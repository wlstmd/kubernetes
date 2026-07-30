# Loki 스택 설치 (Prometheus + Grafana + Loki)

## ENV

```sh
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
CLUSTER_OIDC=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

## Prometheus

```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get deployment metrics-server -n kube-system

kubectl create ns monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm repo list

helm install prometheus prometheus-community/prometheus \
    --namespace monitoring \
    --set alertmanager.persistentVolume.storageClass="gp2" \
    --set server.persistentVolume.storageClass="gp2" \
    -f values.yaml

kubectl get all -n monitoring
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

## Grafana

```sh
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana \
    --namespace monitoring \
    --set persistence.storageClassName="gp2" \
    --set persistence.enabled=true \
    --set adminPassword='admin1234' \
    --values prometheus-source.yaml \
    --set service.type=ClusterIP
```

## Loki

```sh
helm show values grafana/loki-stack > loki-stack-values.yaml

kubectl create ns loki
helm install loki-stack grafana/loki-stack --values loki-stack-values.yaml -n loki
kubectl -n loki get pods

http://loki-stack.loki.svc.cluster.local:3100
```
