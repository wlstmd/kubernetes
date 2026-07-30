# ACK RDS 컨트롤러를 이용한 RDS 인스턴스 관리

ACK(AWS Controllers for Kubernetes) RDS 컨트롤러를 설치하고, 쿠버네티스 매니페스트로 DB 서브넷 그룹과 RDS(MariaDB) 인스턴스를 생성한 뒤 FieldExport로 연결 정보를 ConfigMap에 노출시켜 파드에서 사용하는 실습입니다.

## 변수 지정

```sh
export SERVICE=rds
export EKS_CLUSTER_NAME=skills-eks-cluster
export AWS_REGION=ap-northeast-2

export RELEASE_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/$SERVICE-controller/releases/latest | grep '"tag_name":' | cut -d'"' -f4 | cut -c 2-)
helm pull oci://public.ecr.aws/aws-controllers-k8s/$SERVICE-chart --version=$RELEASE_VERSION
tar xzvf $SERVICE-chart-$RELEASE_VERSION.tgz
```

## ACK RDS Controller 설치

```sh
helm install -n ack-system ack-$SERVICE-controller --set aws.region="$AWS_REGION" ~/$SERVICE-chart
```

## 설치 확인

```sh
helm list --namespace ack-system
kubectl -n ack-system get pods -l "app.kubernetes.io/instance=ack-$SERVICE-controller"
kubectl get crd | grep $SERVICE
```

## IAM 서비스 계정 생성 및 권한 부여

```sh
eksctl create iamserviceaccount \
  --name ack-$SERVICE-controller \
  --region=ap-northeast-2 \
  --namespace ack-system \
  --cluster $EKS_CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess \
  --override-existing-serviceaccounts \
  --approve
```

## IAM 서비스 계정 확인

```sh
eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME
```

## 서비스 계정 확인

```sh
kubectl get sa -n ack-system
kubectl describe sa ack-$SERVICE-controller -n ack-system
```

## ACK RDS Controller 재시작

```sh
kubectl -n ack-system rollout restart deploy ack-$SERVICE-controller-$SERVICE-chart
```

## Pod 설명

```sh
kubectl describe pod -n ack-system -l k8s-app=$SERVICE-chart
```

## DB 암호를 위한 secret 생성

```sh
export RDS_INSTANCE_NAME=skills-rds

export RDS_INSTANCE_PASSWORD=cloudadmin

kubectl create secret generic "${RDS_INSTANCE_NAME}-password" --from-literal=password="${RDS_INSTANCE_PASSWORD}"
```

## secret 확인

```sh
kubectl get secret $RDS_INSTANCE_NAME-password
```

## DB 인스턴스 상태 확인

```sh
watch -d "kubectl describe dbinstance "${RDS_INSTANCE_NAME}" | grep 'Db Instance Status'"
```

## 서브넷 ID 확인

```sh
SUBNET_ID_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-potected-subnet-a" --query "Subnets[0].SubnetId" --output text)
SUBNET_ID_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-potected-subnet-b" --query "Subnets[0].SubnetId" --output text)
```

## 서브넷 그룹 매니페스트 생성

```sh
cat << EOF > subnet-group.yaml
apiVersion: rds.services.k8s.aws/v1alpha1
kind: DBSubnetGroup
metadata:
  name: skills-rds-subnet-group
spec:
  name: skills-rds-subnet-group
  description: "Subnet group for RDS instance"
  subnetIDs:
    - $SUBNET_ID_1
    - $SUBNET_ID_2
EOF
```

## 서브넷 그룹 생성

```sh
kubectl apply -f subnet-group.yaml
```

## RDS 인스턴스 매니페스트 생성

```sh
cat << EOF > rds-mariadb.yaml
apiVersion: rds.services.k8s.aws/v1alpha1
kind: DBInstance
metadata:
  name: "${RDS_INSTANCE_NAME}"
spec:
  allocatedStorage: 20
  dbInstanceClass: db.t4g.micro
  dbInstanceIdentifier: "${RDS_INSTANCE_NAME}"
  engine: mariadb
  engineVersion: "10.11"
  masterUsername: "admin"
  masterUserPassword:
    namespace: default
    name: "${RDS_INSTANCE_NAME}-password"
    key: password
  dbSubnetGroupName: skills-rds-subnet-group
EOF
```

## RDS 인스턴스 생성

```sh
kubectl apply -f rds-mariadb.yaml
```

## RDS 인스턴스 확인

```sh
kubectl get dbinstances ${RDS_INSTANCE_NAME}
kubectl describe dbinstance "${RDS_INSTANCE_NAME}"
aws rds describe-db-instances --db-instance-identifier $RDS_INSTANCE_NAME | jq
```

## RDS 인스턴스 상태 확인

```sh
kubectl describe dbinstance "${RDS_INSTANCE_NAME}" | grep 'Db Instance Status'
```

## RDS 인스턴스 동기화 상태 대기

```sh
kubectl wait dbinstances ${RDS_INSTANCE_NAME} --for=condition=ACK.ResourceSynced --timeout=15m
```

---

