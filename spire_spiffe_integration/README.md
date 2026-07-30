# SPIRE/SPIFFE + Istio 연동

```bash
CLUSTER_NAME="<EKS_CLUSTER_NAME>"
CLUSTER_OIDC=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)
```

```bash
cat << EOF > aws-ebs-csi-driver-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/OIDC"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "OIDC:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF
```

```bash
sed -i "s|ACCOUNT_ID|$ACCOUNT|g" aws-ebs-csi-driver-trust-policy.json
sed -i "s|OIDC|$CLUSTER_OIDC|g" aws-ebs-csi-driver-trust-policy.json
```

```bash
aws iam create-role --role-name AmazonEKS_EBS_CSI_DriverRole --assume-role-policy-document file:///home/ec2-user/aws-ebs-csi-driver-trust-policy.json
```

```bash
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy --role-name AmazonEKS_EBS_CSI_DriverRole
```

```bash
eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --service-account-role-arn arn:aws:iam::$ACCOUNT:role/AmazonEKS_EBS_CSI_DriverRole --force
```

```bash
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

- helm으로 spire-crds, spire를 설치

```bash
helm upgrade --install -n spire-server spire-crds spire-crds --repo https://spiffe.github.io/helm-charts-hardened/ --create-namespace
helm upgrade --install -n spire-server spire spire --repo https://spiffe.github.io/helm-charts-hardened/ --wait --set global.spire.trustDomain="example.org"
```

- SPIRE에 workload를 등록하는 방법은 두 가지가 있다
- ClusterSPIFFEID CR을 활용해 필터링 된 pod를 자동으로 등록하거나,
- spire-server pod에 접근하여 spire-server 명령어로 수동 등록할 수 있다.

- 자동으로 등록하려면 Istio gateway, Istio sidecar를 위한 ClusterSPIFFEID 리소스를 각각 생성한다.

istio-ingressgateway-reg-cluster-spiffeid.yaml

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: istio-ingressgateway-reg
spec:
  spiffeIDTemplate: "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
  workloadSelectorTemplates:
    - "k8s:ns:istio-system"
    - "k8s:sa:istio-ingressgateway-service-account"
```

istio-sidecar-reg-cluster-spiffeid.yaml

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: istio-sidecar-reg
spec:
  spiffeIDTemplate: "spiffe://{{ .TrustDomain }}/ns/{{ .PodMeta.Namespace }}/sa/{{ .PodSpec.ServiceAccountName }}"
  podSelector:
    matchLabels:
      spiffe.io/spire-managed-identity: "true"
  workloadSelectorTemplates:
    - "k8s:ns:default"
```

- 수동으로 등록하려면, spire-server pod에 exec로 접근하여 /opt/spire/bin/spire-server 명령어를 사용한다

```bash
SPIRE_SERVER_POD=$(kubectl get pod -l statefulset.kubernetes.io/pod-name=spire-server-0 -n spire-server -o jsonpath="{.items[0].metadata.name}")
```

- Istio 공식 문서에서는 spire ns를 사용하고 socketPath를 /run/spire/sockets/server.sock으로 지정하는데,
- namespace가 존재하지 않는다는 것과 실행 시 폴더를 찾을 수 없다는 문제가 있었다.
- 따라서 spire-server로 ns를 변경하고,
- SPIFFE의 공식 문서를 따라 default 값을 사용하면 문제가 해결된다
  https://spiffe.io/docs/latest/deploying/spire_server/

```bash
kubectl exec -n spire-server "$SPIRE_SERVER_POD" -- \
/opt/spire/bin/spire-server entry create \
    -spiffeID spiffe://example.org/ns/istio-system/sa/istio-ingressgateway-service-account \
    -parentID spiffe://example.org/ns/spire/sa/spire-agent \
    -selector k8s:sa:istio-ingressgateway-service-account \
    -selector k8s:ns:istio-system
