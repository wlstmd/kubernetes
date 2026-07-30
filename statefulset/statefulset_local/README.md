# StatefulSet + 로컬 볼륨(hostPath) 실습

워커 노드에 로컬 디렉토리를 준비하고, StatefulSet을 배포하여 Pod 내부에서 로컬 볼륨이 노드의 hostPath와 정상적으로 매핑되는지 확인하는 실습 정리.

## 노드 확인
```sh
kubectl get node  
```

## 각 노드에 접속 후 폴더 생성 및 StatefulSet 배포
```sh
sudo mkdir -p /mnt/common
kubectl apply -f statefulset-local.yaml
```

## Pod 내부 shell 접속
```sh
kubectl exec -it statefulset-demo-0-0 -- /bin/bash
```

## 마운트된 디렉토리 확인
```sh
df -h /usr/share/nginx/html
```

## 테스트 파일 생성
```sh
echo "Hello from Kubernetes!" > /usr/share/nginx/html/index.html
```

## 노드에 ssh 접속 후
```sh
ls -l /tmp/k8s-pv-statefulset-demo
cat /tmp/k8s-pv-statefulset-demo/index.html
```
