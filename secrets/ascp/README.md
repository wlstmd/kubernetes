# AWS Secrets Manager + Secrets Store CSI Driver (ASCP) 연동

Secrets Store CSI Driver와 AWS Secrets Manager Provider(ASCP)를 설치하고, Secrets Manager의 시크릿을 IRSA를 통해 Pod에 볼륨으로 마운트하는 실습 정리.

## 환경 변수 설정
```sh
export EKS_CLUSTER_NAME=skills-eks-cluster
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Secrets Store CSI Driver 설치
```sh
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install -n kube-system csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver
```

## AWS Secrets Manager Provider 설치
```sh
helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm install -n kube-system secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws
```

## Secrets Manager에 테스트 시크릿 생성
```sh
aws --region ap-northeast-2 secretsmanager \
  create-secret --name secret_test \
  --secret-string '{"username":"foo", "password":"super-secret"}'

SECRET_ARN=$(aws --region ap-northeast-2 secretsmanager \
    describe-secret --secret-id  secret_test \
    --query 'ARN' | sed -e 's/"//g' )

echo $SECRET_ARN
```

## IAM 정책 생성 (시크릿 접근 권한)
```sh
aws --region ap-northeast-2 iam \
	create-policy --query Policy.Arn \
    --output text --policy-name secret_policy \
    --policy-document '{
    "Version": "2012-10-17",
    "Statement": [ {
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": ["'"$SECRET_ARN"'" ]
    } ]
}'
```

## OIDC Provider 연결 및 IRSA 서비스 어카운트 생성
```sh
eksctl utils associate-iam-oidc-provider \
    --region=ap-northeast-2 \
    --cluster=$EKS_CLUSTER_NAME \
    --approve

eksctl create iamserviceaccount \
    --region=ap-northeast-2 \
    --name "secret-deployment-sa"  \
    --cluster $EKS_CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/secret_policy  \
    --override-existing-serviceaccounts \
    --approve
```

## SecretProviderClass 및 Deployment 배포
```sh
kubectl apply -f SecretProviderClass.yaml
kubectl apply -f deployment.yaml
```

## Pod에서 마운트된 시크릿 확인
```sh
export POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[].metadata.name}')
kubectl exec -it ${POD_NAME} -- cat /mnt/secrets/${SECRET_ARN}; echo
```
