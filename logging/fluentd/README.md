# Fluentd 로그 수집 설치

## 환경 변수 설정

```sh
EKS_CLUSTER_NAME="skills-eks-cluster"
REGION_CODE="ap-northeast-2"
```

## Create a namespace for the CloudWatch agent

```sh
cat << EOF > ns.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: fluentd
  labels:
    name: amazon-cloudwatch
EOF
kubectl apply -f ns.yaml
kubectl create ns skills
```

## IRSA

```sh
eksctl create iamserviceaccount \
	--name fluentd \
	--region=$REGION_CODE \
	--cluster $EKS_CLUSTER_NAME \
	--namespace=fluentd \
	--attach-policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess \
	--override-existing-serviceaccounts \
	--approve 
```

## CM

```sh
kubectl create configmap cluster-info --from-literal=cluster.name=$EKS_CLUSTER_NAME --from-literal=logs.region=$REGION_CODE -n fluentd
```

## FLUENTD

```sh
kubectl apply -f fluentd.yaml
```

## Deployment

```sh
kubectl apply -f deployment.yaml
```

## Add Log

```sh
kubectl exec -it -n skills deployment.apps/skills-app-deployment -- curl localhost:8080/v1/dummy > /dev/null 2>&1
```

## Check Log

```sh
kubectl logs -n skills deployment.apps/skills-app-deployment
```
