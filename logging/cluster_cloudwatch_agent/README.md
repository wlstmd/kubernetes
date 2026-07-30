# Cluster-level CloudWatch Agent 설치 (DaemonSet)

## 환경 변수 설정

```sh
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
EKS_NODE_GROUP_NAME="<NODE_GROUP_NAME>"
```

## Attach IAM Role for EKS NodeGroup

```sh
NODEGROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query "nodegroup.nodeRole" --output text | cut -d'/' -f2-)

aws iam attach-role-policy \
--role-name $NODEGROUP_ROLE_NAME \
--policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

## Namespace

```sh
kubectl apply -f cloudwatch-namespace.yaml
```

## SA

```sh
kubectl apply -f serviceaccount.yaml
```

## ConfigMap

```sh
sed -i 's/{{cluster_name}}/'${EKS_CLUSTER_NAME}'/' configmap.yaml
kubectl apply -f configmap.yaml
```

## DaemonSet

```sh
kubectl apply -f daemonset.yaml
```

## Check

```sh
kubectl get pods -n amazon-cloudwatch
```
