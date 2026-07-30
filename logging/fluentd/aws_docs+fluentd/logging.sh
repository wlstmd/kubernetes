# ENV
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
REGION_CODE="<REGION>"

# CloudWatch의 네임스페이스 생성
kubectl apply -f cloudwatch-namespace.yaml

# Fluentd ConfigMap 생성
kubectl create configmap cluster-info \
--from-literal=cluster.name=$EKS_CLUSTER_NAME \
--from-literal=logs.region=$REGION_CODE -n amazon-cloudwatch

# Fluentd DaemonSet 배포
kubectl apply -f fluentd.yaml

# Fluentd DaemonSet Pod가 실행 중인지 확인
kubectl get pods -n amazon-cloudwatch

# Add Log
kubectl exec -it -n skills deployment.apps/skills-app-deployment -- curl localhost:8080/v1/dummy > /dev/null 2>&1

# Check Log
kubectl logs -n skills deployment.apps/skills-app-deployment