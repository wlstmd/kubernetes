# Pod Security Standards / Pod Security Admission (PSS/PSA) 실습

EKS 클러스터에서 PSP(PodSecurityPolicy) 잔존 여부를 확인하고 클러스터 로깅을 활성화한 뒤(`bastion.sh`), PSS/PSA 정책 위반 시나리오를 순서대로 적용해보는 데모(`test.sh`) 실습 정리.

## bastion.sh

## 환경 변수 설정
```sh
export AWS_REGION=ap-northeast-2
export CLUSTER_NAME=skills-eks-cluster
```

## PSP 어노테이션이 남아있는 Pod 확인
```sh
kubectl get pod -A -o jsonpath='{range .items[?(@.metadata.annotations.kubernetes.io/psp)]}{.metadata.name}{"t"}{.metadata.annotations.kubernetes.io/psp}{"t"}{.metadata.namespace}{"n"}'
```

## EKS 클러스터 로깅 활성화
```sh
eksctl utils update-cluster-logging --enable-types=all --region=$AWS_REGION \
  --cluster=$CLUSTER_NAME \
  --approve
```

## test.sh 실행 권한 부여
```sh
chmod +x test.sh
```

## policy-test 네임스페이스 정리 (test.sh 실행 전 초기화)
```sh
kubectl delete ns policy-test 2>&1
```

## test.sh — PSS/PSA 데모 시나리오

`test.sh`는 `0-ns.yaml` ~ `6-pod.yaml` 매니페스트를 순서대로 적용하며, 정상 설정과 다양한 Pod Security 위반 케이스(컨테이너 시큐리티 컨텍스트 누락, hostNetwork/hostPID/hostIPC 등)를 보여주는 데모 스크립트.

### 스크립트 선언부
```sh
#!/usr/bin/env bash
#set -o errexit

NEWLINE=$'\n'

#clear
```

### 0. 네임스페이스 생성 (0-ns.yaml)
```sh
kubectl apply -f 0-ns.yaml

echo "${NEWLINE}"
```

### 1. Good config (1-ok.yaml)
```sh
echo ">>> 1. Good config..."
kubectl apply -f 1-ok.yaml
sleep 2
kubectl delete -f 1-ok.yaml
sleep 2

echo "${NEWLINE}"
```

### 2. Deployment - Missing container security context element (2-dep-sec-cont.yaml)
```sh
echo ">>> 2. Deployment - Missing container security context element..."
kubectl apply -f 2-dep-sec-cont.yaml
sleep 2

echo "${NEWLINE}"
```

### 3. Pod - Missing container security context element (3-pod.yaml)
```sh
echo ">>> 3. Pod - Missing container security context element..."
kubectl apply -f 3-pod.yaml
sleep 2

echo "${NEWLINE}"
```

### 4. Pod - Pod security context는 있으나 container security context 누락 (4-pod.yaml)
```sh
echo ">>> 4. Pod - Pod security context, but Missing container security context element..."
kubectl apply -f 4-pod.yaml
sleep 2

echo "${NEWLINE}"
```

### 5. Pod - Container security context 설정은 있으나 잘못된 값 (5-pod.yaml)
```sh
echo ">>> 5. Pod - Container security context element present, with incorrect settings..."
kubectl apply -f 5-pod.yaml
sleep 2

echo "${NEWLINE}"
```

### 6. Pod - hostNetwork/hostPID/hostIPC 설정 오류 (6-pod.yaml)
```sh
echo ">>> 6. Pod - Container security context element present, with incorrect spec.hostNetwork, spec.hostPID, spec.hostIPC settings..."
kubectl apply -f 6-pod.yaml
sleep 2

echo "${NEWLINE}"
```
