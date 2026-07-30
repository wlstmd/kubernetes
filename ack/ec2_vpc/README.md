# ACK EC2 컨트롤러 및 VPC/EC2 리소스 실습

ACK(AWS Controllers for Kubernetes) EC2 컨트롤러를 설치하고, 쿠버네티스 매니페스트로 VPC/서브넷/인스턴스 등 EC2 리소스를 직접 생성·관리하는 실습입니다. `bastion.sh`로 컨트롤러를 설치하고 간단한 VPC/서브넷 데모를 진행한 뒤, `etc.sh`에서 IGW/NAT/라우팅/보안그룹/인스턴스까지 포함한 완전한 VPC 워크플로우를 실습합니다.

## bastion.sh — ACK EC2 컨트롤러 설치 및 VPC/서브넷 데모

### 변수 지정

```sh
export SERVICE=ec2
export AWS_REGION=ap-northeast-2
export EKS_CLUSTER_NAME=skills-eks-cluster
```

### HELM 차트 Install

```sh
export RELEASE_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/$SERVICE-controller/releases/latest | grep '"tag_name":' | cut -d'"' -f4 | cut -c 2-)
helm pull oci://public.ecr.aws/aws-controllers-k8s/$SERVICE-chart --version=$RELEASE_VERSION
tar xzvf $SERVICE-chart-$RELEASE_VERSION.tgz
```

### ACK EC2-Controller 설치

```sh
helm install -n ack-system ack-$SERVICE-controller --set aws.region="$AWS_REGION" ~/$SERVICE-chart
```

### 설치 확인

```sh
helm list --namespace ack-system
kubectl -n ack-system get pods -l "app.kubernetes.io/instance=ack-$SERVICE-controller"
kubectl get crd | grep $SERVICE
```

### IAM 서비스 계정 생성 및 권한 부여

```sh
eksctl create iamserviceaccount \
  --name ack-$SERVICE-controller \
  --region=ap-northeast-2 \
  --namespace ack-system \
  --cluster $EKS_CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
  --override-existing-serviceaccounts \
  --approve

eksctl delete iamserviceaccount \
  --name ack-$SERVICE-controller \
  --region=ap-northeast-2 \
  --namespace ack-system \
  --cluster $EKS_CLUSTER_NAME
```

### IAM 서비스 계정 확인

```sh
eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME
```

### 서비스 계정 확인

```sh
kubectl get sa -n ack-system
kubectl describe sa ack-$SERVICE-controller -n ack-system
```

### ACK EC2 Controller 재시작

```sh
kubectl -n ack-system rollout restart deploy ack-$SERVICE-controller-$SERVICE-chart
```

### Pod 설명

```sh
kubectl describe pod -n ack-system -l k8s-app=$SERVICE-chart
```

### VPC 상태 확인

```sh
while true; do aws ec2 describe-vpcs --query 'Vpcs[*].{VPCId:VpcId, CidrBlock:CidrBlock}' --output text; echo "-----"; sleep 1; done
```

### VPC 생성

```sh
cat << EOF > vpc.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: VPC
metadata:
  name: vpc-tutorial-test
spec:
  cidrBlocks: 
  - 10.0.0.0/16
  enableDNSSupport: true
  enableDNSHostnames: true
EOF

kubectl apply -f vpc.yaml
```

### VPC 생성 확인

```sh
kubectl get vpcs
kubectl describe vpcs
aws ec2 describe-vpcs --query 'Vpcs[*].{VPCId:VpcId, CidrBlock:CidrBlock}' --output text
```

### VPC ID 변수 설정

```sh
VPCID=$(kubectl get vpcs vpc-tutorial-test -o jsonpath={.status.vpcID})
```

### 서브넷 상태 확인

```sh
while true; do aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query 'Subnets[*].{SubnetId:SubnetId, CidrBlock:CidrBlock}' --output text; echo "-----"; sleep 1 ; done
```

### 서브넷 매니페스트 생성

```sh
cat << EOF > subnet.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Subnet
metadata:
  name: subnet-tutorial-test
spec:
  cidrBlock: 10.0.0.0/20
  vpcID: $VPCID
EOF

kubectl apply -f subnet.yaml
```

