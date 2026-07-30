# EBS 볼륨 자동 스냅샷 백업 (CronJob)

EKS 노드 그룹에 EBS 스냅샷 권한을 부여하고, CronJob으로 특정 EBS 볼륨의 스냅샷을 주기적으로 생성하는 실습. 스크립트 자체에는 별도의 `#` 주석이 없어, 아래 섹션 구분은 명령 내용을 기준으로 나눈 것이다.

## 환경 변수 설정

```sh
export EKS_CLUSTER_NAME=skills-eks-cluster
export EKS_NODE_GROUP_NAME=skills-app-nodegroup
export AWS_REGION=ap-northeast-2
```

## EBS 볼륨 생성

```sh
aws ec2 create-volume --size 10 --volume-type gp3 --availability-zone ap-northeast-2a --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=wsi-ebs}]'
```

## 스냅샷 IAM 정책 생성

```sh
cat << EOF > ebs_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name EBSforEKSPolicy\
    --policy-document file://ebs_policy.json
```

## 노드 그룹 Role에 정책 연결

```sh
NODEGROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query "nodegroup.nodeRole" --output text | cut -d'/' -f2-)

aws iam attach-role-policy \
    --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query "Account" --output text):policy/EBSforEKSPolicy \
    --role-name $NODEGROUP_ROLE_NAME
```

## 네임스페이스 생성

```sh
kubectl create ns skills
```

## EBS 스냅샷 CronJob 배포

대상 EBS 볼륨 ID를 조회해 `backup.yaml`의 `EBS_ID` 자리를 치환한 뒤 배포한다.

```sh
EBS_ID=$(aws ec2 describe-volumes --filters Name=tag:Name,Values=wsi-ebs --query 'Volumes[*].VolumeId' --output text)

sed -i "s|EBS_ID|$EBS_ID|g" backup.yaml

kubectl apply -f backup.yaml
```

## 상태 확인

```sh
kubectl get cronjob ebs-snapshot-cronjob -n skills
kubectl get jobs --sort-by=.metadata.creationTimestamp -n skills
```

## 참고: backup.yaml

10분마다 지정한 EBS 볼륨의 스냅샷을 생성하는 CronJob 정의 (`EBS_ID`는 위 스크립트에서 `sed`로 실제 볼륨 ID로 치환됨).

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ebs-snapshot-cronjob
  namespace: skills
spec:
  schedule: "*/10 * * * *" # 10분마다 실행
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: ebs-snapshot
              image: amazon/aws-cli
              command:
                [
                  "sh",
                  "-c",
                  "aws ec2 create-snapshot --volume-id EBS_ID --description 'Automated backup'",
                ]
          restartPolicy: OnFailure
```
