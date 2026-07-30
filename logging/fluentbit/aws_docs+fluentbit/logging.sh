# ENV
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
DASHBOARD_NAME="<DASHBOARD_NAME>"
REGION_CODE="<REGION>"
EKS_NODE_GROUP_NAME="<NODE_GROUP_NAME>"

# Attach IAM Role for EKS NodeGroup
NODEGROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query "nodegroup.nodeRole" --output text | cut -d'/' -f2-)

aws iam attach-role-policy \
--role-name $NODEGROUP_ROLE_NAME \
--policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Create a namespace for the CloudWatch agent
wget https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml
kubectl apply -f cloudwatch-namespace.yaml

# Fluent Bit DaemonSet 배포를 위한 설정
ClusterName=$EKS_CLUSTER_NAME
RegionName=$REGION_CODE
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
[[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
[[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'
kubectl create configmap fluent-bit-cluster-info \
--from-literal=cluster.name=${ClusterName} \
--from-literal=http.server=${FluentBitHttpServer} \
--from-literal=http.port=${FluentBitHttpPort} \
--from-literal=read.head=${FluentBitReadFromHead} \
--from-literal=read.tail=${FluentBitReadFromTail} \
--from-literal=logs.region=${RegionName} -n amazon-cloudwatch

# Fluent Bit DaemonSet 배포
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml

# Fluent Bit daemonSet Pod가 실행 중인지 확인
kubectl get pods -n amazon-cloudwatch

# Fluent Bit Prometheus 지표에 대한 대시보드
curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/service/cwagent-prometheus/sample_cloudwatch_dashboards/fluent-bit/cw_dashboard_fluent_bit.json \
| sed "s/{{YOUR_AWS_REGION}}/${REGION_CODE}/g" \
| sed "s/{{YOUR_CLUSTER_NAME}}/${EKS_CLUSTER_NAME}/g" \
| xargs -0 aws cloudwatch put-dashboard --dashboard-name ${DASHBOARD_NAME} --dashboard-body