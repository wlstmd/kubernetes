# CloudWatch Observability 설치

## ENV

```sh
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
EKS_NODE_GROUP_NAME="<NODE_GROUP_NAME>"
NODE_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query 'nodegroup.nodeRole' --output text | awk -F/ '{print $NF}')
```

## Attach IAM Role for EKS NodeGroup

```sh
aws iam attach-role-policy \
--role-name $NODE_ROLE_NAME \
--policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

## Create a namespace for the CloudWatch agent

```sh
wget https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml
kubectl apply -f cloudwatch-namespace.yaml
```

## Create CloudWatch Observability

```sh
aws eks create-addon --cluster-name $EKS_CLUSTER_NAME --addon-name amazon-cloudwatch-observability > /dev/null
```

## Check Addon

```sh
aws eks describe-addon --cluster-name $EKS_CLUSTER_NAME --addon-name amazon-cloudwatch-observability
```
