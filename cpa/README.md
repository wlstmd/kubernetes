# Cluster Proportional Autoscaler 설치

노드 수에 비례해서 `deployment/nginx-deployment`의 replica 수를 조정하는 Cluster Proportional Autoscaler를 Helm으로 설치하는 스크립트(`bastion.sh`)입니다.

## values.yaml 생성

노드 수 대비 replica 비율(`ladder`)과 대상 리소스를 지정하는 `values.yaml`을 작성합니다.

```sh
cat << EOF > values.yaml
config:
  ladder:
    nodesToReplicas:
      - [1, 1]
      - [2, 2]
options:
  namespace: default
  target: "deployment/nginx-deployment"
EOF
```

## Helm 설치

Cluster Proportional Autoscaler Helm repo를 추가하고 위 values로 설치합니다.

```sh
helm repo add cluster-proportional-autoscaler https://kubernetes-sigs.github.io/cluster-proportional-autoscaler
helm repo update
helm upgrade --install cluster-proportional-autoscaler \
	-f values.yaml \
    cluster-proportional-autoscaler/cluster-proportional-autoscaler
```

## 로그 확인

배포된 Cluster Proportional Autoscaler 파드 로그를 확인합니다.

```sh
kubectl logs -l  app.kubernetes.io/instance=cluster-proportional-autoscaler
```