## RDS 인스턴스 연결 정보를 위한 ConfigMap 생성

FieldExport 리소스로 DBInstance의 상태값(엔드포인트 주소/포트, 마스터 사용자명)을 ConfigMap에 자동으로 내보냅니다.

```sh
RDS_INSTANCE_CONN_CM="${RDS_INSTANCE_NAME}-conn-cm"

cat << EOF > rds-field-exports.yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${RDS_INSTANCE_CONN_CM}
data: {}
---
apiVersion: services.k8s.aws/v1alpha1
kind: FieldExport
metadata:
  name: ${RDS_INSTANCE_NAME}-host
spec:
  to:
    name: ${RDS_INSTANCE_CONN_CM}
    kind: configmap
  from:
    path: ".status.endpoint.address"
    resource:
      group: rds.services.k8s.aws
      kind: DBInstance
      name: ${RDS_INSTANCE_NAME}
---
apiVersion: services.k8s.aws/v1alpha1
kind: FieldExport
metadata:
  name: ${RDS_INSTANCE_NAME}-port
spec:
  to:
    name: ${RDS_INSTANCE_CONN_CM}
    kind: configmap
  from:
    path: ".status.endpoint.port"
    resource:
      group: rds.services.k8s.aws
      kind: DBInstance
      name: ${RDS_INSTANCE_NAME}
---
apiVersion: services.k8s.aws/v1alpha1
kind: FieldExport
metadata:
  name: ${RDS_INSTANCE_NAME}-user
spec:
  to:
    name: ${RDS_INSTANCE_CONN_CM}
    kind: configmap
  from:
    path: ".spec.masterUsername"
    resource:
      group: rds.services.k8s.aws
      kind: DBInstance
      name: ${RDS_INSTANCE_NAME}
EOF

kubectl apply -f rds-field-exports.yaml
```

## 상태 정보 확인 : address 와 port 정보

```sh
kubectl get dbinstances skills-rds -o jsonpath={.status.endpoint} | jq
```

## 상태 정보 확인 : masterUsername 확인

```sh
kubectl get dbinstances skills-rds -o jsonpath={.spec.masterUsername} ; echo
```

## ConfigMap 확인

```sh
kubectl get cm skills-rds-conn-cm -o yaml
```

## fieldexport 정보 확인

```sh
kubectl get crd | grep fieldexport
kubectl get fieldexport
```

## 파드 생성

FieldExport로 노출된 ConfigMap과 DB 암호 Secret을 환경 변수로 주입하는 테스트 파드를 생성합니다.

```sh
APP_NAMESPACE=default
cat << EOF > rds-pods.yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: ${APP_NAMESPACE}
spec:
  containers:
   - image: busybox
     name: myapp
     command:
        - sleep
        - "3600"
     imagePullPolicy: IfNotPresent
     env:
      - name: DBHOST
        valueFrom:
         configMapKeyRef:
          name: ${RDS_INSTANCE_CONN_CM}
          key: "${APP_NAMESPACE}.${RDS_INSTANCE_NAME}-host"
      - name: DBPORT
        valueFrom:
         configMapKeyRef:
          name: ${RDS_INSTANCE_CONN_CM}
          key: "${APP_NAMESPACE}.${RDS_INSTANCE_NAME}-port"
      - name: DBUSER
        valueFrom:
         configMapKeyRef:
          name: ${RDS_INSTANCE_CONN_CM}
          key: "${APP_NAMESPACE}.${RDS_INSTANCE_NAME}-user"
      - name: DBPASSWORD
        valueFrom:
          secretKeyRef:
           name: "${RDS_INSTANCE_NAME}-password"
           key: password
EOF
kubectl apply -f rds-pods.yaml
```

## 생성 확인

```sh
kubectl get pod app
```

## 파드의 환경 변수 확인

```sh
kubectl exec -it app -- env | grep DB
```

## RDS 인스턴스 이름 변경

```sh
aws rds modify-db-instance --db-instance-identifier $RDS_INSTANCE_NAME --new-db-instance-identifier studyend --apply-immediately
```

## RDS 인스턴스 이름 변경 확인

```sh
kubectl patch dbinstance skills-rds --type=merge -p '{"spec":{"dbInstanceIdentifier":"studyend"}}'

kubectl get dbinstance skills-rds
kubectl describe dbinstance skills-rds
```

## 상태 정보 확인 : address 변경 확인!

```sh
kubectl get dbinstances skills-rds -o jsonpath={.status.endpoint} | jq

kubectl exec -it app -- env | grep DB
```

## 파드 삭제 후 재생성 후 확인

```sh
kubectl delete pod app && kubectl apply -f rds-pods.yaml

kubectl exec -it app -- env | grep DB
```

## 상태 정보 확인 : address 와 port 정보 (재확인)

```sh
kubectl get dbinstances skills-rds -o jsonpath={.status.endpoint} | jq
```

## 상태 정보 확인 : masterUsername 확인 (재확인)

```sh
kubectl get dbinstances skills-rds -o jsonpath={.spec.masterUsername} ; echo

kubectl get crd | grep fieldexport
kubectl get fieldexport
```
