# Kong API Gateway (Gateway API) on EKS

```bash
EKS_CLUSTER_NAME=<EKS_CLUSTER_NAME>
```

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
```

```bash
cat << EOF > values.yaml
gateway:
  admin:
    http:
      enabled: true
  proxy:
    type: NodePort
    http:
      enabled: true
      nodePort: 32001
    tls:
      enabled: false
EOF
```

```bash
helm repo add kong https://charts.konghq.com
helm repo update
helm install kong kong/ingress -n kong --create-namespace -f values.yaml
```

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

- 이제 GatewayClass를 이용하여, Kubernetes Gateway API와 Kong Gateway를 통합하여 외부 및 내부 트래픽을 효율적으로 관리할 수 있도록 설정

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kong-class
  annotations:
    konghq.com/gatewayclass-unmanaged: "true"
spec:
  controllerName: konghq.com/kic-gateway-controller
```

```bash
kubectl apply -f kong-gw-class.yaml
```

- Kong Gateway가 모든 네임스페이스의 HTTP 요청(포트 80)을 수신하고 라우팅할 수 있도록 구성

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kong-gateway
  namespace: kong
spec:
  gatewayClassName: kong-class
  listeners:
    - name: kong-listeners
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
```

```bash
kubectl apply -f kong-gw-gateway.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: kong
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: kong
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
```

```bash
kubectl apply -f deploy.yaml
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: kong-httproute
  namespace: kong
  annotations:
    konghq.com/strip-path: "false"
spec:
  parentRefs:
    - name: kong-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: nginx-service
          port: 80
          kind: Service
```

```bash
kubectl apply -f kong-HTTProute.yaml
```

- 이제 Kong Proxy로 HTTProute를 통하여, 정상적으로 호출을 합니다. 이제 ingress 생성할 때, Service를 Kong으로 잡습니다.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kong-ingress
  namespace: kong
  annotations:
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/group.name: kong-tg
    alb.ingress.kubernetes.io/healthcheck-path: /healthcheck
    alb.ingress.kubernetes.io/load-balancer-name: kong-alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    kubernetes.io/ingress.class: alb

spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kong-gateway-proxy
                port:
                  number: 80
```

```bash
kubectl apply -f kong-ingress.yaml
```

!image.png
</content>
