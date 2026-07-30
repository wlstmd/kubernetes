# AWS Pod EIP Controller

- 참고
  https://github.com/aws-samples/aws-pod-eip-controller

### 기존 Pod가 외부 인터넷과 통신하는 방법

1. Worker Node가 Public Subnet에 위치 할 경우 Pod는 외부 인터넷 통신 시 Worker Node의 Public/EIP를 기반으로 외부 인터넷과 통신
2. Worker Node가 Private Subnet에 위치 할 경우 NAT G/W을 통해 NAT GW의 공인 IP로 NAT되어 통신

### **AWS Pod EIP Controller란?**

AWS Pod EIP Controller는 Annotation을 통해 Elastic IP를 자동으로 할당 및 해제하는 기능을 제공

### **Pod에 대한 인터넷 Outbound 액세스 이해**

- Pod의 통신 대상이 VPC에 연결된 CIDR 블록 내에 있지 않은 경우 기본적으로 Pod가 실행 중인 노드의 ENI의 IP 주소로 변환
- 즉 실행 중인 노드가 Public Subnet에 위치하여 있고, 해당 노드가 퍼블릭 또는 EIP 주소를 할당 받은 경우에 인터넷과 통신이 가능하지만, Pod는 노드의 Public IP로 SNAT 되어 통신
- 노드의 기본 ENI로의 SNAT을 해제하기 위해서는 아래 옵션으로 해제

```bash
kubectl set env daemonset -n kube-system aws-node AWS_VPC_K8S_CNI_EXTERNALSNAT=true
```

### Pod 기반 White-List 처리를 위한 방안

- AWS Pod EIP Controller를 통해 Pod의 Public EIP를 부여
- `AWS_VPC_K8S_CNI_EXTERNALSNAT=true`을 통해 Node 기반 SNAT을 해제
- 외부 파트너사 API가 "이 IP만 허용해줄게"라고 화이트리스트를 걸어주는 상황에서, **Pod마다 서로 다른 IP**로 식별되어야 하는 경우
- NAT GW를 쓰면 Pod A, B, C가 전부 같은 IP로 나가기 때문에 **애초에 "Pod별 화이트리스트"라는 요구사항 자체가 성립이 안 됨.** 이게 EIP Controller를 별도로 만든 이유

  ```markdown
  [Pod A: 10.0.1.10] ─┐
  [Pod B: 10.0.1.11] ─┼─→ NAT Gateway (공인 IP 1개) ─→ 인터넷
  [Pod C: 10.0.1.12] ─┘
  ```

- Cluster Manifest
  ```yaml
  apiVersion: eksctl.io/v1alpha5
  kind: ClusterConfig

  metadata:
    name: public-eks-cluster
    version: "1.35"
    region: ap-northeast-2

  iam:
    withOIDC: true

  vpc:
    subnets:
      public:
        ap-northeast-2a: { id: public_a }
        ap-northeast-2b: { id: public_b }

  managedNodeGroups:
    - name: public-nodegroup
      instanceName: public-node
      instanceType: t3.medium
      desiredCapacity: 2
      minSize: 2
      maxSize: 4
      privateNetworking: false
  ```

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=<AWS_REGION>
```

```bash
aws ecr create-repository --repository-name aws-pod-eip-controller
```

```bash
aws ecr get-login-password --region ${AWS_REGION} \
    | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

```bash
git clone https://github.com/aws-samples/aws-pod-eip-controller.git
cd aws-pod-eip-controller
```

```bash
docker buildx build \
    --tag ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aws-pod-eip-controller:latest \
    --platform linux/amd64,linux/arm64 \
    --push .
```

```bash
cat << EOF > iam-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "ec2:AllocateAddress",
                "ec2:AssociateAddress",
                "ec2:CreateTags",
                "ec2:ReleaseAddress",
                "ec2:DisassociateAddress",
                "ec2:DeleteTags",
                "ec2:DescribeAddresses",
                "ec2:DescribeNetworkInterfaces"
            ],
            "Resource": "*"
        }
    ]
}
EOF
```

```bash
aws iam create-policy \
    --policy-name AWSPodEIPControllerIAMPolicy \
    --policy-document file://iam-policy.json
```

```bash
eksctl create iamserviceaccount \
    --cluster=eip-controller-demo \
    --namespace=kube-system \
    --name=aws-pod-eip-controller \
    --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSPodEIPControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --region ${AWS_REGION} \
    --approve
```

```bash
helm install aws-pod-eip-controller ./charts/aws-pod-eip-controller \
  --namespace kube-system \
  --set image=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/aws-pod-eip-controller:latest \
  --set clusterName=eip-controller-demo \
  --set serviceAccountName=aws-pod-eip-controller \
  --wait
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: busybox-eip
  template:
    metadata:
      labels:
        app: busybox-eip
      annotations:
        aws-samples.github.com/aws-pod-eip-controller-type: auto
    spec:
      nodeSelector:
        alpha.eksctl.io/nodegroup-name: public-node-group
      containers:
        - name: busybox
          image: busybox
          command:
            - sleep
            - "3600"
          imagePullPolicy: IfNotPresent
```

```bash
kubectl get pod | grep busybox
```

```bash
kubectl get pods -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,PODIP:.status.podIP,EIP:.metadata.labels.aws-pod-eip-controller-public-ip -w
```

**테스트 1 - SNAT가 활성화 되어 있을 경우**

- busybox Pod에 접속하여 외부 API를 통해 Source IP를 조회하게 되면 결과적으로 Pod의 EIP가 아닌, Node의 Public IP가 반환 되는 것을 확인 할 수 있다.

```bash
kubectl exec -it <POD_NAME> -- /bin/sh
wget -qO- http://api.ipify.org
```

**테스트 2 - SNAT가 비활성화 되어 있을 경우**

- busybox Pod에 접속하여 외부 API를 통해 Source IP를 조회하게 되면 결과적으로 Pod에 부여된 EIP가 조회되는 사항을 확인 할 수 있다.

```bash
kubectl exec -it <POD_NAME> -- /bin/sh
wget -qO- http://api.ipify.org
```
</content>
