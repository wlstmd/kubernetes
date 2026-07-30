# NetworkPolicy 동작 확인

이 폴더의 `client-pod.yaml`, `web-pod.yaml`, `test-pod.yaml`, `web-service.yaml`, `network-policy.yaml` 매니페스트로 `network-policy-demo` 네임스페이스에 리소스가 이미 배포되어 있다는 전제로, 아래 명령어들로 `web-allow-same-namespace` NetworkPolicy(같은 네임스페이스의 `app: client` 파드에서 오는 Ingress만 `app: web` 파드에 허용)의 동작을 확인한다.

## Pod 상태 확인

```sh
kubectl get pod web-pod -n network-policy-demo -o wide
```

## 같은 네임스페이스 내 통신 테스트

`client-pod`, `test-pod`에서 `web-pod`의 IP로 직접 통신을 시도한다. (서비스 이름으로의 접근은 주석 처리되어 있음)

```sh
kubectl exec -n network-policy-demo client-pod -- wget -O- --timeout=2 http://10.244.0.3
kubectl exec -n network-policy-demo test-pod -- wget -O- --timeout=2 http://10.244.0.3

# kubectl exec -n network-policy-demo client-pod -- wget -O- --timeout=2 http://web-service
```

## NetworkPolicy 확인

```sh
kubectl get networkpolicy -n network-policy-demo
kubectl describe networkpolicy web-allow-same-namespace -n network-policy-demo
```

## 다른 네임스페이스에서 접근 테스트

`default` 네임스페이스에서 임시 파드를 띄워 `network-policy-demo` 네임스페이스의 `web-pod` 서비스로 접근을 시도한다 (NetworkPolicy가 같은 네임스페이스만 허용하므로 차단되는지 확인).

```sh
kubectl run test-pod --namespace=default --image=alpine --restart=Never --rm -i -- wget -O- --timeout=2 http://web-pod.network-policy-demo
```
