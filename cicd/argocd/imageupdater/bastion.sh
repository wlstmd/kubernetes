# ENV
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export EKS_CLUSTER_NAME="skills-eks-cluster"
export AWS_REGION="ap-northeast-2"

cat << EOF > values.yaml
configs:
  params:
    server.insecure: true
EOF

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm install argocd argo/argo-cd \
    --create-namespace \
    --namespace argocd \
    --values values.yaml

# ArgoCD CLI Install
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# ArgoCD Login
export ARGOCD_SERVER=`kubectl get svc argocd-server -n argocd -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname'`
echo $ARGOCD_SERVER

export ARGO_PWD=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
echo $ARGO_PWD

argocd login $ARGOCD_SERVER --username admin --password $ARGO_PWD --insecure

# argocd account update-password - # 비밀번호 변경

# ArgoCD Image Updater Install
cat << EOF > values.yaml
config:
  argocd:
    grpcWeb: true
    serverAddress: "http://argocd-server.argocd"	# ArgoCD API Server 연결
    insecure: true
    plaintext: true
  logLevel: debug
  registries:	# ECR Registry 등록 (Docker hub 등 Public Registry는 불필요)
    - name: ECR
      api_url: "https://$AWS_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com"
      prefix: "$AWS_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com"
      ping: true
      insecure: false
      credentials: "ext:/scripts/auth1.sh"
      credsexpire: 10h
authScripts:
  enabled: true
  scripts:	# ECR 인증 Token을 얻는 스크립트
    auth1.sh: |
      #!/bin/sh
      aws ecr --region ap-northeast-2 get-authorization-token --output text --query 'authorizationData[].authorizationToken' | base64 -d
EOF

helm install argocd-image-updater argo/argocd-image-updater \
    --namespace argocd \
    --values values.yaml

# HPA Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# AWS LoadBalancerController
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

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl get deployment -n kube-system aws-load-balancer-controller