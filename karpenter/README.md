# Karpenter 설치 및 구성

## KarpenterNodeRole이라는 IAM Role을 생성 (해당 Role은 Scale-out 된 노드가 사용할 IAM Role)

```sh
cat << EOF > node-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

aws iam create-role --role-name "KarpenterNodeRole-skills-eks" \
    --assume-role-policy-document file://node-trust-policy.json
    
aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile \
    --instance-profile-name "KarpenterNodeInstanceProfile-skills-eks"

aws iam add-role-to-instance-profile \
    --instance-profile-name "KarpenterNodeInstanceProfile-skills-eks" \
    --role-name "KarpenterNodeRole-skills-eks"
```

## KarpenterControllerRole이라는 IAM Role을 생성 (해당 Role은 Karpenter Pod가 사용할 IAM Role)

```sh
aws eks describe-cluster --name skills-eks-cluster --query "cluster.identity.oidc.issuer" --output text

cat << EOF > controller-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::362708816803:oidc-provider/OIDC_ENDPOINT#*//}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "OIDC_ENDPOINT#*//}:aud": "sts.amazonaws.com",
                    "OIDC_ENDPOINT#*//}:sub": "system:serviceaccount:karpenter:karpenter"
                }
            }
        }
    ]
}
EOF

aws iam create-role --role-name KarpenterControllerRole-skills-eks \
    --assume-role-policy-document file://controller-trust-policy.json
    
cat << EOF > controller-policy.json
{
    "Statement": [
        {
            "Action": [
                "ssm:GetParameter",
                "ec2:DescribeImages",
                "ec2:RunInstances",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeAvailabilityZones",
                "ec2:DeleteLaunchTemplate",
                "ec2:CreateTags",
                "ec2:CreateLaunchTemplate",
                "ec2:CreateFleet",
                "ec2:DescribeSpotPriceHistory",
                "pricing:GetProducts"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "Karpenter"
        },
        {
            "Action": "ec2:TerminateInstances",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/karpenter.sh/provisioner-name": "*"
                }
            },
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "ConditionalEC2Termination"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::362708816803:role/KarpenterNodeRole-skills-eks",
            "Sid": "PassNodeIAMRole"
        },
        {
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:aws:eks:ap-northeast-2:362708816803:cluster/skills-eks-cluster",
            "Sid": "EKSClusterEndpointLookup"
        }
    ],
    "Version": "2012-10-17"
}
EOF

aws iam put-role-policy --role-name KarpenterControllerRole-skills-eks \
    --policy-name KarpenterControllerPolicy-skills-eks \
    --policy-document file://controller-policy.json
```

## aws-auth ConfigMap 수정

```sh
kubectl edit configmap aws-auth -n kube-system
```

## Karpenter Helm 차트 템플릿 렌더링

```sh
helm template karpenter oci://public.ecr.aws/karpenter/karpenter --version v0.31.0 --namespace karpenter \
    --set settings.aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-skills-eks \
    --set settings.aws.clusterName=skills-eks-cluster \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::362708816803:role/KarpenterControllerRole-skills-eks" \
    --set controller.resources.requests.cpu=1 \
    --set controller.resources.requests.memory=1Gi \
    --set controller.resources.limits.cpu=1 \
    --set controller.resources.limits.memory=1Gi > karpenter.yaml
```

## Karpenter 네임스페이스 및 CRD 생성, 컨트롤러 배포

```sh
kubectl create ns karpenter

kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter/v0.31.0/pkg/apis/crds/karpenter.sh_provisioners.yaml
kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter/v0.31.0/pkg/apis/crds/karpenter.k8s.aws_awsnodetemplates.yaml
kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter/v0.31.0/pkg/apis/crds/karpenter.sh_machines.yaml
kubectl apply -f karpenter.yaml
```

## Karpenter Pod 확인

```sh
kubectl get po -n karpenter
```

## Provisioner 및 테스트 Deployment 배포

`provisioner.yaml`(Provisioner + AWSNodeTemplate)과 `deployment.yaml`(nginx 스케일 테스트용)을 적용한다.

```sh
kubectl apply -f provisioner.yaml

kubectl apply -f deployment.yaml
```

## 동작 확인

```sh
kubectl describe pod nginx-xxxx

kubectl logs -n karpenter  deploy/karpenter -f
```
