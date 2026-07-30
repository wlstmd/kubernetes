# Cluster Autoscaler 설치 및 구성

EKS 클러스터에 Cluster Autoscaler를 위한 IAM 정책/서비스 어카운트를 만들고 배포한 뒤, safe-to-evict 설정을 패치하고 로그로 동작을 확인하는 스크립트(`ca.sh`)입니다.

## IAM 정책 생성

Cluster Autoscaler가 Auto Scaling Group을 제어할 수 있도록 `cluster-autoscaler-policy.json`을 기반으로 IAM 정책을 생성합니다.

```sh
aws iam create-policy \
    --policy-name AmazonEKSClusterAutoscalerPolicy \
    --policy-document file://cluster-autoscaler-policy.json
```

## Cluster Autoscaler 서비스 어카운트 생성

`kube-system` 네임스페이스에 위 정책을 붙인 `cluster-autoscaler` IAM 서비스 어카운트를 생성합니다.

```sh
eksctl create iamserviceaccount \
  --cluster=skills-eks-cluster \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --attach-policy-arn=arn:aws:iam::362708816803:policy/AmazonEKSClusterAutoscalerPolicy \
  --override-existing-serviceaccounts \
  --approve
```

## Cluster Autoscaler 배포

`cluster-auto-scaler.yaml` 매니페스트로 Cluster Autoscaler를 배포합니다.

```sh
kubectl apply -f cluster-auto-scaler.yaml
```

## Safe-to-evict 어노테이션 패치

Cluster Autoscaler 파드 자신이 축출되지 않도록 `safe-to-evict: false` 어노테이션을 패치합니다.

```sh
kubectl patch deployment cluster-autoscaler \
  -n kube-system \
  -p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'
```

## 로그 확인

Cluster Autoscaler 파드 로그를 실시간으로 확인합니다.

```sh
kubectl -n kube-system logs -f deployment.apps/cluster-autoscaler
```
