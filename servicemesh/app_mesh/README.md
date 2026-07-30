# AWS App Mesh 실습

## 개요

`AWS App Mesh`는 애플리케이션의 서비스 간 통신을 쉽게 모니터링하고 제어할 수 있는 서비스 메시입니다.
`서비스 메시`는 네트워크 프록시를 통해 서비스 간의 통신을 처리하는 인프라 계층입니다.

| App Mesh는 서비스 간 통신을 표준화하여 애플리케이션의 가시성과 고가용성을 보장합니다.

`주요 구성 요소`

- 서비스 메시: 서비스 간의 네트워크 트래픽을 관리하는 논리적 경계입니다.
- 가상 서비스: 실제 서비스의 추상화로, 서비스 간 통신을 위한 이름을 제공합니다.
- 가상 노드: 검색 가능한 서비스에 대한 논리 포인터입니다.
- 가상 라우터 및 경로: 트래픽을 처리하고 특정 기준에 따라 트래픽을 라우팅합니다.
- 프록시: App Mesh 구성을 읽고 트래픽을 적절하게 전달합니다.

`예제`

기존 애플리케이션에서 serviceA가 serviceB와 통신한다고 가정합니다. serviceB의 새 버전 serviceBv2를 배포하고, serviceA의 트래픽을 두 서비스로 나누어 보내고 싶다면, App Mesh를 사용하면 애플리케이션 코드를 변경하지 않고도 이를 쉽게 설정할 수 있습니다.

App Mesh를 사용하면 서비스 간 통신이 프록시를 통해 이루어지며, 프록시는 App Mesh 구성을 읽고 트래픽을 적절하게 라우팅합니다. 이를 통해 서비스 간 통신 방식을 유연하게 제어할 수 있습니다.

- 가상 서비스: 여러 가상 노드를 하나의 서비스로 묶는 추상화.
- 가상 노드: 실제 서비스 인스턴스를 나타내는 논리 포인터.
- 가상 라우터: 트래픽을 여러 가상 노드로 분배하는 역할.


## ENV
```sh
CLUSTER_NAME=<CLUSTER_NAME>
AWS_REGION=<REGION_CODE>
```

## App Mesh 설치 가능 여부 검증
```sh
curl -o pre_upgrade_check.sh https://raw.githubusercontent.com/aws/eks-charts/master/stable/appmesh-controller/upgrade/pre_upgrade_check.sh
sh ./pre_upgrade_check.sh
```

## Repo
```sh
helm repo add eks https://aws.github.io/eks-charts
```

## CRD (CustomerResourceDefinition)
```sh
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"
```

## NS
```sh
kubectl create ns appmesh-system
```

## OIDC
```sh
eksctl utils associate-iam-oidc-provider \
    --region=$AWS_REGION \
    --cluster $CLUSTER_NAME \
    --approve
```

## IRSA
```sh
eksctl create iamserviceaccount \
    --cluster $CLUSTER_NAME \
    --namespace appmesh-system \
    --name appmesh-controller \
    --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
    --override-existing-serviceaccounts \
    --approve
```

## appmesh-controller 설치
```sh
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=$AWS_REGION \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller
```

## AWS App Mesh 리소스 배포
```sh
kubectl apply -f namespace.yaml 
kubectl apply -f mesh.yaml
```

## Kubernetes 메시 리소스의 세부 정보 확인
```sh
kubectl describe mesh my-mesh
```

## 컨트롤러가 생성한 App Mesh 서비스 메시에 대한 세부 정보 확인
```sh
aws appmesh describe-mesh --mesh-name my-mesh
```

## Virtual Node
```sh
kubectl apply -f virtual-node.yaml
kubectl describe virtualnode my-service-a -n my-apps
```

## Virtual Router
```sh
kubectl apply -f virtual-router.yaml
kubectl describe virtualrouter my-service-a-virtual-router -n my-apps
```

## Virtual Service
```sh
kubectl apply -f virtual-service.yaml
kubectl describe virtualservice my-service-a -n my-apps
```

## Proxy Auth
```sh
cat << EOF > proxy-auth.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "appmesh:StreamAggregatedResources",
      "Resource": [
        "arn:aws:appmesh:ap-northeast-2:362708816803:mesh/my-mesh/virtualNode/my-service-a_my-apps"
      ]
    }
  ]
}
EOF
```

## Policy 생성
```sh
aws iam create-policy --policy-name my-policy --policy-document file://proxy-auth.json

eksctl create iamserviceaccount \
    --cluster $CLUSTER_NAME \
    --namespace my-apps \
    --name my-service-a \
    --attach-policy-arn  arn:aws:iam::362708816803:policy/my-policy \
    --override-existing-serviceaccounts \
    --approve
```

## Service
```sh
kubectl apply -f service.yaml

kubectl -n my-apps get pods
```

## Delete
```sh
kubectl delete namespace my-apps
kubectl delete mesh my-mesh
helm delete appmesh-controller -n appmesh-system
```
