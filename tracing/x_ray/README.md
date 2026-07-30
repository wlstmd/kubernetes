# EKS에 AWS X-Ray 데몬 및 샘플 앱 배포

IRSA로 X-Ray 데몬용 서비스 어카운트를 만들고, X-Ray 데몬을 DaemonSet으로 배포한 뒤 샘플 프론트/백엔드 앱으로 트레이스를 발생시켜 확인하는 실습.

## ENV

```sh
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
CLUSTER_OIDC=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

## IRSA (Create the service account for X-Ray.)

```sh
eksctl create iamserviceaccount \
  --name xray-daemon \
  --namespace default \
  --cluster $EKS_CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess \
  --override-existing-serviceaccounts \
  --approve 
```

## Apply a label to the service account

```sh
kubectl label serviceaccount xray-daemon app=xray-daemon
```

## X-Ray DaemonSet

```sh
kubectl apply -f xray-k8s-daemonset.yaml
kubectl describe daemonset xray-daemon
kubectl logs -l app=xray-daemon
```

## X-Ray Sample App

```sh
kubectl apply -f https://eksworkshop.com/intermediate/245_x-ray/sample-front.files/x-ray-sample-front-k8s.yml
kubectl apply -f https://eksworkshop.com/intermediate/245_x-ray/sample-back.files/x-ray-sample-back-k8s.yml
kubectl describe deployments x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl describe services x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl get service x-ray-sample-front-k8s -o wide
```

## Delete

```sh
kubectl delete deployments x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl delete services x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl delete -f xray-k8s-daemonset.yaml
eksctl delete iamserviceaccount --name xray-daemon --cluster $EKS_CLUSTER_NAME
```

## 참고 매니페스트

`x-ray-sample-front-k8s.yml`, `x-ray-sample-back-k8s.yml`은 스크립트에서는 원격 URL(`eksworkshop.com`)로 적용하지만, 동일한 내용의 로컬 사본이 이 폴더에도 보관되어 있다.

`xray-k8s-daemonset.yaml` (ClusterRoleBinding + DaemonSet + ConfigMap + headless Service):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: xray-daemon
  labels:
    app: xray-daemon
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: xray-daemon
    namespace: default
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: xray-daemon
spec:
  updateStrategy:
    type: RollingUpdate
  selector:
    matchLabels:
      app: xray-daemon
  template:
    metadata:
      labels:
        app: xray-daemon
    spec:
      volumes:
        - name: config-volume
          configMap:
            name: xray-config
      hostNetwork: true
      serviceAccountName: xray-daemon
      containers:
        - name: xray-daemon
          image: amazon/aws-xray-daemon
          imagePullPolicy: Always
          command: ["/usr/bin/xray", "-c", "/aws/xray/config.yaml"]
          resources:
            limits:
              memory: 24Mi
          ports:
            - name: xray-ingest
              containerPort: 2000
              hostPort: 2000
              protocol: UDP
          volumeMounts:
            - name: config-volume
              mountPath: /aws/xray
              readOnly: true
---
# Configuration for AWS X-Ray daemon
apiVersion: v1
kind: ConfigMap
metadata:
  name: xray-config
data:
  config.yaml: |-
    # Maximum buffer size in MB (minimum 3). Choose 0 to use 1% of host memory.
    TotalBufferSizeMB: 0
    # Maximum number of concurrent calls to AWS X-Ray to upload segment documents.
    Concurrency: 8
    # Send segments to AWS X-Ray service in a specific region
    Region: ""
    # Change the X-Ray service endpoint to which the daemon sends segment documents.
    Endpoint: ""
    Socket:
      # Change the address and port on which the daemon listens for UDP packets containing segment documents.
      # Make sure we listen on all IP's by default for the k8s setup
      UDPAddress: 0.0.0.0:2000
    Logging:
      LogRotation: true
      # Change the log level, from most verbose to least: dev, debug, info, warn, error, prod (default).
      LogLevel: prod
      # Output logs to the specified file path.
      LogPath: ""
    # Turn on local mode to skip EC2 instance metadata check.
    LocalMode: false
    # Amazon Resource Name (ARN) of the AWS resource running the daemon.
    ResourceARN: ""
    # Assume an IAM role to upload segments to a different account.
    RoleARN: ""
    # Disable TLS certificate verification.
    NoVerifySSL: false
    # Upload segments to AWS X-Ray through a proxy.
    ProxyAddress: ""
    # Daemon configuration file format version.
    Version: 1
---
# k8s service definition for AWS X-Ray daemon headless service
apiVersion: v1
kind: Service
metadata:
  name: xray-service
spec:
  selector:
    app: xray-daemon
  clusterIP: None
  ports:
    - name: incoming
      port: 2000
      protocol: UDP
```

`x-ray-sample-back-k8s.yml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: x-ray-sample-back-k8s
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: x-ray-sample-back-k8s
    tier: backend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x-ray-sample-back-k8s
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 2
      maxSurge: 2
  selector:
    matchLabels:
      app: x-ray-sample-back-k8s
      tier: backend
  template:
    metadata:
      labels:
        app: x-ray-sample-back-k8s
        tier: backend
    spec:
      containers:
        - name: x-ray-sample-back-k8s
          image: rnzdocker1/eks-workshop-x-ray-sample-back:ba01b042766edb5fc794733b0af28d92d99b63dd
          securityContext:
            privileged: false
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
          ports:
            - containerPort: 8080
```

`x-ray-sample-front-k8s.yml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: x-ray-sample-front-k8s
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: x-ray-sample-front-k8s
    tier: frontend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x-ray-sample-front-k8s
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 2
      maxSurge: 2
  selector:
    matchLabels:
      app: x-ray-sample-front-k8s
      tier: frontend
  template:
    metadata:
      labels:
        app: x-ray-sample-front-k8s
        tier: frontend
    spec:
      containers:
        - name: x-ray-sample-front-k8s
          image: rnzdocker1/eks-workshop-x-ray-sample-front:ba01b042766edb5fc794733b0af28d92d99b63dd
          securityContext:
            privileged: false
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
          ports:
            - containerPort: 8080
```