### 서브넷 생성 확인

```sh
kubectl get subnets
kubectl describe subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query 'Subnets[*].{SubnetId:SubnetId, CidrBlock:CidrBlock}' --output text
```

### 리소스 삭제

```sh
kubectl delete -f subnet.yaml && kubectl delete -f vpc.yaml
```

## etc.sh — VPC/IGW/NAT/서브넷/인스턴스 전체 워크플로우

### VPC 및 관련 리소스 매니페스트 생성

VPC, 인터넷 게이트웨이, NAT 게이트웨이, EIP, 퍼블릭/프라이빗 라우트 테이블, 퍼블릭/프라이빗 서브넷, 보안 그룹을 하나의 매니페스트로 정의합니다.

```sh
cat << EOF > vpc-workflow.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: VPC
metadata:
  name: tutorial-vpc
spec:
  cidrBlocks: 
  - 10.0.0.0/16
  enableDNSSupport: true
  enableDNSHostnames: true
  tags:
    - key: name
      value: vpc-tutorial
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: InternetGateway
metadata:
  name: tutorial-igw
spec:
  vpcRef:
    from:
      name: tutorial-vpc
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: NATGateway
metadata:
  name: tutorial-natgateway1
spec:
  subnetRef:
    from:
      name: tutorial-public-subnet1
  allocationRef:
    from:
      name: tutorial-eip1
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: ElasticIPAddress
metadata:
  name: tutorial-eip1
spec:
  tags:
    - key: name
      value: eip-tutorial
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: RouteTable
metadata:
  name: tutorial-public-route-table
spec:
  vpcRef:
    from:
      name: tutorial-vpc
  routes:
  - destinationCIDRBlock: 0.0.0.0/0
    gatewayRef:
      from:
        name: tutorial-igw
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: RouteTable
metadata:
  name: tutorial-private-route-table-az1
spec:
  vpcRef:
    from:
      name: tutorial-vpc
  routes:
  - destinationCIDRBlock: 0.0.0.0/0
    natGatewayRef:
      from:
        name: tutorial-natgateway1
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Subnet
metadata:
  name: tutorial-public-subnet1
spec:
  availabilityZone: ap-northeast-2a
  cidrBlock: 10.0.0.0/20
  mapPublicIPOnLaunch: true
  vpcRef:
    from:
      name: tutorial-vpc
  routeTableRefs:
  - from:
      name: tutorial-public-route-table
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Subnet
metadata:
  name: tutorial-private-subnet1
spec:
  availabilityZone: ap-northeast-2a
  cidrBlock: 10.0.128.0/20
  vpcRef:
    from:
      name: tutorial-vpc
  routeTableRefs:
  - from:
      name: tutorial-private-route-table-az1
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: SecurityGroup
metadata:
  name: tutorial-security-group
spec:
  description: "ack security group"
  name: tutorial-sg
  vpcRef:
     from:
       name: tutorial-vpc
  ingressRules:
    - ipProtocol: tcp
      fromPort: 22
      toPort: 22
      ipRanges:
        - cidrIP: "0.0.0.0/0"
          description: "ingress"
EOF
```

### VPC 및 관련 리소스 생성

```sh
kubectl apply -f vpc-workflow.yaml
```

### 리소스 생성 상태 확인

```sh
kubectl get routetables,subnet
```

### VPC 환경 생성 확인

```sh
kubectl describe vpcs
kubectl describe internetgateways
kubectl describe routetables
kubectl describe natgateways
kubectl describe elasticipaddresses
kubectl describe securitygroups
```

### public 서브넷 ID 확인

```sh
PUBSUB1=$(kubectl get subnets tutorial-public-subnet1 -o jsonpath={.status.subnetID})
echo $PUBSUB1
```

### 보안 그룹 ID 확인

```sh
TSG=$(kubectl get securitygroups tutorial-security-group -o jsonpath={.status.id})
echo $TSG
```

### Amazon Linux 2023 AMI ID 확인

```sh
AL2023AMI=ami-049788618f07e189d
echo $AL2023AMI
```

### SSH 키페어 이름 설정

```sh
MYKEYPAIR=skills-practice

# echo $PUBSUB1 , $TSG , $AL2023AMI , $MYKEYPAIR
```

