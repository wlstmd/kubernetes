# ArgoCD 설치 및 애플리케이션 배포

ArgoCD를 EKS 클러스터에 설치하고, CLI로 로그인한 뒤 Git 저장소 기반 애플리케이션을 등록하고 동기화하는 실습입니다.

## ArgoCD Install

```sh
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## ArgoCD CLI Install

```sh
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

## LoadBalancer

```sh
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

## ArgoCD Login

```sh
export ARGOCD_SERVER=`kubectl get svc argocd-server -n argocd -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname'`
echo $ARGOCD_SERVER

export ARGO_PWD=`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
echo $ARGO_PWD

argocd login $ARGOCD_SERVER --username admin --password $ARGO_PWD --insecure
```

## ArgoCD App Create

```sh
CONTEXT_NAME=`kubectl config view -o jsonpath='{.current-context}'`
argocd cluster add $CONTEXT_NAME

# ECS Demo NodeJS
kubectl create namespace ecsdemo-nodejs
argocd app create ecsdemo-nodejs --repo https://github.com/wlstmd/ecsdemo-nodejs.git --path kubernetes --dest-server https://kubernetes.default.svc --dest-namespace ecsdemo-nodejs
```

## ArgoCD App Get

```sh
argocd app get ecsdemo-nodejs
```

## ArgoCD App Sync

```sh
argocd app sync ecsdemo-nodejs
```
