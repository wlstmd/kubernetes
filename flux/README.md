# FluxCD GitOps 구성 및 실습

Flux CLI 설치와 GitHub 부트스트랩부터 시작해서 Git 소스/Kustomization, HelmRelease(값 오버라이드 포함), Weave GitOps 대시보드까지 실습하는 스크립트(`bastion.sh`)입니다.

## Flux CLI 설치 및 GitHub 부트스트랩

Flux CLI를 설치하고, GitHub 저장소(`fluxcd-repo`)를 대상으로 클러스터에 Flux를 부트스트랩합니다.

```sh
curl -s https://fluxcd.io/install.sh | sudo bash

export GITHUB_USER=wlstmd
export GITHUB_TOKEN=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

flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=fluxcd-repo \
  --branch=main \
  --path=./clusters/skills-eks-cluster \
  --personal
```

## Flux 설치 확인

`flux-system` 네임스페이스의 파드/리소스와 설치된 Flux CRD를 확인합니다.

```sh
kubectl get pods -n flux-system
kubectl get-all -n flux-system
kubectl get crd | grep fluxc
```

## Git Source 및 Kustomization 생성

테스트용 Git 저장소를 소스로 등록하고, `./nginx` 경로를 대상으로 하는 Kustomization을 생성합니다.

```sh
GITURL="https://github.com/wlstmd/fluxcd-test.git"
flux create source git nginx-example1 \
  --url=$GITURL \
  --branch=main \
  --interval=30s

flux get sources git
kubectl -n flux-system get gitrepositories

flux create kustomization nginx-example1 \
  --target-namespace=default \
  --prune=true \
  --interval=1m \
  --source=nginx-example1 \
  --path="./nginx" \
  --health-check-timeout=2m
```

## 리소스 및 동기화 상태 확인

`default` 네임스페이스의 리소스와 Kustomization 동기화 상태를 확인합니다.

```sh
kubectl -n default get po,svc

flux get kustomizations
kubectl -n flux-system get kustomizations
```

## 자동 sync확인

원격 저장소에 push해서 Flux가 자동으로 동기화하는지 확인하고, 반영된 이미지를 확인합니다.

```sh
git push origin main

kubectl -n default  describe po nginx-example1 | grep "Image:"
```

## 삭제

Kustomization과 Git 소스를 삭제합니다.

```sh
flux delete kustomization nginx-example1
kubectl -n default get po,svc
flux -n default delete source git nginx-example1
```

## flux 삭제

Flux 자체를 클러스터에서 제거합니다.

```sh
flux uninstall --namespace=flux-system
```

## HELM

HelmRelease로 차트를 배포하고, `dev-values.yaml`과 ConfigMap을 통한 값 오버라이드로 리비전이 올라가는 것을 확인한 뒤, 관련 리소스를 정리합니다.

```sh
flux create helmrelease helm-application-example \
  --chart hello-world \
  --source HelmRepository/helm-source-example \
  --chart-version "0.1.0" \
  --namespace default

kubectl get HelmRelease -n default
flux get HelmRelease -n default
helm -n default ls

cat <<EOF > dev-values.yaml
replicaCount: 2
EOF

flux create helmrelease helm-application-example \
  --chart hello-world \
  --source HelmRepository/helm-source-example \
  --chart-version "0.1.0" \
  --namespace default \
  --values values.yaml

helm -n default ls # 리비전 증가


kubectl -n default describe helmrelease helm-application-example | grep "Revision:"

cat <<EOF | kubectl apply -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: override-value
  namespace: default
data:
  values.yaml: |-
    replicaCount: 3
EOF

flux create helmrelease helm-application-example \
  --chart hello-world \
  --source HelmRepository/helm-source-example \
  --chart-version "0.1.0" \
  --namespace default \
  --values-from=Configmap/override-value

kubectl -n default describe helmrelease helm-application-example # 리비전 증가

kubectl -n default get po
```

## 삭제

HelmRelease와 Helm 소스를 삭제하고 Flux를 제거합니다.

```sh
flux -n default delete helmrelease helm-application-example
flux -n defualt delete source helm helm-source-example
flux uninstall --namespace=flux-system
```

## 대시보드

Weave GitOps CLI(`gitops`)를 설치하고 대시보드를 생성한 뒤, port-forward로 접속합니다.

```sh
curl --silent --location "https://github.com/weaveworks/weave-gitops/releases/download/v0.24.0/gitops-$(uname)-$(uname -m).tar.gz" | tar xz -C /tmp
sudo mv /tmp/gitops /usr/local/bin
gitops version

PASSWORD="password"
gitops create dashboard ww-gitops \
  --password=$PASSWORD

flux -n flux-system get helmrelease

kubectl -n flux-system get pod

kubectl port-forward svc/ww-gitops-weave-gitops -n flux-system 9001:9001 --address 0.0.0.0
```
