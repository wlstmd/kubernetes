# Fluent Bit 로그 수집 설치

## ENV

```sh
EKS_CLUSTER_NAME="skills-eks-cluster"
```

## Attach IAM Role for EKS NodeGroup

```sh
aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=skills-app-nodegroup" --query "Reservations[*].Instances[*].IamInstanceProfile.Arn" --output text

aws iam get-instance-profile --instance-profile-name <InstanceProfileName> --query "InstanceProfile.Roles[*].RoleName" --output text
# aws iam get-instance-profile --instance-profile-name arn:aws:iam::362708816803:instance-profile/eks-30c90cd7-90ab-1e78-b0ad-db08135cb66c --query "InstanceProfile.Roles[*].RoleName" --output text

aws iam attach-role-policy --role-name eksctl-skills-eks-cluster-nodegrou-NodeInstanceRole-tHGWlrkWUHFl --policy-arn arn:aws:iam::362708816803:policy/FluentBitCloudWatchLogsPolicy
```

## OIDC

```sh
eksctl utils associate-iam-oidc-provider --region=ap-northeast-2 --cluster=skills-eks-cluster --approve
```

## Create Role

```sh
cat << EOF > fluent-bit-cloudwatch-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams",
                "logs:DescribeLogGroups"
            ],
            "Resource": [
                "arn:aws:logs:*:*:log-group:skills/app:*",
                "arn:aws:logs:*:*:log-group:skills/app"
            ]
        }
    ]
}
EOF

aws iam create-policy --policy-name FluentBitCloudWatchLogsPolicy --policy-document file://fluent-bit-cloudwatch-policy.json
```

## IRSA

```sh
POLICY_ARN=$(aws iam list-policies --query 'Policies[?PolicyName==`FluentBitCloudWatchLogsPolicy`].Arn' --output text)

eksctl create iamserviceaccount \
    --name fluent-bit \
    --region="ap-northeast-2" \
    --cluster "$EKS_CLUSTER_NAME" \
    --namespace=skills \
    --attach-policy-arn "$POLICY_ARN" \
    --override-existing-serviceaccounts \
    --approve
```

## IAM ServiceAccount 삭제 (cleanup)

```sh
eksctl delete iamserviceaccount --region ap-northeast-2 \
    --name fluent-bit \
    --namespace skills \
    --cluster skills-eks-cluster
```
