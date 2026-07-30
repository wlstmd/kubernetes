# Kubernetes Dashboard 설치 및 접속

## Kubernetes Dashboard 설치

```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.6.1/aio/deploy/recommended.yaml
```

## 프록시 실행

```sh
kubectl proxy &
```

## SSH 터널링 (원격 접속용)

```sh
ssh -i <your-key-file.pem> -L 8001:127.0.0.1:8001 ec2-user@<your-ec2-public-ip>
```

## admin-user 서비스 계정 생성

```sh
kubectl apply -f admin-user-config.yaml
```

## 접속 토큰 발급 및 대시보드 접속

```sh
kubectl -n kubernetes-dashboard create token admin-user

http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```
