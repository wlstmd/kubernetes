# AppArmor 프로파일 적용 실습

쿠버네티스 노드에서 AppArmor 커널 모듈 지원 여부를 확인하고, 파일 쓰기를 거부하는 AppArmor 프로파일을 만들어 파드에 적용하는 실습입니다.

## 쿠버네티스 버전은 최소 1.4 확인

```sh
kubectl get nodes -o=jsonpath=$'{range .items[*]}{@.metadata.name}: {@.status.nodeInfo.kubeletVersion}\n{end}'
```

## AppArmor 커널 모듈을 사용 가능 확인 Y 출력

```sh
cat /sys/module/apparmor/parameters/enabled

ssh gke-test-default-pool-239f5d02-gyn2 "sudo cat /sys/kernel/security/apparmor/profiles | sort"

kubectl get nodes -o=jsonpath='{range .items[*]}{@.metadata.name}: {.status.conditions[?(@.reason=="KubeletReady")].message}{"\n"}{end}'
```

## AppArmor 프로파일 생성

```sh
cat << EOF > apparmor-deny-write
profile apparmor-deny-write flags=(attach_disconnected) {
  file,
  # Deny all file writes.
  deny /** w,
}
EOF

apparmor_parser apparmor-deny-write

aa-status | grep k8s-example
```

## AppArmor 프로파일 적용

```sh
kubectl apply -f hello-apparmor.yaml

kubectl exec -it hello-apparmor -- sh

ls
touch test # Permission denied
```
