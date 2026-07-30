# Crossplane + provider-aws

https://docs.crossplane.io/latest/get-started/

https://github.com/crossplane-contrib/provider-aws/tree/master/examples

https://github.com/crossplane-contrib/provider-aws

https://doc.crds.dev/github.com/crossplane/provider-aws@v0.54.2

- Install Crossplane

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm install crossplane --namespace crossplane-system --create-namespace crossplane-stable/crossplane
```

- Install CrossPlane CLI

```bash
curl -sL "https://raw.githubusercontent.com/crossplane/crossplane/main/install.sh" | sh
```

`forProvider`

이 필드는 프로바이더에 제공되는 필드다. 여기에 포함된 필더는 프로바이더 즉, AWS가 리소스를 만들 때 이 필드의 값을 사용한다.

`writeConnectionSecretToRef`

생성한 매니지드 리소스에 관한 연결 정보(엔드포인트나, 이름 등)를 저장할 시크릿을 저장한다. 생성한 리소스의 정보를 시크릿에 저장하고 서비스에서 사용할 Pod에서 이 시크릿을 연결해서 정보를 사용하는 구조다.

`providerConfigRef`

어떤 `ProviderConfig`를 사용할지 지정하고 생략할 시 `default` 구성을 사용한다.

`deletionPolicy`

매니지드 리소스를 삭제했을 때 실제 클라우드의 리소스를 어떻게 할지를 정한다. `Delete`로 지정하면 매니지드 리소스를 지울 때 클라우드의 리소스도 지우고 `Orphan`으로 지정하면 클라우드 리소스는 놔두고 Kubernetes 안에서만 지운다.

### Secret 방식

- Manual
  ```yaml
  apiVersion: pkg.crossplane.io/v1
  kind: Provider
  metadata:
    name: provider-aws
  spec:
    package: xpkg.upbound.io/crossplane-contrib/provider-aws:v0.54.2
  ```
  ```bash
  kubectl apply -f provider.yaml
  ```
  ```bash
  kubectl get providers
  ```

  - aws-credentials.ini 파일 구성하기
    ```bash
    [default]
    aws_access_key_id = <AWS_ACCESS_KEY_ID>
    aws_secret_access_key = <AWS_SECRET_ACCESS_KEY_ID>
    ```
  ```bash
  kubectl create secret generic aws-secret \
    --namespace=crossplane-system \
    --from-file=creds=./aws-credentials.ini
  ```
  ```yaml
  apiVersion: aws.crossplane.io/v1beta1
  kind: ProviderConfig
  metadata:
    name: default
  spec:
    credentials:
      source: Secret
      secretRef:
        namespace: crossplane-system
        name: aws-secret
        key: creds
  ```
  ```bash
  kubectl apply -f providerconfig.yaml
  ```

### IRSA 방식

- Manual
  ```bash
  CLUSTER_NAME=<CLUSTER_NAME>
  ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
  ```
  ```bash
  OIDC=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
  ```
  ```bash
  cat << EOF > trust-policy.json
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Effect": "Allow",
              "Principal": {
                  "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/$OIDC"
              },
              "Action": "sts:AssumeRoleWithWebIdentity",
              "Condition": {
                  "StringEquals": {
                      "oidc.eks.ap-northeast-2.amazonaws.com/id/$OIDC:aud": "sts.amazonaws.com",
                      "oidc.eks.ap-northeast-2.amazonaws.com/id/$OIDC:sub": "system:serviceaccount:crossplane-system:provider-aws"
                  }
              }
          }
      ]
  }
  EOF
  ```
  ```bash
  aws iam create-role --role-name crossplane-provider-aws-role --assume-role-policy-document file://trust-policy.json
  ```
  ```bash
  aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --role-name crossplane-provider-aws-role
  ```
  ```yaml
  apiVersion: pkg.crossplane.io/v1beta1
  kind: DeploymentRuntimeConfig
  metadata:
    name: aws-config
  spec:
    serviceAccountTemplate:
      metadata:
        name: provider-aws
        annotations:
          eks.amazonaws.com/role-arn: <CrossPlane_Role_ARN>
    deploymentTemplate:
      spec:
        selector:
          matchLabels:
            app: provider-aws
        template:
          metadata:
            labels:
              app: provider-aws
          spec:
            securityContext:
              fsGroup: 2000
            containers:
              - name: package-runtime
                args:
                  - --debug
                  - --enable-management-policies
  ```
  ```bash
  kubectl apply -f config.yaml
  ```
  ```yaml
  apiVersion: pkg.crossplane.io/v1
  kind: Provider
  metadata:
    name: provider-aws
  spec:
    package: xpkg.upbound.io/crossplane-contrib/provider-aws:v0.54.2
    runtimeConfigRef:
      name: aws-config
  ```
  ```bash
  kubectl apply -f provider.yaml
  ```
  ```yaml
  apiVersion: aws.crossplane.io/v1beta1
  kind: ProviderConfig
  metadata:
    name: aws-provider
  spec:
    credentials:
      source: InjectedIdentity
  ```
  ```bash
  kubectl apply -f provider-config.yaml
  ```

### Examples

S3

```yaml
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: <BucketName>
  namespace: default
spec:
  deletionPolicy: Delete
  forProvider:
    acl: private
    locationConstraint: ap-northeast-2
  providerConfigRef:
    name: aws-provider
```

```bash
kubectl apply -f bucket.yaml
```
</content>
