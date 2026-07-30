# MWAA(Managed Workflows for Apache Airflow) 연동 설정

## 환경 변수 및 실행 환경 구성

EKS 클러스터와 연동할 MWAA 환경을 위한 환경 변수 설정부터, S3 버킷 생성, OIDC 연동, `mwaa` 네임스페이스의 Role/RoleBinding, MWAA 실행 역할에 필요한 IAM 정책/역할 생성, EKS identity mapping, kubeconfig 발급까지 이어지는 구간이다.

```sh
export EKS_CLUSTER_NAME=skills-eks-cluster
export REGION_CODE=ap-northeast-2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export MWAA_ENV_NAME=skills-mwaa-env
export MWAA_S3_BUCKET=skills-mwaa-s3-bucket

aws s3 mb s3://$MWAA_S3_BUCKET --region $REGION_CODE

eksctl utils associate-iam-oidc-provider \
  --region $REGION_CODE \
  --cluster $EKS_CLUSTER_NAME \
  --approve

kubectl create namespace mwaa

cat << EOF | kubectl apply -f - -n mwaa
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: mwaa-role
rules:
  - apiGroups:
      - ""
      - "apps"
      - "batch"
      - "extensions"
    resources:      
      - "jobs"
      - "pods"
      - "pods/attach"
      - "pods/exec"
      - "pods/log"
      - "pods/portforward"
      - "secrets"
      - "services"
    verbs:
      - "create"
      - "delete"
      - "describe"
      - "get"
      - "list"
      - "patch"
      - "update"
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: mwaa-role-binding
subjects:
- kind: User
  name: mwaa-service
roleRef:
  kind: Role
  name: mwaa-role
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl get pods -n mwaa --as mwaa-service

cat << EOF > mwaa-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "airflow:PublishMetrics",
      "Resource": "arn:aws:airflow:${REGION_CODE}:${AWS_ACCOUNT_ID}:environment/${MWAA_ENV_NAME}"
    },
    {
      "Effect": "Deny",
      "Action": "s3:ListAllMyBuckets",
      "Resource": [
        "arn:aws:s3:::$MWAA_S3_BUCKET",
        "arn:aws:s3:::$MWAA_S3_BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject*", "s3:GetBucket*", "s3:List*"],
      "Resource": [
        "arn:aws:s3:::$MWAA_S3_BUCKET",
        "arn:aws:s3:::$MWAA_S3_BUCKET/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:CreateLogGroup",
        "logs:PutLogEvents",
        "logs:GetLogEvents",
        "logs:GetLogRecord",
        "logs:GetLogGroupFields",
        "logs:GetQueryResults"
      ],
      "Resource": [
        "arn:aws:logs:${REGION_CODE}:${AWS_ACCOUNT_ID}:log-group:airflow-${MWAA_ENV_NAME}-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["logs:DescribeLogGroups"],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": "cloudwatch:PutMetricData",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage",
        "sqs:SendMessage"
      ],
      "Resource": "arn:aws:sqs:${REGION_CODE}:*:airflow-celery-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey*",
        "kms:Encrypt"
      ],
      "NotResource": "arn:aws:kms:*:${AWS_ACCOUNT_ID}:key/*",
      "Condition": {
        "StringLike": {
          "kms:ViaService": ["sqs.${REGION_CODE}.amazonaws.com"]
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": ["eks:DescribeCluster"],
      "Resource": "arn:aws:eks:${REGION_CODE}:${AWS_ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
    }
  ]
}
EOF

cat << EOF > mwaa-role-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "airflow.amazonaws.com",
                    "airflow-env.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

aws iam create-policy \
  --policy-name mwaa-policy \
  --policy-document file://mwaa-policy.json

aws iam create-role \
  --role-name mwaa-execution-role \
  --assume-role-policy-document file://mwaa-role-trust-policy.json

aws iam attach-role-policy \
  --role-name mwaa-execution-role \
  --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/mwaa-policy

eksctl create iamidentitymapping \
  --region $REGION_CODE \
  --cluster $EKS_CLUSTER_NAME \
  --arn arn:aws:iam::$AWS_ACCOUNT_ID:role/mwaa-execution-role \
  --username mwaa-service

aws eks update-kubeconfig \
  --region $REGION_CODE \
  --kubeconfig ./kube_config.yaml \
  --name $EKS_CLUSTER_NAME \
  --alias aws
```

## 버킷에 파일 업로드

MWAA S3 버킷에 올릴 dags/requirements 디렉터리 구조.

```sh
.
├─dags
│  ├─mwaa_pod.py
│  └─kube_config.yaml
└─requirements
    └─requirements.txt
```

## Check

```sh
kubectl get pods -n mwaa

kubectl logs -n mwaa <pod-name>
```
