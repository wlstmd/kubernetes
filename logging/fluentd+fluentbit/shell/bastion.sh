# ENV
EKS_CLUSTER_NAME="skills-eks-cluster"

# EKS
eksctl create cluster -f cluster.yaml
aws eks --region ap-northeast-2 update-kubeconfig --name $EKS_CLUSTER_NAME
echo 'alias k=kubectl' >> ~/.bash_profile && source ~/.bash_profile

# NS
kubectl apply -f ns.yaml
kubectl create ns app

# OIDC
eksctl utils associate-iam-oidc-provider --region=ap-northeast-2 --cluster=$EKS_CLUSTER_NAME --approve

# IRSA
eksctl create iamserviceaccount \
	--name fluentd \
	--region=ap-northeast-2 \
	--cluster $EKS_CLUSTER_NAME \
	--namespace=fluentd \
	--attach-policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess \
	--override-existing-serviceaccounts \
	--approve 

# CM
kubectl create configmap cluster-info \
  --from-literal=cluster.name=$EKS_CLUSTER_NAME \
  --from-literal=logs.region=ap-northeast-2 -n fluentd

# FLUENTD
kubectl apply -f fluentd.yaml

# FLUENTBIT
SVC_CLUSTER_IP=$(kubectl get svc -n fluentd -o json | jq -r '.items[].spec.clusterIP')

sed -i "s|SVC_IP|$SVC_CLUSTER_IP|g" fluentbit.yaml
kubectl apply -f fluentbit.yaml

# APP
kubectl apply -f deployment.yaml

# Add Log
kubectl exec -it -n app deployment.apps/service -- curl localhost:8080 > /dev/null 2>&1

# Check Log
kubectl logs -n app deployment.apps/service -c fluent-bit-cnt
kubectl logs -n app deployment.apps/service -c service-conatiner

