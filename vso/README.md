# HashiCorp Vault + Vault Secrets Operator(VSO) 구성

Vault를 dev 모드로 설치하고, Vault Secrets Operator(VSO)를 통해 Vault의 정적 시크릿을 Kubernetes Secret으로 동기화하는 실습. Kubernetes Auth Method로 인증하고, `VaultAuth`/`VaultStaticSecret` CRD로 시크릿을 주기적으로 갱신(refresh)한다.

## Vault Secrets Operator 설치

Vault를 dev 모드로 설치한 뒤, VSO를 설치하고 기본 VaultConnection을 확인한다.

```sh
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

cat << EOF > vault-values.yaml
server:
  dev:
    enabled: true
    devRootToken: "root"
  logLevel: debug
  # service:
  #   enabled: true
  #   type: ClusterIP
  #   # Port on which Vault server is listening
  #   port: 8200
  #   # Target port to which the service should be mapped to
  #   targetPort: 8200
ui:
  enabled: true
  serviceType: "LoadBalancer"
  externalPort: 8200

injector:
  enabled: "false"
EOF

helm install vault hashicorp/vault -n vault --create-namespace --values vault-values.yaml

cat << EOF > vso-values.yaml
defaultVaultConnection:
  enabled: true
  address: http://vault:8200
  skipTLSVerify: false
  spec:
  template:
    spec:
      containers:
      - name: manager
        args:
        - "--client-cache-persistence-model=direct-encrypted"
EOF

helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    -n vault \
    -f vso-values.yaml

kubectl get po -n vault 

kubectl get vaultconnections.secrets.hashicorp.com  -n vault default  -o yaml
```

## Vault Secrets Operator 정적 시크릿 정의

Vault 파드 안에 접속해 KV v2 시크릿 엔진을 활성화하고 테스트용 시크릿을 등록한다.

```sh
kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh


vault secrets enable -path vso-test -version=2 kv

vault kv put vso-test/secret test="password"

vault kv get vso-test/secret
```

## Kuberenetes Auth Method 구성

Kubernetes Auth Method를 활성화하고, 조회 전용 정책과 역할(role)을 등록해 `vso-sa` 서비스 어카운트가 해당 정책으로 인증하도록 구성한다.

```sh
vault auth enable kubernetes

vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc.cluster.local"

vault policy write vso-policy - <<EOF
path "vso-test/data/secret" {
  capabilities = ["read"]
}
EOF

exit

kubectl create sa vso-sa

kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

vault write auth/kubernetes/role/vso \
  bound_service_account_names=vso-sa \
  bound_service_account_namespaces=default \
  policies=vso-policy \
  ttl=5m

exit
```

## Vault CRD 설정(VaultAuth, VaultStaticSecret)

`VaultAuth`와 `VaultStaticSecret` CR을 적용해 Vault의 정적 시크릿을 `vsosecret`이라는 Kubernetes Secret으로 동기화하고, Vault 쪽 값을 변경했을 때 `refreshAfter` 주기로 자동 반영되는지 확인한다.

```sh
kubectl apply -f - <<EOF
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: static-auth
  namespace: default
spec:
  kubernetes:
    audiences:
    - vault
    role: vso
    serviceAccount: vso-sa
    tokenExpirationSeconds: 600
  method: kubernetes
  mount: kubernetes
EOF

kubectl apply -f -<<EOF
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: vault-kv
  namespace: default
spec:
  type: kv-v2
  mount: vso-test
  path: secret
  destination:
    name: vsosecret
    create: true
  refreshAfter: 30s
  vaultAuthRef: static-auth
EOF

kubectl get secrets

kubectl get secret vsosecret -o jsonpath='{.data.test}' | base64 -d

kubectl exec --stdin=true --tty=true vault-0 -n vault -- /bin/sh

vault kv put vso-test/secret test="password2"

kubectl get secret vsosecret -o jsonpath='{.data.test}' | base64 -d
```
