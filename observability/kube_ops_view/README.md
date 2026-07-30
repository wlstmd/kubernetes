# kube-ops-view 실행

## kube-ops-view 실행

```sh
kubectl proxy &
docker run -d -p 8080:8080 --net=host hjacobs/kube-ops-view
```
