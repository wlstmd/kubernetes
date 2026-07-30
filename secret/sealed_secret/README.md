# Sealed Secrets 실습

Bitnami Sealed Secrets를 이용해 평문 Secret을 SealedSecret으로 암호화하고, 클러스터에 안전하게 배포(GitOps 방식)하는 실습 정리.

## Client Side
```sh
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/kubeseal-0.27.1-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.1-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Server Side
```sh
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/controller.yaml
kubectl create secret generic mysecret --from-literal hello=world --dry-run=client -oyaml > mysecret.yaml
cat mysecret.yaml | kubeseal -oyaml > mysealed-secret.yaml # sealed secret
```

## 수동배포 보통은 GitOps
```sh
kubectl apply -f mysealed-secret.yaml
kubectl get sealedsecret mysecret
kubectl get secret mysecret
```
