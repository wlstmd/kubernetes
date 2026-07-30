# GatewayAPI (VPC Lattice) 클러스터 구성

EKS 클러스터를 생성하고 AWS Gateway API Controller(VPC Lattice)를 설치한 뒤, Gateway/HTTPRoute로 서비스 간 트래픽을 연결하고 테스트하는 실습입니다. `bastion.sh`(클러스터 생성 + 컨트롤러 설치 + 서비스 배포/테스트)를 먼저 실행하고, 이후 `init.sh`(CloudFormation 기반 인프라 배포 + 서비스 확인)를 실행하는 흐름입니다.

## bastion.sh — 클러스터 생성 및 Gateway API 컨트롤러 설치

### 서브넷 조회, cluster.yaml 값 치환 및 클러스터 생성

`LatticeWorkshop-Client-*` 태그의 퍼블릭/프라이빗(3개 AZ) 서브넷 ID를 조회해 `cluster.yaml`에 채워 넣고, `eksctl`로 클러스터를 생성합니다.

```sh
#!/bin/bash
public_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PublicSubnet01" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
public_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PublicSubnet02" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
public_c=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PublicSubnet03" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PrivateSubnet01" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PrivateSubnet02" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_c=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PrivateSubnet03" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)

sed -i "s|public_a|$public_a|g" cluster.yaml
sed -i "s|public_b|$public_b|g" cluster.yaml
sed -i "s|public_c|$public_c|g" cluster.yaml
sed -i "s|private_a|$private_a|g" cluster.yaml
sed -i "s|private_b|$private_b|g" cluster.yaml
sed -i "s|private_c|$private_c|g" cluster.yaml

eksctl create cluster -f cluster.yaml
```

### VPC Lattice용 보안 그룹 및 프리픽스 리스트 허용

클러스터 보안 그룹에 VPC Lattice(IPv4/IPv6) 관리형 프리픽스 리스트로부터의 인바운드 트래픽을 허용합니다.

```sh
export EKS_CLUSTER_NAME=gw-eks-cluster
export AWS_REGION=ap-northeast-2

CLUSTER_SG=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --output json| jq -r '.cluster.resourcesVpcConfig.clusterSecurityGroupId')
PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists --query "PrefixLists[?PrefixListName=="\'com.amazonaws.$AWS_REGION.vpc-lattice\'"].PrefixListId" | jq -r '.[]')
aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --ip-permissions "PrefixListIds=[{PrefixListId=${PREFIX_LIST_ID}}],IpProtocol=-1"
PREFIX_LIST_ID_IPV6=$(aws ec2 describe-managed-prefix-lists --query "PrefixLists[?PrefixListName=="\'com.amazonaws.$AWS_REGION.ipv6.vpc-lattice\'"].PrefixListId" | jq -r '.[]')
aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --ip-permissions "PrefixListIds=[{PrefixListId=${PREFIX_LIST_ID_IPV6}}],IpProtocol=-1"
```

### VPC Lattice IAM 정책 및 컨트롤러 네임스페이스 준비

Gateway API Controller에 필요한 IAM 정책을 생성하고, 컨트롤러가 배포될 네임스페이스를 만든 뒤 EKS Pod Identity Agent 애드온을 설치·확인합니다.

```sh
curl https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/recommended-inline-policy.json  -o recommended-inline-policy.json

aws iam create-policy \
    --policy-name VPCLatticeControllerIAMPolicy \
    --policy-document file://recommended-inline-policy.json

export VPCLatticeControllerIAMPolicyArn=$(aws iam list-policies --query 'Policies[?PolicyName==`VPCLatticeControllerIAMPolicy`].Arn' --output text)

kubectl create ns aws-application-networking-system

aws eks create-addon --cluster-name $EKS_CLUSTER_NAME --addon-name eks-pod-identity-agent --addon-version v1.0.0-eksbuild.1

kubectl get pods -n kube-system | grep 'eks-pod-identity-agent'
```

### Gateway API 컨트롤러 서비스 어카운트 및 IAM Role/Pod Identity 연결

컨트롤러용 서비스 어카운트를 만들고, EKS Pod Identity가 assume할 수 있는 IAM Role을 생성해 정책을 붙인 뒤 Pod Identity Association으로 연결합니다.

```sh
cat << EOF > gateway-api-controller-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
    name: gateway-api-controller
    namespace: aws-application-networking-system
EOF
kubectl apply -f gateway-api-controller-service-account.yaml

cat << EOF > trust-relationship.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowEksAuthToAssumeRoleForPodIdentity",
            "Effect": "Allow",
            "Principal": {
                "Service": "pods.eks.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
            ]
        }
    ]
}
EOF

aws iam create-role --role-name VPCLatticeControllerIAMRole --assume-role-policy-document file://trust-relationship.json --description "IAM Role for AWS Gateway API Controller for VPC Lattice"

aws iam attach-role-policy --role-name VPCLatticeControllerIAMRole --policy-arn=$VPCLatticeControllerIAMPolicyArn

export VPCLatticeControllerIAMRoleArn=$(aws iam list-roles --query 'Roles[?RoleName==`VPCLatticeControllerIAMRole`].Arn' --output text)

aws eks create-pod-identity-association --cluster-name $EKS_CLUSTER_NAME --role-arn $VPCLatticeControllerIAMRoleArn --namespace aws-application-networking-system --service-account gateway-api-controller
```

