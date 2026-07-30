# EMR on EKS 구성 및 Spark Job 실행

EKS 클러스터를 EMR 가상 클러스터로 등록하고, Job Execution Role/IRSA 신뢰 정책을 구성한 뒤 PySpark 잡을 EMR on EKS로 실행한다.

## 환경 변수 설정

클러스터 이름, S3 버킷 이름, 리전, 계정 ID, 클러스터 OIDC 발급자를 환경 변수로 지정합니다.

```sh
export CLUSTER_NAME="skills-eks-cluster"
export S3_BUCKET_NAME="skills-emr-on-eks"
export REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export CLUSTER_OIDC=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
```

## EMR 네임스페이스 및 IAM Identity Mapping 설정

`emr` 네임스페이스를 만들고, EMR 컨테이너 서비스가 클러스터를 사용할 수 있도록 IAM identity mapping과 OIDC 프로바이더를 구성합니다.

```sh
kubectl create ns emr

eksctl create iamidentitymapping --cluster $CLUSTER_NAME \
    --namespace emr \
    --service-name "emr-containers" \
    --region $REGION

eksctl utils associate-iam-oidc-provider \
   --cluster $CLUSTER_NAME \
   --region $REGION \
   --approve
```

## Job Execution Role 생성

EMR 컨테이너가 assume할 수 있는 신뢰 정책으로 `EMRContainers-JobExecutionRole`을 생성하고, S3/CloudWatch Logs 접근 권한을 인라인 정책으로 부여합니다.

```sh
cat << EOF > emr-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$CLUSTER_OIDC"
            },
            "Action": "sts:AssumeRoleWithWebIdentity"
        }
    ]
}
EOF

aws iam create-role \
  --role-name EMRContainers-JobExecutionRole \
  --assume-role-policy-document file://emr-trust-policy.json

cat << EOF > emr-container-jobexecutionrole.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:*:*:*"
      ]
    }
  ]
} 
EOF

aws iam put-role-policy \
  --role-name EMRContainers-JobExecutionRole \
  --policy-name EMR-Containers-Job-Execution \
  --policy-document file://emr-container-jobexecutionrole.json
```

## EMR 가상 클러스터 및 S3 버킷 생성

`emr` 네임스페이스를 컨테이너 프로바이더로 하는 EMR 가상 클러스터를 생성하고, 잡 산출물을 저장할 S3 버킷을 만듭니다.

```sh
aws emr-containers create-virtual-cluster --name skills-emr-cluster --container-provider '{
   "id": "'"$CLUSTER_NAME"'",
   "type": "EKS",
   "info": {
      "eksInfo": {
         "namespace": "emr"
      }
   }
}'

aws s3 mb s3://$S3_BUCKET_NAME

S3_PREFIX="s3://$S3_BUCKET_NAME"
V_C_ID=$(aws emr-containers list-virtual-clusters --query "virtualClusters[?name=='skills-emr-cluster'].id" --output text)
EMR_ROLE_ARN=$(aws iam get-role --role-name EMRContainers-JobExecutionRole --query Role.Arn --output text)
```

## Spark 잡 스크립트 작성 및 업로드

간단한 PySpark 스크립트(`job-app.py`)를 작성해서 S3에 업로드합니다.

```sh
cat << EOF > job-app.py
from pyspark.sql import SparkSession
from pyspark import SparkContext
from pyspark.sql import functions as F
from pyspark.sql import types as T
from pyspark.sql import Row
import argparse

spark = SparkSession.builder.appName("sample_script").getOrCreate()

def main():
    df_spark = spark.createDataFrame([
        Row(a=1, b=11.2, c='apple'),
        Row(a=2, b=3.5, c='banana'),
        Row(a=3, b=7.3, c='tomato'),
    ])

    df_spark.write.mode('overwrite').parquet('s3://$S3_BUCKET_NAME/result/job-without-app/')

if __name__ == "__main__":
    main()
EOF

aws s3 cp job-app.py s3://$S3_BUCKET_NAME/spark-src/job-app.py
```

## Spark 잡 실행 요청 및 첫 실행

잡 실행 요청(`request.json`)을 작성하고, 로그 그룹을 만든 뒤 첫 번째 Spark 잡을 실행합니다.

```sh
cat << EOF > request.json
{
    "name": "wsi-emr-stark-job",
    "virtualClusterId": "${V_C_ID}",
    "executionRoleArn": "${EMR_ROLE_ARN}",
    "releaseLabel": "emr-6.4.0-latest",
    "jobDriver": {
        "sparkSubmitJobDriver": {
            "entryPoint": "s3://$S3_BUCKET_NAME/spark-src/job-app.py",
            "sparkSubmitParameters": "--conf spark.executor.instances=1 --conf spark.executor.memory=1G --conf spark.executor.cores=1 --conf spark.driver.cores=1"
        }
    },
    "configurationOverrides": {
        "applicationConfiguration": [
            {
                "classification": "spark-defaults",
                "properties": {
                  "spark.dynamicAllocation.enabled": "false",
                  "spark.kubernetes.executor.deleteOnTermination": "true"
                }
            }
        ],
        "monitoringConfiguration": {
            "cloudWatchMonitoringConfiguration": {
                "logGroupName": "/emr-on-eks/${CLUSTER_NAME}",
                "logStreamNamePrefix": "emr"
            },
            "s3MonitoringConfiguration": {
                "logUri": "${S3_PREFIX}/"
            }
        }
    }
}
EOF

aws logs create-log-group --log-group-name=/emr-on-eks/$CLUSTER_NAME

aws emr-containers start-job-run --cli-input-json file://request.json
```

## Job Execution Role 신뢰 정책 범위 축소 및 재실행

실제 생성된 Spark client/driver/executor 서비스 어카운트만 assume 가능하도록 신뢰 정책을 좁혀서 갱신하고, 같은 요청으로 잡을 다시 실행합니다.

```sh
export EMR_CONATINER_CLIENT_SA=$(kubectl get sa -n emr -o json | jq -r '.items[].metadata.name | select(startswith("emr-containers-sa-spark-client"))')
export EMR_CONATINER_DRIVER_SA=$(kubectl get sa -n emr -o json | jq -r '.items[].metadata.name | select(startswith("emr-containers-sa-spark-driver"))')
export EMR_CONATINER_EXECUTOR_SA=$(kubectl get sa -n emr -o json | jq -r '.items[].metadata.name | select(startswith("emr-containers-sa-spark-executor"))')
export NAMESPACE=emr

cat << EOF > emr-trust-policy-release.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/$CLUSTER_OIDC"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "$CLUSTER_OIDC:aud": "sts.amazonaws.com",
                    "$CLUSTER_OIDC:sub": [
                        "system:serviceaccount:$NAMESPACE:$EMR_CONATINER_CLIENT_SA",
                        "system:serviceaccount:$NAMESPACE:$EMR_CONATINER_DRIVER_SA",
                        "system:serviceaccount:$NAMESPACE:$EMR_CONATINER_EXECUTOR_SA"
                    ]
                }
            }
        }
    ]
}
EOF

aws iam update-assume-role-policy \
  --role-name EMRContainers-JobExecutionRole \
  --policy-document file://emr-trust-policy-release.json

aws emr-containers start-job-run --cli-input-json file://request.json
```
