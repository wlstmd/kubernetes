# ELK(Elasticsearch + Logstash) 로깅 구성 및 테스트

Logstash와 Filebeat로 EKS 상의 nginx 로그를 수집해서 Amazon Elasticsearch(OpenDistro) 도메인으로 보내고, 테스트 트래픽을 발생시켜 Kibana에서 확인하는 스크립트(`bastion.sh`)입니다.

## Environment variables

클러스터 이름, 계정 ID, 리전, Elasticsearch 도메인 이름/버전/계정 정보를 환경 변수로 지정합니다.

```sh
export EKS_CLUSTER_NAME=skills-eks-cluster
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=ap-northeast-2
export ES_DOMAIN_NAME="skills-logging"
export ES_VERSION="7.10"
export ES_DOMAIN_USER="admin"
export ES_DOMAIN_PASSWORD="$(openssl rand -base64 12)_Ek1$"
```

## Create OIDC provider for EKS

IAM 서비스 어카운트를 쓸 수 있도록 클러스터에 IAM OIDC 프로바이더를 연결합니다.

```sh
eksctl utils associate-iam-oidc-provider \
    --cluster $EKS_CLUSTER_NAME \
    --approve
```

## Add AWS Load Balancer Controller Helm

데모 앱을 외부에 노출하기 위해 AWS Load Balancer Controller를 Helm으로 설치합니다.

```sh
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## Create IAM policy for Logstash

Logstash가 Elasticsearch에 HTTP 요청을 보낼 수 있도록 정책 문서를 작성합니다.

```sh
cat << EOF > logstash-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "es:ESHttp*"
            ],
            "Resource": "arn:aws:es:${AWS_REGION}:${ACCOUNT_ID}:domain/${ES_DOMAIN_NAME}"
        }
    ]
}
EOF
```

## Create IAM policy

위에서 작성한 문서로 실제 IAM 정책을 생성합니다.

```sh
aws iam create-policy \
    --policy-name logstash-policy \
    --policy-document file://logstash-policy.json
```

## Create namespace and service account

`logging` 네임스페이스를 만들고, 위 정책을 붙인 `logstash` IAM 서비스 어카운트를 생성합니다.

```sh
kubectl create namespace logging

eksctl create iamserviceaccount \
    --name logstash \
    --namespace logging \
    --cluster $EKS_CLUSTER_NAME \
    --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/logstash-policy" \
    --override-existing-serviceaccounts \
    --approve
```

## Verify service account

생성된 서비스 어카운트를 확인합니다.

```sh
kubectl -n logging describe serviceaccounts logstash
```

## Create Elasticsearch domain

Elasticsearch(OpenDistro 보안 옵션 포함) 도메인 정의를 작성합니다.

```sh
cat << EOF > es_domain.json
{
    "DomainName": "${ES_DOMAIN_NAME}",
    "ElasticsearchVersion": "${ES_VERSION}",
    "ElasticsearchClusterConfig": {
        "InstanceType": "r5.large.elasticsearch",
        "InstanceCount": 1,
        "DedicatedMasterEnabled": false,
        "ZoneAwarenessEnabled": false,
        "WarmEnabled": false
    },
    "EBSOptions": {
        "EBSEnabled": true,
        "VolumeType": "gp2",
        "VolumeSize": 100
    },
    "AccessPolicies": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":\"es:ESHttp*\",\"Resource\":\"arn:aws:es:${AWS_REGION}:${ACCOUNT_ID}:domain/${ES_DOMAIN_NAME}/*\"}]}",
    "SnapshotOptions": {},
    "CognitoOptions": {
        "Enabled": false
    },
    "EncryptionAtRestOptions": {
        "Enabled": true
    },
    "NodeToNodeEncryptionOptions": {
        "Enabled": true
    },
    "DomainEndpointOptions": {
        "EnforceHTTPS": true,
        "TLSSecurityPolicy": "Policy-Min-TLS-1-0-2019-07"
    },
    "AdvancedSecurityOptions": {
        "Enabled": true,
        "InternalUserDatabaseEnabled": true,
        "MasterUserOptions": {
            "MasterUserName": "${ES_DOMAIN_USER}",
            "MasterUserPassword": "${ES_DOMAIN_PASSWORD}"
        }
    }
}
EOF
```

## Create Elasticsearch domain

위 정의로 실제 Elasticsearch 도메인을 생성합니다.

```sh
aws es create-elasticsearch-domain \
    --cli-input-json file://es_domain.json