### 인스턴스 상태 확인

```sh
while true; do aws ec2 describe-instances --query "Reservations[*].Instances[*].{PublicIPAdd:PublicIpAddress,PrivateIPAdd:PrivateIpAddress,InstanceName:Tags[?Key=='Name']|[0].Value,Status:State.Name}" --filters Name=instance-state-name,Values=running --output table; date ; sleep 1 ; done
```

### public 서브넷에 인스턴스 생성

```sh
cat << EOF > tutorial-bastion-host.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Instance
metadata:
  name: tutorial-bastion-host
spec:
  imageID: $AL2023AMI # AL2023 AMI ID - ap-northeast-2
  instanceType: t3.medium
  subnetID: $PUBSUB1
  securityGroupIDs:
  - $TSG
  keyName: $MYKEYPAIR
  tags:
    - key: producer
      value: ack
EOF

kubectl apply -f tutorial-bastion-host.yaml
```

### 인스턴스 생성 확인

```sh
kubectl get instance
kubectl describe instance
aws ec2 describe-instances --query "Reservations[*].Instances[*].{PublicIPAdd:PublicIpAddress,PrivateIPAdd:PrivateIpAddress,InstanceName:Tags[?Key=='Name']|[0].Value,Status:State.Name}" --filters Name=instance-state-name,Values=running --output table
```

### 보안 그룹 수정 (아웃바운드 규칙 추가)

```sh
cat << EOF > modify-sg.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: SecurityGroup
metadata:
  name: tutorial-security-group
spec:
  description: "ack security group"
  name: tutorial-sg
  vpcRef:
     from:
       name: tutorial-vpc
  ingressRules:
    - ipProtocol: tcp
      fromPort: 22
      toPort: 22
      ipRanges:
        - cidrIP: "0.0.0.0/0"
          description: "ingress"
  egressRules:
    - ipProtocol: '-1'
      ipRanges:
        - cidrIP: "0.0.0.0/0"
          description: "egress"
EOF
```

### 보안 그룹 수정 적용

```sh
kubectl apply -f modify-sg.yaml
```

### 변경 확인 - 보안그룹에 아웃바운드 규칙 확인

```sh
kubectl logs -n $ACK_SYSTEM_NAMESPACE -l k8s-app=ec2-chart -f
```

### private 서브넷 ID 확인 - NATGW 생성 완료 후 RT/SubnetID가 확인되어 다소 시간 필요함

```sh
PRISUB1=$(kubectl get subnets tutorial-private-subnet1 -o jsonpath={.status.subnetID})
echo $PRISUB1

# echo $PRISUB1 , $TSG , $AL2023AMI , $MYKEYPAIR
```

### private 서브넷에 인스턴스 생성

```sh
cat << EOF > tutorial-instance-private.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Instance
metadata:
  name: tutorial-instance-private
spec:
  imageID: $AL2023AMI # AL2023 AMI ID - ap-northeast-2
  instanceType: t3.medium
  subnetID: $PRISUB1
  securityGroupIDs:
  - $TSG
  keyName: $MYKEYPAIR
  tags:
    - key: producer
      value: ack
EOF

# 인스턴스 생성
kubectl apply -f tutorial-instance-private.yaml
```

### 인스턴스 생성 확인

```sh
kubectl get instance
kubectl describe instance
aws ec2 describe-instances --query "Reservations[*].Instances[*].{PublicIPAdd:PublicIpAddress,PrivateIPAdd:PrivateIpAddress,InstanceName:Tags[?Key=='Name']|[0].Value,Status:State.Name}" --filters Name=instance-state-name,Values=running --output table
```

### SSH 접속

이 시점에서 생성된 (private) 인스턴스에 bastion을 통해 SSH로 접속합니다.

### 네트워크 상태 확인

```sh
ip -c addr
sudo ss -tnp
ping -c 2 8.8.8.8
curl ipinfo.io/ip ; echo # Public IP 확인 (EIP)
exit
```

### 리소스 삭제

```sh
kubectl delete -f tutorial-bastion-host.yaml && kubectl delete -f tutorial-instance-private.yaml
kubectl delete -f vpc-workflow.yaml
```