### Gateway API 컨트롤러 및 GatewayClass 배포

컨트롤러 매니페스트와 `gatewayclass`를 클러스터에 배포합니다.

```sh
kubectl apply -f https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/deploy-v1.0.5.yaml

kubectl get pods -n aws-application-networking-system 

kubectl apply -f https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/gatewayclass.yaml
```

### VPC Lattice 서비스 네트워크 생성 및 VPC 연결

`my-hotel` 서비스 네트워크를 만들고 클러스터 VPC를 연결합니다.

```sh
aws vpc-lattice create-service-network --name my-hotel

aws vpc-lattice list-service-networks | jq -r '.items[]| select(.name=="my-hotel") | .id'

export my_hotel_sn_id=$(aws vpc-lattice list-service-networks | jq -r '.items[]| select(.name=="my-hotel") | .id')
export CLUSTER_VPC_ID=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# VPC는 1개의 Service Network에만 Associaation 이 가능합니다. 앞서 LAB에서 Superapp에 Client VPC를 Assocation 시켰다면, 삭제 후 Association 해야 합니다.
aws vpc-lattice create-service-network-vpc-association --service-network-identifier ${my_hotel_sn_id} --vpc-identifier ${CLUSTER_VPC_ID}

aws vpc-lattice list-service-network-vpc-associations --vpc-id ${CLUSTER_VPC_ID} | jq -r '.items[].status'
```

### Gateway 및 HTTPRoute 리소스 배포

`my-hotel-gateway`와 `parking`, `review`, `rate-route-path`, `inventory-ver1`, `inventory-route` 매니페스트를 배포합니다.

```sh
kubectl apply -f my-hotel-gateway.yaml

kubectl get gateway

kubectl apply -f parking.yaml
kubectl apply -f review.yaml
kubectl apply -f rate-route-path.yaml

kubectl get svc,pod,httproute

kubectl apply -f inventory-ver1.yaml
kubectl apply -f inventory-route.yaml

kubectl get svc,pod,httproute
```

### 서비스 간 통신 테스트

각 HTTPRoute에 대해 Lattice가 할당한 도메인 이름을 조회하고, 파드에서 curl로 서비스 간 통신을 테스트합니다.

```sh
export k8s_rates_svc_dns=$(kubectl get httproute rates -o json | jq -r '.metadata.annotations."application-networking.k8s.aws/lattice-assigned-domain-name"')
export k8s_inventory_svc_dns=$(kubectl get httproute inventory -o json | jq -r '.metadata.annotations."application-networking.k8s.aws/lattice-assigned-domain-name"')

kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/parking
kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/review 
kubectl exec deploy/parking -- curl $k8s_inventory_svc_dns
```

### 추가 Lattice 테스트 라우트 배포 및 통신 테스트

`lattice-test-01` 라우트를 추가로 배포하고 동일한 방식으로 통신을 테스트합니다.

```sh
kubectl apply -f lattice-test-01.yaml

export k8s_lattice_test_01_svc_dns=$(kubectl get httproute lattice-test-01 -o json | jq -r '.metadata.annotations."application-networking.k8s.aws/lattice-assigned-domain-name"')

kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/parking
kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/review 
kubectl exec deploy/parking -- curl $k8s_inventory_svc_dns
```

## init.sh — CloudFormation 배포 및 서비스 확인

### CloudFormation 스택 배포

`cloudfromation/LatticeBaseInfraWithAPIServer.yaml` 템플릿으로 추가 인프라 스택을 배포합니다.

```sh
aws cloudformation deploy \
  --stack-name "latticebaseinfrawithapiserver" \
  --template-file "./LatticeBaseInfraWithAPIServer.yaml" \
  --capabilities CAPABILITY_NAMED_IAM
```

### 서비스 DNS 및 IAM Role 조회

배포된 VPC Lattice 서비스들의 DNS 이름과 클라이언트 인스턴스 IAM Role ARN, 서비스 ARN을 조회합니다.

```sh
export reservation_svc_dns=$(aws vpc-lattice list-services | jq -r '.items[].dnsEntry.domainName' | grep 'reservation')
export parking_svc_dns=$(aws vpc-lattice list-services | jq -r '.items[].dnsEntry.domainName' | grep 'parking')

InstanceClient1_IAM_ARN=$(aws iam get-role --role-name InstanceClient1_IAM --query Role.Arn --output text)
InstanceClient2_IAM_ARN=$(aws iam get-role --role-name InstanceClient2_IAM --query Role.Arn --output text)
parking_svc_arn=$(aws vpc-lattice list-services | jq -r '.items[] | select(.dnsEntry.domainName=="'$parking_svc_dns'") | .arn')
```
