# KEDA AWS SQS TriggerAuthentication 구성 예제

> 이 폴더의 `bastion.sh`는 비어 있다. 아래는 폴더에 있는 매니페스트(`scaledobject.yaml`, `secret.yaml`, `triggerauthentication.yaml`)를 정리한 참고 자료이며, IRSA(`AWS_ROLE_ARN`)를 이용한 `TriggerAuthentication` 기반 AWS SQS ScaledObject 예제이다.

## Secret (IAM Role ARN)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: admin-secrets
data:
  AWS_ROLE_ARN: YXJuOmF3czppYW06OjM2MjcwODgxNjgwMzpyb2xlL2tlZGEtc3FzLXJvbGUK
```

## TriggerAuthentication

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-trigger-auth-aws-credentials
spec:
  secretTargetRef:
    - parameter: awsRoleArn
      name: admin-secrets
      key: AWS_ROLE_ARN
```

## ScaledObject (aws-sqs-queue 트리거)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: keda-scale-object
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-deployment # Mandatory. Must be in the same namespace as the ScaledObject
    envSourceContainerName: nginx # Optional. Default: .spec.template.spec.containers[0]
  pollingInterval: 30 # Optional. Default: 30 seconds
  cooldownPeriod: 300 # Optional. Default: 300 seconds
  idleReplicaCount: 0 # Optional. Default: ignored, must be less than minReplicaCount
  minReplicaCount: 1 # Optional. Default: 0
  maxReplicaCount: 100 # Optional. Default: 100
  fallback: # Optional. Section to specify fallback options
    failureThreshold: 3 # Mandatory if fallback section is included
    replicas: 6 # Mandatory if fallback section is included
  advanced: # Optional. Section to specify advanced options
    restoreToOriginalReplicaCount: false # Optional. Default: false
    horizontalPodAutoscalerConfig: # Optional. Section to specify HPA related options
      name: keda-hpa # Optional. Default: keda-hpa-{scaled-object-name}
      behavior: # Optional. Use to modify HPA's scaling behavior
        scaleDown:
          stabilizationWindowSeconds: 300
          policies:
            - type: Percent
              value: 100
              periodSeconds: 15
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: keda-trigger-auth-aws-credentials
      metadata:
        queueURL: keda-queue
        queueLength: "5"
        awsRegion: "ap-northeast-2"
```

## 적용 순서 (참고)

```sh
kubectl apply -f secret.yaml
kubectl apply -f triggerauthentication.yaml
kubectl apply -f scaledobject.yaml
```
