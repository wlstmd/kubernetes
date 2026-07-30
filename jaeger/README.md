# Jaeger Operator 설치 및 구성

## cert-manager 설치

```sh
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml
```

## observability 네임스페이스 생성

```sh
kubectl create namespace observability
```

## Jaeger Operator 설치

```sh
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.65.0/jaeger-operator.yaml -n observability
```

## 설치 확인

```sh
kubectl get all -n observability 
```

## Jaeger 인스턴스 배포 (jaeger-operator-simple-prod.yaml)

`jaeger-operator-simple-prod.yaml`은 production 전략, in-memory 스토리지, DaemonSet agent로 구성된 Jaeger CR이다.

```sh
kubectl apply -f jaeger-operator-simple-prod.yaml
```

## port-forward로 UI 접속

```sh
kubectl port-forward svc/simple-prod-query 16686:16686 --address 0.0.0.0
```
