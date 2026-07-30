# OPA Gatekeeper 설치 및 구성

OPA Gatekeeper를 EKS 클러스터에 설치하고, ConstraintTemplate/Constraint를 이용해 Container Image, Privileged Container, ECR Repository 사용을 제한하는 정책 실습 스크립트(`bastion.sh`) 정리.

## Ready

### ENV
```sh
REGION_CODE=$(aws configure get default.region --output text)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

### OPA Gatekeeper Install
```sh
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml
kubectl get pods -n gatekeeper-system
```

### audit-controller log 확인
```sh
kubectl logs -l control-plane=audit-controller -n gatekeeper-system
```

### gatekeeper-system log 확인
```sh
kubectl logs -l control-plane=controller-manager -n gatekeeper-system
```

## Container Image 제한하기

### ConstraintTemplate
```sh
kubectl apply -f constraint-template-image.yaml 
```

### Constraint
```sh
kubectl apply -f constraint-image.yaml
kubectl get constrainttemplate
kubectl get constraint
```

### constraintTemplate 상세 내용 확인
```sh
kubectl get constrainttemplate -o yaml enforceimagelist
```

### constraint 의 상세 내용을 확인
```sh
kubectl get constraint -o yaml k8senforceallowlistedimages
```

### OPA 정책에 위반된 Pod를 배포
```sh
kubectl apply -f pod-with-invalid-image.yaml
# > Error from server (Forbidden): error when creating "/home/ec2-user/environment/opa/pod-with-invalid-image.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [k8senforceallowlistedimages] pod "invalid-image" has invalid image "docker:latest". Please, contact Security Team. Follow the allowlisted images {"300861432382.dkr.ecr.ap-northeast-2.amazonaws.com/eks-security-shared", "amazon/aws-alb-ingress-controller", "amazon/aws-cli", "amazon/aws-efs-csi-driver", "amazon/aws-node-termination-handler", "amazon/cloudwatch-agent", "busybox", "docker.io/amazon/aws-alb-ingress-controller", "falco", "grafana/grafana", "nginx", "openpolicyagent/gatekeeper", "prom/alertmanager", "prom/prometheus"}
```

### OPA 정책에 위반 되지 않은 Pod를 배포
```sh
kubectl apply -f pod-with-valid-image.yaml
```

### Container Image 사용제한 정책 삭제
```sh
kubectl delete -f pod-with-valid-image.yaml
kubectl delete -f constraint-image.yaml
kubectl delete -f constraint-template-image.yaml 
```

## Privilege Container 사용 제한하기

### constraintTemplate
```sh
kubectl apply -f constraint-template-privileged.yaml
```

### constraint
```sh
kubectl apply -f constraint-privileged.yaml
```

### constraintTemplate 상세 내용 확인
```sh
kubectl get constrainttemplate -o yaml enforceprivilegecontainer
```

### constraint 의 상세 내용을 확인
```sh
kubectl get constraint -o yaml privileged-container-security
```

### 허용되지 않은 Privileged를 사용한 Pod 배포 (Error)
```sh
kubectl apply -f privileged-container.yaml
```

### "privileged:" 값이 "false" 로 처리되어 있는 Pod를 배포 (Success)
```sh
kubectl apply -f privileged-container.yaml
```

### Container Image 사용제한 정책 삭제
```sh
kubectl delete -f privileged-container.yaml
kubectl delete -f constraint-privileged.yaml
kubectl delete -f constraint-template-privileged.yaml
```

## Repository 사용 제한하기

### nginx image 를 다운로드한 후 이전 과정에서 생성환 "eks-security-shared" Repository에 업로드할 수 있도록 Tag를 부여
```sh
docker pull public.ecr.aws/docker/library/nginx
docker tag public.ecr.aws/docker/library/nginx $AWS_ACCOUNT_ID.dkr.ecr.$REGION_CODE.amazonaws.com/eks-security-shared
aws ecr get-login-password --region $REGION_CODE | \
docker login --username AWS --password-stdin \
$AWS_ACCOUNT_ID.dkr.ecr.$REGION_CODE.amazonaws.com
docker push $AWS_ACCOUNT_ID.dkr.ecr.$REGION_CODE.amazonaws.com/eks-security-shared
```

### constraintTemplate
```sh
kubectl apply -f constraint-template-repository.yaml
```

### constraint
```sh
kubectl apply -f constraint-repository.yaml
```

### Check
```sh
kubectl get constrainttemplate
kubectl get constraint
```

### Repository 사용 제한 확인: 등록되지 않은 Repository 를 이용한 Pod 배포 (Error)
```sh
kubectl apply -f disallowed-repository.yaml
```

### 등록된 ECR Repository 를 사용하도록 하는 Pod를 배포 (Success)
```sh
kubectl apply -f allowed-repository.yaml
```

### Repository 사용제한 정책 삭제
```sh
kubectl delete -f allowed-repository.yaml
kubectl delete -f constraint-repository.yaml
kubectl delete -f constraint-template-repository.yaml
```
