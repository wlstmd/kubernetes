# AWS App Mesh 실습

## 개요

AWS App Mesh는 서비스 간 통신을 프록시로 처리하는 서비스 메시. 트래픽을 표준화해서 가시성과 고가용성을 확보한다.

- 가상 서비스: 여러 가상 노드를 하나로 묶는 추상화, 서비스 간 통신에 쓰이는 이름을 제공.
- 가상 노드: 실제 서비스 인스턴스를 가리키는 논리 포인터.
- 가상 라우터/경로: 특정 기준에 따라 트래픽을 여러 가상 노드로 분배.
- 프록시: App Mesh 구성을 읽고 트래픽을 라우팅.

예: serviceA가 serviceB와 통신 중일 때 serviceB의 새 버전 serviceBv2를 배포하고 트래픽을 두 버전으로 나누고 싶다면, 애플리케이션 코드 변경 없이 App Mesh 설정만으로 처리할 수 있다.


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
