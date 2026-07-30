# Velero 설치 및 S3 기반 백업/복원

Velero를 이용해 EKS 클러스터의 네임스페이스를 S3 버킷에 백업하고 복원하는 실습. 스크립트 자체에는 별도의 `#` 주석이 없어, 아래 섹션 구분은 명령 내용을 기준으로 나눈 것이다.

## 환경 변수 설정

```sh
export BUCKET_NAME="skills-velero"
export REGION_CODE=ap-northeast-2
export BACKUP_NAME="skills-backup"
```

## S3 버킷 및 IAM 사용자 생성

```sh
aws s3 mb s3://$BUCKET_NAME --region $REGION_CODE

aws iam create-user --user-name velero
```

## Velero IAM 정책 생성 및 연결

```sh
cat << EOF > velero-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}"
            ]
        }
    ]
}
EOF

aws iam put-user-policy \
  --user-name velero \
  --policy-name velero \
  --policy-document file://velero-policy.json
```

## Velero용 Access Key 생성

```sh
aws iam create-access-key --user-name velero
```

## Velero CLI 설치

```sh
wget https://github.com/vmware-tanzu/velero/releases/download/v1.15.2/velero-v1.15.2-linux-amd64.tar.gz
tar zxvf velero-v1.15.2-linux-amd64.tar.gz
sudo cp velero-v1.15.2-linux-amd64/velero /usr/local/bin/
```

## AWS 자격 증명 파일 생성

```sh
cat << EOF > credentials-velero
[default]
aws_access_key_id=<AWS_ACCESS_KEY_ID>
aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>
EOF
```

## Velero 설치

```sh
velero install \
    --provider aws \
    --bucket $BUCKET_NAME \
    --secret-file ./credentials-velero \
    --backup-location-config region=$REGION_CODE \
    --use-volume-snapshots=false \
    --plugins velero/velero-plugin-for-aws:v1.10.0
```

## 백업 생성 및 확인

```sh
velero backup create $BACKUP_NAME --include-namespaces skills --wait

velero get backup
```

## 복원

```sh
velero restore create --from-backup $BACKUP_NAME --wait
```