```

## Get necessary variables

Logstash IAM 역할 ARN과 ES 엔드포인트를 조회합니다.

```sh
export LOGSTASH_ROLE=$(eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME --namespace logging -o json | jq '.[].status.roleARN' -r)
export ES_ENDPOINT=$(aws es describe-elasticsearch-domain --domain-name ${ES_DOMAIN_NAME} --output text --query "DomainStatus.Endpoint")
```

## Update Elasticsearch security settings

OpenDistro 보안 플러그인의 `all_access` 역할에 Logstash 역할을 매핑합니다.

```sh
curl -sS -u "${ES_DOMAIN_USER}:${ES_DOMAIN_PASSWORD}" \
    -X PATCH \
    https://${ES_ENDPOINT}/_opendistro/_security/api/rolesmapping/all_access?pretty \
    -H 'Content-Type: application/json' \
    -d'
[
  {
    "op": "add", "path": "/backend_roles", "value": ["'${LOGSTASH_ROLE}'"]
  }
]
'
```

## 보안 그룹 인바운드/아웃바운드 규칙 추가

노드 그룹 보안 그룹 ID를 조회해서, Beats(5044)와 5000 포트에 대한 인바운드/아웃바운드 트래픽을 자기 자신에게 허용합니다.

```sh
EKS_NODE_GROUP_SG_ID=$(aws ec2 describe-instances --filter Name=tag:Name,Values=skills-app-node --query "Reservations[1].Instances[].SecurityGroups[].GroupId" --output text)
aws ec2 authorize-security-group-ingress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5044 --source-group $EKS_NODE_GROUP_SG_ID
aws ec2 authorize-security-group-ingress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5000 --source-group $EKS_NODE_GROUP_SG_ID
aws ec2 authorize-security-group-egress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5044 --source-group $EKS_NODE_GROUP_SG_ID
aws ec2 authorize-security-group-egress --group-id $EKS_NODE_GROUP_SG_ID --protocol tcp --port 5000 --source-group $EKS_NODE_GROUP_SG_ID
```

## Create Logstash ConfigMap

Logstash 설정(`logstash.yml`, `logstash.conf` - beats 입력, grok 필터, elasticsearch 출력)을 담은 ConfigMap을 작성합니다.

```sh
cat << EOF > logstash-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: logstash-config
  namespace: logging
data:
  logstash.yml: |
    http.host: "0.0.0.0"
    path.config: /usr/share/logstash/pipeline
  logstash.conf: |
    input {
      beats {
        port => 5044
      }
    }
    
    filter {
      grok {
        match => { "message" => "%{COMBINEDAPACHELOG}" }
      }
      date {
        match => [ "timestamp" , "dd/MMM/yyyy:HH:mm:ss Z" ]
      }
    }
    
    output {
      elasticsearch {
        hosts => ["https://${ES_ENDPOINT}:443"]
        ssl => true
        user => "${ES_DOMAIN_USER}"
        password => "${ES_DOMAIN_PASSWORD}"
        index => "logstash-%{+YYYY.MM.dd}"
        ilm_enabled => false
      }
    }
EOF
```

## Apply Logstash ConfigMap

작성한 ConfigMap을 클러스터에 적용합니다.

```sh
kubectl apply -f logstash-config.yaml
```

## Create Logstash Deployment

Logstash 배포와 서비스를 정의합니다.

```sh
cat << EOF > logstash-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logstash
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: logstash
  template:
    metadata:
      labels:
        app: logstash
    spec:
      serviceAccountName: logstash
      containers:
      - name: logstash
        image: docker.elastic.co/logstash/logstash:7.10.2
        ports:
        - containerPort: 5044
        volumeMounts:
        - name: config-volume
          mountPath: /usr/share/logstash/config
        - name: pipeline-volume
          mountPath: /usr/share/logstash/pipeline
      volumes:
      - name: config-volume
        configMap:
          name: logstash-config
          items:
            - key: logstash.yml
              path: logstash.yml
      - name: pipeline-volume
        configMap:
          name: logstash-config
          items:
            - key: logstash.conf
              path: logstash.conf
