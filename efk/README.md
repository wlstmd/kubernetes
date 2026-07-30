# EFK(Fluent Bit + Elasticsearch/Kibana) 로깅 구성

Fluent Bit로 EKS 로그를 수집해서 Amazon Elasticsearch(OpenDistro) 도메인으로 보내고, Kibana로 조회할 수 있도록 구성하는 스크립트(`bastion.sh`)입니다.

## 환경 변수 설정

클러스터 이름, 계정 ID, 리전, Elasticsearch 도메인 이름/버전/계정 정보를 환경 변수로 지정합니다.

```sh
export EKS_CLUSTER_NAME=skills-eks-cluster
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=ap-northeast-2
export ES_DOMAIN_NAME="skills-logging" # Elasticsearch domain name
export ES_VERSION="7.10" # Elasticsearch version
export ES_DOMAIN_USER="admin" # kibana admin user
export ES_DOMAIN_PASSWORD="$(openssl rand -base64 12)_Ek1$" 
```

## OIDC 프로바이더 연결

IAM 서비스 어카운트를 쓸 수 있도록 클러스터에 IAM OIDC 프로바이더를 연결합니다.

```sh
eksctl utils associate-iam-oidc-provider \
    --cluster $EKS_CLUSTER_NAME \
    --approve
```

## Fluent Bit IAM 정책 생성

Fluent Bit가 Elasticsearch에 HTTP 요청을 보낼 수 있도록 정책 문서를 작성하고 IAM 정책으로 생성합니다.

```sh
cat << EOF > fluent-bit-policy.json
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

aws iam create-policy   \
  --policy-name fluent-bit-policy \
  --policy-document file://fluent-bit-policy.json
```

## 로깅 네임스페이스 및 Fluent Bit 서비스 어카운트 생성

`logging` 네임스페이스를 만들고, 위 정책을 붙인 `fluent-bit` IAM 서비스 어카운트를 생성/확인합니다.

```sh
kubectl create namespace logging

eksctl create iamserviceaccount \
    --name fluent-bit \
    --namespace logging \
    --cluster $EKS_CLUSTER_NAME \
    --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/fluent-bit-policy" \
    --override-existing-serviceaccounts \
    --approve

kubectl -n logging describe serviceaccounts fluent-bit
```

## Elasticsearch 도메인 생성

Elasticsearch(OpenDistro 보안 옵션 포함) 도메인 정의를 작성하고 생성합니다.

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
    "AccessPolicies":  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"*\"},\"Action\":\"es:ESHttp*\",\"Resource\":\"arn:aws:es:${AWS_REGION}:${ACCOUNT_ID}:domain/${ES_DOMAIN_NAME}/*\"}]}",
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

aws es create-elasticsearch-domain \
  --cli-input-json  file://es_domain.json
```

## Fluent Bit 역할 매핑 등록

Fluent Bit IAM 역할 ARN과 ES 엔드포인트를 조회한 뒤, OpenDistro 보안 플러그인의 `all_access` 역할에 Fluent Bit 역할을 매핑합니다.

```sh
export FLUENTBIT_ROLE=$(eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME --namespace logging -o json | jq '.[].status.roleARN' -r) 
export ES_ENDPOINT=$(aws es describe-elasticsearch-domain --domain-name ${ES_DOMAIN_NAME} --output text --query "DomainStatus.Endpoint")

curl -sS -u "${ES_DOMAIN_USER}:${ES_DOMAIN_PASSWORD}" \
    -X PATCH \
    https://${ES_ENDPOINT}/_opendistro/_security/api/rolesmapping/all_access?pretty \
    -H 'Content-Type: application/json' \
    -d'
[
  {
    "op": "add", "path": "/backend_roles", "value": ["'${FLUENTBIT_ROLE}'"]
  }
]
'
```

## Fluent Bit 배포 및 확인

`fluentbit.yaml`로 Fluent Bit를 배포하고, 파드 상태와 Kibana 접속 정보를 출력합니다.

```sh
kubectl apply -f fluentbit.yaml

kubectl -n logging get pods -o wide

echo "Kibana URL: https://${ES_ENDPOINT}/_plugin/kibana/
Kibana user: ${ES_DOMAIN_USER}
Kibana password: ${ES_DOMAIN_PASSWORD}"
```
