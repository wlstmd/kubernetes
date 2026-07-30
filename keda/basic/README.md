# KEDA 설치 및 Cron 트리거 ScaledObject 구성

## KEDA 설치 (Helm)

```sh
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm install keda kedacore/keda --namespace keda
```

## ScaledObject 및 Deployment 배포

`scaledobject.yaml`은 `cron` 트리거(`Asia/Seoul` 기준 매시 00/15/30/45분에 시작, 05/20/35/50분에 종료)로 `php-apache` Deployment(`deployment.yaml`)를 스케일하는 예제이다.

```sh
kubectl apply -f scaledobject.yaml
kubectl apply -f deployment.yaml
```

## ScaledObject 확인

```sh
kubectl get scaledobject
kubectl describe scaledobject
```
