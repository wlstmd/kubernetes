# Calico 설치 및 NetworkPolicy 테스트

Calico CNI(tigera-operator)와 calicoctl을 설치하고, NetworkPolicy를 적용한 뒤 파드 간 통신이 정책대로 제한되는지 확인하는 실습입니다.

## install Calico

```sh
helm repo add projectcalico https://docs.tigera.io/calico/charts
kubectl create namespace tigera-operator
helm install calico projectcalico/tigera-operator --version v3.29.1 --namespace tigera-operator
# helm install calico projectcalico/tigera-operator --version v3.29.1 -f values.yaml --namespace tigera-operator
```

## install Calicoctl

```sh
curl -L https://github.com/projectcalico/calico/releases/download/v3.29.1/calicoctl-linux-amd64 -o kubectl-calico
chmod +x kubectl-calico
sudo mv kubectl-calico /usr/local/bin/calicoctl
```

## 네트워크 정책 적용

```sh
kubectl apply -f networkpolicy.yaml
```

## 테스트 파드 배포

```sh
kubectl apply -f a-pod.yaml && kubectl apply -f b-pod.yaml && kubectl apply -f c-pod.yaml
```

## 파드 간 연결 테스트

```sh
kubectl exec -it a-pod -- curl <b-pod-ip>
kubectl exec -it c-pod -- curl <c-pod-ip>
```