```

## Istio

- Istio 설치 전, Gateway API crds를 설치

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

- spiffe/spire 설정을 위한 IstioOperator manifest를 작성한다
  - 문서 예제를 그대로 사용
- Code
  ```yaml
  apiVersion: install.istio.io/v1alpha1
  kind: IstioOperator
  metadata:
    namespace: istio-system
  spec:
    profile: default
    meshConfig:
      trustDomain: example.org
    values:
      # This is used to customize the sidecar template.
      # It adds both the label to indicate that SPIRE should manage the
      # identity of this pod, as well as the CSI driver mounts.
      sidecarInjectorWebhook:
        templates:
          spire: |
            labels:
              spiffe.io/spire-managed-identity: "true"
            spec:
              containers:
              - name: istio-proxy
                volumeMounts:
                - name: workload-socket
                  mountPath: /run/secrets/workload-spiffe-uds
                  readOnly: true
              volumes:
                - name: workload-socket
                  csi:
                    driver: "csi.spiffe.io"
                    readOnly: true
    components:
      ingressGateways:
        - name: istio-ingressgateway
          enabled: true
          label:
            istio: ingressgateway
          k8s:
            overlays:
              # This is used to customize the ingress gateway template.
              # It adds the CSI driver mounts, as well as an init container
              # to stall gateway startup until the CSI driver mounts the socket.
              - apiVersion: apps/v1
                kind: Deployment
                name: istio-ingressgateway
                patches:
                  - path: spec.template.spec.volumes.[name:workload-socket]
                    value:
                      name: workload-socket
                      csi:
                        driver: "csi.spiffe.io"
                        readOnly: true
                  - path: spec.template.spec.containers.[name:istio-proxy].volumeMounts.[name:workload-socket]
                    value:
                      name: workload-socket
                      mountPath: "/run/secrets/workload-spiffe-uds"
                      readOnly: true
                  - path: spec.template.spec.initContainers
                    value:
                      - name: wait-for-spire-socket
                        image: busybox:1.36
                        volumeMounts:
                          - name: workload-socket
                            mountPath: /run/secrets/workload-spiffe-uds
                            readOnly: true
                        env:
                          - name: CHECK_FILE
                            value: /run/secrets/workload-spiffe-uds/socket
                        command:
                          - sh
                          - "-c"
                          - |-
                            echo "$(date -Iseconds)" Waiting for: ${CHECK_FILE}
                            while [[ ! -e ${CHECK_FILE} ]] ; do
                              echo "$(date -Iseconds)" File does not exist: ${CHECK_FILE}
                              sleep 15
                            done
                            ls -l ${CHECK_FILE}
  ```
- istioctl로 설치

```bash
curl -L https://istio.io/downloadIstio | sh -
cd istio-1.27.0
export PATH=$PWD/bin:$PATH
istioctl version
```

```bash
istioctl install --skip-confirmation -f ./istio.yaml
```

```bash
$ kubectl get po -n istio-system
NAME                                    READY   STATUS    RESTARTS   AGE
istio-ingressgateway-5f447d94f8-h6qdd   1/1     Running   0          56s
istiod-566955fbd5-5sjdx                 1/1     Running   0          70s
```

## Application

- 테스트를 위해 간단하게 서로 통신이 가능한 애플리케이션을 구성해보았다
  - GET / 요청 시, 내부에서 APP_URL env 주소로 GET /api 요청을 보낸다
- Code

  main.go

  ```go
  package main

  import (
          "fmt"
          "io"
          "log"
          "net/http"
          "os"
  )

  func proxyHandler(w http.ResponseWriter, r *http.Request) {
          appURL := os.Getenv("APP_URL")
          if appURL == "" {
                  http.Error(w, "APP_URL not set", http.StatusBadRequest)
                  return
          }

          target := fmt.Sprintf("http://%s/api", appURL)
          resp, err := http.Get(target)
          if err != nil {
                  http.Error(w, fmt.Sprintf("failed to call %s: %v", target, err), http.StatusBadGateway)
                  return
          }
          defer resp.Body.Close()

          w.WriteHeader(resp.StatusCode)
          io.Copy(w, resp.Body)
  }

  func apiHandler(w http.ResponseWriter, r *http.Request) {
          if r.Method != http.MethodGet {
                  http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
                  return
          }
          w.WriteHeader(http.StatusOK)
          w.Write([]byte("app page"))
  }

  func main() {
          http.HandleFunc("/", proxyHandler)
          http.HandleFunc("/api", apiHandler)

          addr := ":8080"
          log.Printf("server listening on %s", addr)
          log.Fatal(http.ListenAndServe(addr, nil))
  }
  ```

  - Dockerfile

  ```docker
  FROM golang:alpine
  WORKDIR /app
  COPY main.go .
  RUN apk add --no-cache curl && go mod init noah.io/ark/rest && go build main.go
  EXPOSE 8080
  CMD ["./main"]
  ```

- 애플리케이션을 Docker 컨테이너로 registry에 build/push 한다
- 이제 k8s에 istio 및 spire를 연결하여 애플리케이션을 배포하기 위해 manifest를 작성한다
  - inject annotation으로 sidecar와 spire을 설정하고, spiffe CSI volume을 설정해야 한다
- conn-a, conn-b 와 같이 2개를 배포했다

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: conn-a
  labels:
    app: conn-a
  # Injects custom sidecar template
  annotations:
    inject.istio.io/templates: "sidecar,spire"
spec:
  containers:
    - name: app
      image: ghcr.io/dya-only/conn:latest
      ports:
        - containerPort: 8080
      env:
        # ENV for requests to other API
        - name: APP_URL
          value: conn-b
  volumes:
    # CSI volume
    - name: workload-socket
      csi:
        driver: "csi.spiffe.io"
        readOnly: true
---
apiVersion: v1
kind: Service
metadata:
  name: conn-a
spec:
  selector:
    app: conn-a
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: conn-b
  labels:
    app: conn-b
  # Injects custom sidecar template
  annotations:
    inject.istio.io/templates: "sidecar,spire"
spec:
  containers:
    - name: app
      image: ghcr.io/dya-only/conn:latest
      ports:
        - containerPort: 8080
      env:
        # ENV for requests to other API
        - name: APP_URL
          value: conn-a
  volumes:
    # CSI volume
    - name: workload-socket
      csi:
        driver: "csi.spiffe.io"
        readOnly: true
---
apiVersion: v1
kind: Service
metadata:
  name: conn-b
spec:
  selector:
    app: conn-b
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
```