---
apiVersion: v1
kind: Service
metadata:
  name: logstash
  namespace: logging
spec:
  type: ClusterIP
  ports:
  - port: 5044
    targetPort: 5044
    protocol: TCP
  selector:
    app: logstash
EOF
```

## Apply Logstash deployment

Logstash 배포/서비스를 클러스터에 적용합니다.

```sh
kubectl apply -f logstash-deployment.yaml
```

## Check deployment status

Logstash 파드 상태를 확인합니다.

```sh
kubectl -n logging get pods -o wide
```

## 데모 애플리케이션(nginx + filebeat) 배포

nginx와 filebeat 사이드카를 함께 띄우는 데모 앱과, 이를 외부에 노출할 LoadBalancer 서비스를 생성합니다.

```sh
cat << EOF > demo-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: demo-app
        image: nginx:latest
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-logs
          mountPath: /var/log/nginx
      - name: filebeat
        image: docker.elastic.co/beats/filebeat:7.10.2
        volumeMounts:
        - name: nginx-logs
          mountPath: /var/log/nginx
        - name: filebeat-config
          mountPath: /usr/share/filebeat/filebeat.yml
          subPath: filebeat.yml
      volumes:
      - name: nginx-logs
        emptyDir: {}
      - name: filebeat-config
        configMap:
          name: filebeat-config
          items:
            - key: filebeat.yml
              path: filebeat.yml
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
  namespace: logging
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: demo-app
---
EOF
kubectl apply -f demo-app.yaml
```

## Filebeat 설정 배포

nginx access/error 로그를 읽어 Logstash로 보내는 filebeat 설정을 ConfigMap으로 작성하고 적용합니다.

```sh
cat << EOF > filebeat-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
  namespace: logging
data:
  filebeat.yml: |
    filebeat.inputs:
    - type: log
      enabled: true
      paths:
        - /var/log/nginx/access.log
      fields:
        app: demo-app
        type: nginx-access
      fields_under_root: true

    - type: log
      enabled: true
      paths:
        - /var/log/nginx/error.log
      fields:
        app: demo-app
        type: nginx-error
      fields_under_root: true

    output.logstash:
      hosts: ["logstash.logging.svc.cluster.local:5044"]

    logging.json: true
    logging.metrics.enabled: false
---
EOF
kubectl apply -f filebeat-config.yaml
```

## Nginx 설정 배포

demo-app의 nginx 설정(access_log/error_log 경로, `/error` 500 응답 등)을 ConfigMap으로 작성하고 적용합니다.

```sh
cat << EOF > nginx-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: logging
data:
  nginx.conf: |
    user  nginx;
    worker_processes  1;

    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;

    events {
        worker_connections  1024;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                         '$status $body_bytes_sent "$http_referer" '
                         '"$http_user_agent" "$http_x_forwarded_for"';

        access_log  /var/log/nginx/access.log  main;

        sendfile        on;
        keepalive_timeout  65;

        server {
            listen       80;
            server_name  localhost;

            location / {
                root   /usr/share/nginx/html;
                index  index.html index.htm;
            }

            location /error {
                return 500;
            }
        }
    }
EOF
kubectl apply -f nginx-config.yaml
```

## 서비스 IP 확인

데모 앱 LoadBalancer 서비스의 외부 주소를 조회합니다.

```sh
export SERVICE_IP=$(kubectl -n logging get svc demo-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

## 일반 접속 로그 생성

정상 요청을 보내 access 로그를 생성합니다.

```sh
curl http://$SERVICE_IP/
```

## 에러 로그 생성

`/error` 경로로 요청을 보내 error 로그를 생성합니다.

```sh
curl http://$SERVICE_IP/error
```

## Print access information

Kibana 접속 URL과 계정 정보를 출력합니다.

```sh
echo "Kibana URL: https://${ES_ENDPOINT}/_plugin/kibana/"
echo "Kibana user: ${ES_DOMAIN_USER}"
echo "Kibana password: ${ES_DOMAIN_PASSWORD}"
```
