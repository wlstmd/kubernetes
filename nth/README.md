# AWS Node Termination Handler(NTH) 설치

## 환경 변수 설정

```sh
EKS_CLUSTER_NAME="skills-eks-cluster"
STACK_NAME="skills-eks-cluster-nth-stack"
AUTO_SCALING_GROUP_NAME=$(aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[*].AutoScalingGroupName' --output text)
```

## CloudFormation 템플릿 다운로드

```sh
curl -LO https://raw.githubusercontent.com/aws/aws-node-termination-handler/main/docs/cfn-template.yaml
```

## CloudFormation 스택 배포

```sh
aws cloudformation deploy \
    --template-file ./cfn-template.yaml \
    --stack-name $STACK_NAME
```

## Auto Scaling 그룹에 라이프사이클 훅 추가

```sh
aws autoscaling put-lifecycle-hook \
  --lifecycle-hook-name=k8s-hook \
  --auto-scaling-group-name=$AUTO_SCALING_GROUP_NAME \
  --lifecycle-transition=autoscaling:EC2_INSTANCE_TERMINATING \
  --default-result=CONTINUE \
  --heartbeat-timeout=300
```

## Auto Scaling 그룹에 태그 추가

```sh
aws autoscaling create-or-update-tags \
  --tags ResourceId=$AUTO_SCALING_GROUP_NAME,ResourceType=auto-scaling-group,Key=aws-node-termination-handler/managed,Value=,PropagateAtLaunch=true
```

## IAM 정책 생성

```sh
cat <<\EOF> nth-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:CompleteLifecycleAction",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeTags",
                "ec2:DescribeInstances",
                "sqs:DeleteMessage",
                "sqs:ReceiveMessage"
            ],
            "Resource": "*"
        }
    ]
}
EOF

POLICY_ARN=$(aws iam create-policy --policy-name nth-policy --policy-document file://nth-policy.json --query 'Policy.Arn' --output text)
```

## IAM OIDC 제공자 연결

```sh
eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve
```

## IAM 서비스 계정 생성

```sh
eksctl create iamserviceaccount \
    --cluster $EKS_CLUSTER_NAME \
    --name aws-node-termination-handler \
    --namespace kube-system \
    --attach-policy-arn $POLICY_ARN \
    --role-name AWS_NTH_Role \
    --approve
```

## SQS 큐 URL 가져오기

```sh
QUEUE_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='QueueURL'].OutputValue" --output text)
```

## Helm 차트 저장소 추가 및 NTH 설치

```sh
helm repo add eks https://aws.github.io/eks-charts
helm install aws-node-termination-handler eks/aws-node-termination-handler \
    --namespace kube-system \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-node-termination-handler \
    --set enableSqsTerminationDraining=true \
    --set queueURL=$QUEUE_URL
```

## Termination Handler 로그 확인

```sh
kubectl logs -l app.kubernetes.io/name=aws-node-termination-handler -n kube-system -f
```
