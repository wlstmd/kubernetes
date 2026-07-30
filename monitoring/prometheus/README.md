# Prometheus 설치 및 Ingress 구성

## ENV

```sh
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
CLUSTER_OIDC=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

## Prometheus

```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get deployment `metrics-server` -n kube-system

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm repo list

kubectl create ns prometheus

helm install prometheus prometheus-community/prometheus \
    --namespace prometheus \
    --set alertmanager.persistentVolume.storageClass="gp2" \
    --set server.persistentVolume.storageClass="gp2" \
    -f values.yaml

kubectl get all -n prometheus

# helm uninstall prometheus -n prometheus
```

## EBS CSI Driver

```sh
eksctl utils associate-iam-oidc-provider --region ap-northeast-2 --cluster $EKS_CLUSTER_NAME --approve

eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --region ap-northeast-2 \
    --namespace kube-system \
    --cluster $EKS_CLUSTER_NAME \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve

# aws iam delete-role --role-name AmazonEKS_EBS_CSI_DriverRole

# eksctl delete iamserviceaccount \
#     --name ebs-csi-controller-sa \
#     --region ap-northeast-2 \
#     --cluster $EKS_CLUSTER_NAME \
#     --namespace kube-system

eksctl create addon --name aws-ebs-csi-driver --cluster $EKS_CLUSTER_NAME --service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole
# eksctl delete addon --name aws-ebs-csi-driver --cluster $EKS_CLUSTER_NAME 

eksctl get addon --name aws-ebs-csi-driver --cluster $EKS_CLUSTER_NAME
```

## Ingress

```sh
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

eksctl create iamserviceaccount \
  --cluster=$EKS_CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# eksctl delete iamserviceaccount \
#   --cluster=$EKS_CLUSTER_NAME \
#   --namespace=kube-system \
#   --name=aws-load-balancer-controller

# aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl get deployment -n kube-system aws-load-balancer-controller
```

`ingress-prometheus.yaml`을 따로 적용하면 `/prometheus` 경로로 노출된다.
