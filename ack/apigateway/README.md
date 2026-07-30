# ACK API Gateway 설치 및 구성

ACK(AWS Controllers for Kubernetes) APIGatewayv2 컨트롤러를 설치하고, AWS Load Balancer Controller 및 VPC Link를 통해 내부 NLB를 API Gateway와 연동하는 실습.

## 변수 지정

```sh
export SERVICE=apigatewayv2
export ACK_SYSTEM_NAMESPACE=ack-system
export AWS_REGION=ap-northeast-2
export EKS_CLUSTER_NAME=skills-eks-cluster
export EKS_NODE_GROUP_NAME=skills-app-nodegroup
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

## HELM 차트 Install

```sh
export RELEASE_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/$SERVICE-controller/releases/latest | grep '"tag_name":' | cut -d'"' -f4 | cut -c 2-)
helm pull oci://public.ecr.aws/aws-controllers-k8s/$SERVICE-chart --version=$RELEASE_VERSION
tar xzvf $SERVICE-chart-$RELEASE_VERSION.tgz
```

## ACK APIGateway2 Controller 설치

```sh
helm install --create-namespace --namespace $ACK_SYSTEM_NAMESPACE ack-$SERVICE-controller --set aws.region="$AWS_REGION" ~/$SERVICE-chart
```

## 설치 확인

```sh
helm list --namespace $ACK_SYSTEM_NAMESPACE
kubectl -n ack-system get pods -l "app.kubernetes.io/instance=ack-apigatewayv2-controller"
kubectl get crd | grep apigatewayv2
```

## AWS Load Balancer Controller 설치

```sh
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

eksctl create iamserviceaccount \
  --cluster=$EKS_CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## 노드 그룹에 권한 부여

```sh
NODEGROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query "nodegroup.nodeRole" --output text | cut -d'/' -f2-)
aws iam attach-role-policy --role-name $NODEGROUP_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonAPIGatewayAdministrator
```

## 애플리케이션 배포

```sh
kubectl apply -f echoserver.yml
kubectl apply -f author-deployment.yml
```

## 배포 확인

```sh
kubectl get deploy,svc
```

## NLB DNS 확인

```sh
NLB1DNS=$(kubectl get svc authorservice -o jsonpath={.status.loadBalancer.ingress[0].hostname})
dig +short $NLB1DNS

NLB2DNS=$(kubectl get svc echoserver -o jsonpath={.status.loadBalancer.ingress[0].hostname})
dig +short $NLB2DNS
```

## VPC Link 가 사용할 보안그룹 생성

```sh
VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)
VPCLINK_SG=$(aws ec2 create-security-group \
  --description "SG for VPC Link" \
  --group-name SG_VPC_LINK \
  --vpc-id $VPC_ID \
  --region $AWS_REGION \
  --output text \
  --query 'GroupId')
```

## VPC Link 생성

```sh
cat << EOF > vpclink.yaml
apiVersion: apigatewayv2.services.k8s.aws/v1alpha1
kind: VPCLink
metadata:
  name: nlb-internal
spec:
  name: nlb-internal
  securityGroupIDs: 
    - $VPCLINK_SG
  subnetIDs: 
    - $(aws ec2 describe-subnets \
          --filter Name=tag:kubernetes.io/role/internal-elb,Values=1 \
          --query 'Subnets[0].SubnetId' \
          --region $AWS_REGION --output text)
    - $(aws ec2 describe-subnets \
          --filter Name=tag:kubernetes.io/role/internal-elb,Values=1 \
          --query 'Subnets[1].SubnetId' \
          --region $AWS_REGION --output text)
EOF

kubectl apply -f vpclink.yaml
```

## VPC Link 생성 확인

```sh
kubectl describe vpclink nlb-internal | grep 'Vpc Link'
aws apigatewayv2 get-vpc-links | jq
```

## API GW 생성 (VPC Link 연동)

