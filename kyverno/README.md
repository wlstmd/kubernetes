# Kyverno 설치

## Kyverno 설치 (Helm)

```sh
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace \
  --set admissionController.replicas=3 \
  --set backgroundController.replicas=2 \
  --set cleanupController.replicas=2 \
  --set reportsController.replicas=2
```

## 설치 확인

```sh
kubectl -n kyverno get pods
```

> `Policy/` 디렉터리에 개별 Kyverno ClusterPolicy 예시(add-network-policy, require-labels, restrict-image-registries 등)가 별도로 있다.
