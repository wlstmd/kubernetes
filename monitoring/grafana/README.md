# Grafana 설치

## 기존 세팅은 Prometheus와 동일함

```sh
kubectl create namespace grafana

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana \
    --namespace grafana \
    --set persistence.storageClassName="gp2" \
    --set persistence.enabled=true \
    --set adminPassword='admin1234' \
    --values prometheus-source.yaml \
    --set service.type=ClusterIP
```

`prometheus-source.yaml`을 데이터소스 값 파일로 사용해서 Grafana가 Prometheus를 기본 데이터소스로 바라보게 설정한다. `ingress-grafana.yaml`을 따로 적용하면 기존 `skills-alb`에 `/grafana` 경로로 노출된다.
