# hostPath 볼륨 테스트

노드의 로컬 디렉터리를 `hostPath` 볼륨으로 마운트하여, 파일이 없을 때/있을 때 응답이 어떻게 달라지는지 확인하는 실습.

## 노드 접속 후

노드에 접속해 웹 페이지로 쓸 디렉터리와 파일을 만들고, Pod를 배포한 뒤 응답을 확인한다.

```sh
sudo mkdir /tmp/webpage
cd /tmp/webpage
echo "hello world" > index.html

kubectl apply -f pod.yaml

kubectl get pods -o wide

kubectl exec hostpath-pod -- curl localhost # 폴더 생성전에는 403응답이 나옴 폴더 생성 후 200응답이 나옴
```

## 참고: pod.yaml

`/tmp/webpage`를 hostPath 볼륨으로 마운트하는 Pod 정의.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-pod
spec:
  containers:
    - name: hostpath-pod
      image: nginx:latest
      volumeMounts:
        - mountPath: /usr/share/nginx/html/
          name: hostpath-volume
  volumes:
    - name: hostpath-volume
      hostPath:
        path: /tmp/webpage
        type: Directory # Directory
```