```sh
cat << EOF > apigw-api.yaml
apiVersion: apigatewayv2.services.k8s.aws/v1alpha1
kind: API
metadata:
  name: apitest-private-nlb
spec:
  body: '{
              "openapi": "3.0.1",
              "info": {
                "title": "ack-apigwv2-import-test-private-nlb",
                "version": "v1"
              },
              "paths": {
              "/\$default": {
                "x-amazon-apigateway-any-method" : {
                "isDefaultRoute" : true,
                "x-amazon-apigateway-integration" : {
                "payloadFormatVersion" : "1.0",
                "connectionId" : "$(kubectl get vpclinks.apigatewayv2.services.k8s.aws \
  nlb-internal \
  -o jsonpath="{.status.vpcLinkID}")",
                "type" : "http_proxy",
                "httpMethod" : "GET",
                "uri" : "$(aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers \
  --region $AWS_REGION \
  --query "LoadBalancers[?contains(DNSName, '$(kubectl get service authorservice \
  -o jsonpath="{.status.loadBalancer.ingress[].hostname}")')].LoadBalancerArn" \
  --output text) \
  --region $AWS_REGION \
  --query "Listeners[0].ListenerArn" \
  --output text)",
               "connectionType" : "VPC_LINK"
                  }
                }
              },
              "/meta": {
                  "get": {
                    "x-amazon-apigateway-integration": {
                       "uri" : "$(aws elbv2 describe-listeners \
  --load-balancer-arn $(aws elbv2 describe-load-balancers \
  --region $AWS_REGION \
  --query "LoadBalancers[?contains(DNSName, '$(kubectl get service echoserver \
  -o jsonpath="{.status.loadBalancer.ingress[].hostname}")')].LoadBalancerArn" \
  --output text) \
  --region $AWS_REGION \
  --query "Listeners[0].ListenerArn" \
  --output text)",
                      "httpMethod": "GET",
                      "connectionId": "$(kubectl get vpclinks.apigatewayv2.services.k8s.aws \
  nlb-internal \
  -o jsonpath="{.status.vpcLinkID}")",
                      "type": "HTTP_PROXY",
                      "connectionType": "VPC_LINK",
                      "payloadFormatVersion": "1.0"
                    }
                  }
                }
              },
              "components": {}
        }'
EOF

kubectl apply -f apigw-api.yaml
```

## stage 생성

```sh
cat << EOF | kubectl apply -f -
apiVersion: apigatewayv2.services.k8s.aws/v1alpha1
kind: Stage
metadata:
  name: "apiv1"
spec:
  apiID: $(kubectl get apis.apigatewayv2.services.k8s.aws apitest-private-nlb -o=jsonpath='{.status.apiID}')
  stageName: api
  autoDeploy: true
EOF
```

## stage URL 호출 정보 확인

```sh
kubectl get api apitest-private-nlb -o jsonpath={.status.apiEndpoint}
```

## 서비스 호출

```sh
curl -s $(kubectl get api apitest-private-nlb -o jsonpath="{.status.apiEndpoint}")/api/author/ | head
curl -s $(kubectl get api apitest-private-nlb -o jsonpath="{.status.apiEndpoint}")/api/meta | head
```

## 파드에서 접속 로그 확인

```sh
kubectl logs -l app=author --since=1h
kubectl logs -l app=echoserver --since=1h
```

## API GW 와 NLB 관련 리소스 삭제

```sh
kubectl delete stages.apigatewayv2.services.k8s.aws apiv1
kubectl delete apis.apigatewayv2.services.k8s.aws apitest-private-nlb
kubectl delete vpclinks.apigatewayv2.services.k8s.aws nlb-internal 
kubectl delete service echoserver  # NLB 삭제
kubectl delete services authorservice  # NLB 삭제
sleep 10 # 10초 정도 후 아래 VPC Link 삭제 진행
```

## VPC Link 가 사용했던 보안그룹 삭제

```sh
aws ec2 delete-security-group --group-id $VPCLINK_SG --region $AWS_REGION 
```

## ACK APIGateway2 Controller 삭제

```sh
helm uninstall -n $ACK_SYSTEM_NAMESPACE ack-$SERVICE-controller
```

## ACK APIGateway2 Controller 관련 crd 삭제

```sh
kubectl delete -f ~/$SERVICE-chart/crds/
```

## ACK APIGateway2 Controller 관련 namespace 삭제

```sh
kubectl delete namespace $ACK_SYSTEM_NAMESPACE
```

## AWS Load Balancer controller 삭제

```sh
helm uninstall -n kube-system aws-load-balancer-controller
```

## AWS IAM Role 삭제

```sh
eksctl delete iamserviceaccount --cluster=$EKS_CLUSTER_NAME --namespace=kube-system --name=aws-load-balancer-controller
```
