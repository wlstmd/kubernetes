# Pod 내 컨테이너 간 볼륨 공유 (emptyDir)

하나의 Pod 안에서 `emptyDir` 볼륨을 공유하는 두 컨테이너(nginx, debian) 실습. debian 컨테이너가 작성한 `index.html`을 nginx 컨테이너가 그대로 서빙하는지 확인한다.

## Deploy

```sh
kubectl apply -f two-container.yaml
```

## Response Check

```sh
kubectl exec -it two-containers -c nginx-container -- curl localhost
kubectl exec -it two-containers -c nginx-container -- cat /usr/share/nginx/html/index.html
```

## 참고: two-container.yaml

`shared-data`라는 `emptyDir` 볼륨을 nginx-container와 debian-container가 함께 마운트한다. debian-container는 시작 시 `index.html`을 생성한다.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: two-containers
spec:
  restartPolicy: Never

  volumes:
    - name: shared-data
      emptyDir: {}

  containers:
    - name: nginx-container
      image: nginx
      volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html

    - name: debian-container
      image: debian
      volumeMounts:
        - name: shared-data
          mountPath: /pod-data
      command: ["/bin/sh"]
      args: ["-c", "echo debian 컨테이너에서 안녕하세요 > /pod-data/index.html"]
```