- 이제 conn-a, conn-b를 모두 istioctl을 사용해서 istio-proxy 등을 주입해 실행한다

```bash
istioctl kube-inject --filename ./conn-a.yaml | kubectl apply -f -
istioctl kube-inject --filename ./conn-b.yaml | kubectl apply -f -
```

- Pod가 istio-proxy 컨테이너와 함께 실행되는 것을 확인할 수 있다

!image.webp

## Check

- 먼저 아래 명령어로 workload를 위한 identity들이 생성된 것을 확인한다

```bash
SPIRE_SERVER_POD=$(kubectl get pod -l statefulset.kubernetes.io/pod-name=spire-server-0 -n spire-server -o jsonpath="{.items[0].metadata.name}")
kubectl exec -t "$SPIRE_SERVER_POD" -n spire-server -c spire-server -- ./bin/spire-server entry show
```

- Ingress-gateway가 여전히 Running 상태인지 확인한다

```bash
$ kubectl get po -n istio-system
NAME                                    READY   STATUS    RESTARTS   AGE
istio-ingressgateway-5f447d94f8-h6qdd   1/1     Running   0          3h19m
istiod-566955fbd5-5sjdx                 1/1     Running   0          3h20m
```

- conn app pod가 가지고 있는 TLS cert를 가져와서 SPIRE로 인증되었는지 확인한다.

```bash
APP_POD=$(kubectl get pod -l app=conn-a -o jsonpath="{.items[0].metadata.name}")
istioctl proxy-config secret "$APP_POD" -o json | jq -r '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' | base64 --decode > chain.pem
```

```bash
$ openssl x509 -in chain.pem -text | grep SPIRE
Subject: C=US, O=SPIRE
```

- 애플리케이션 컨테이너에 접근해서 다른 서비스로 HTTP 요청이 가능한지 확인한다.

```bash
/app # curl conn-b/api
app page
```

## Kiali + Prometheus

- Kiali와 Prometheus Istio addon을 설치해서 Graph로 확인해볼 수도 있다

```bash
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/kiali.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/prometheus.yaml
```

- 설치 후 conn-a → conn-b 요청을 몇 번 시도한 후, Kiali dashboard에 접근하여 Traffic Graph를 확인하자

```bash
kubectl exec conn-a -- curl http://conn-b/api
```

```bash
kubectl port-forward svc/kiali 20001:20001 -n istio-system --address 0.0.0.0
```

```bash
kubectl patch svc kiali -n istio-system -p '{"spec": {"type": "LoadBalancer"}}'
```

- conn-a Pod에서 conn-b Service, Pod로 접근할 때 mTLS가 활성화되어 있음을 확인할 수 있다
</content>
