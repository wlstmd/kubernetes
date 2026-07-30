# Fargate 로그 라우터 (Log Router) 설정

## 환경 변수 설정

```sh
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
EKS_NODE_GROUP_NAME="<NODE_GROUP_NAME>"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
REGION_CODE=$(aws configure get default.region --output text)
```

## Namespace

```sh
kubectl apply -f aws-observability-namespace.yaml
```

## OIDC

```sh
eksctl utils associate-iam-oidc-provider --region=$REGION_CODE --cluster=$EKS_CLUSTER_NAME --approve
```

## IAM Role Attach Policy

```sh
curl -o permissions.json https://raw.githubusercontent.com/aws-samples/amazon-eks-fluent-logging-examples/mainline/examples/fargate/cloudwatchlogs/permissions.json
FARGATE_POLICY_ARN=$(aws --region "$REGION_CODE" --query Policy.Arn --output text iam create-policy --policy-name fargate-policy --policy-document file://permissions.json)
FARGATE_ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-$EKS_CLUSTER_NAME-c-FargatePodExecutionRole')].RoleName" --output text)
NODE_GROUP=$(aws iam get-role --role-name $FARGATE_ROLE_NAME --query "Role.RoleName" --output text)
NODE_GROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query 'nodegroup.nodeRole' --output text | awk -F/ '{print $NF}')
```

## eksctl list roles check

```sh
aws iam list-roles | grep 'eksctl-'

aws iam attach-role-policy --policy-arn $FARGATE_POLICY_ARN --role-name $NODE_GROUP
aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess --role-name $NODE_GROUP_ROLE_NAME
```

## ConfigMap

```sh
kubectl apply -f aws-logging-cloudwatch-configmap.yaml
```

## Add Log & Check Log

```sh
kubectl exec -it -n skills deployment.apps/skills-app-deployment -- curl localhost:8080/healthcheck > /dev/null 2>&1
kubectl logs -n skills deployment.apps/skills-app-deployment -c skills-app
```

## Fargate Log Router 생성과정

- ConfigMap을 생성하고 나면 Fargate의 Amazon EKS가 자동으로 감지하고 로그 라우터를 구성
  - aws-observability로 이름이 지정된 전용 Kubernetes 네임스페이스를 생성
  - name의 값은 aws-observability여야 하며 aws-observability: enabled 레이블이 필요

```yaml
kind: Namespace
apiVersion: v1
metadata:
name: aws-observability
labels:
aws-observability: enabled
```

## Fargate 로그 라우터 구성

Fluent Conf는 Fluent Bit의 구성 파일입니다. 이는 컨테이너 로그를 원하는 로그 대상으로 라우팅하는 데 사용되는 빠르고 가벼운 로그 프로세서 구성 언어입니다. 자세한 내용은 Fluent Bit 설명서의 구성 파일을 참조하세요.

### 중요 사항

일반적인 Fluent Conf에 포함된 주요 단원은 `Service`, `Input`, `Filter`, `Output`입니다. 하지만 Fargate 로그 라우터는 다음 부분만 수락합니다:

- `Filter` 및 `Output` 부분
- `Parser` 부분

기타 부분을 제공하는 경우 해당 부분은 거부됩니다.

Fargate 로그 라우터에서는 `Service` 및 `Input` 부분을 관리합니다. 여기에는 수정할 수 없고 ConfigMap에서 필요하지 않은 다음과 같은 `Input` 부분이 있습니다. 그러나 메모리 버퍼 제한과 로그에 적용된 태그와 같은 인사이트를 얻을 수 있습니다.

```yaml
[INPUT]
    Name tail
    Buffer_Max_Size 66KB
    DB /var/log/flb_kube.db
    Mem_Buf_Limit 45MB
    Path /var/log/containers/*.log
    Read_From_Head On
    Refresh_Interval 10
    Rotate_Wait 30
    Skip_Long_Lines On
    Tag kube.*
```

## ConfigMap을 생성할 때 Fargate가 필드를 검증하는 규칙

### 구성 파일 섹션

- `[FILTER]`, `[OUTPUT]`, `[PARSER]`는 각 해당 키 아래에 지정되어야 합니다.
  - 예: `filters.conf`에는 `[FILTER]` 섹션이 있어야 합니다.
  - 여러 개의 `[OUTPUT]` 섹션을 지정하여 로그를 여러 대상으로 동시에 라우팅할 수 있습니다.

### 필수 키

- `[FILTER]`에는 `Name` 및 `match` 키가 필요합니다.
- `[OUTPUT]`에는 `Name` 및 `match` 키가 필요합니다.
- `[PARSER]`에는 `Name` 및 `format` 키가 필요합니다.
- 태그는 대/소문자를 구분합니다.

### 환경 변수

- `${ENV_VAR}`와 같은 환경 변수는 ConfigMap에서 허용되지 않습니다.

### 들여쓰기

- 각 `filters.conf`, `output.conf`, `parsers.conf` 내의 지시문 또는 키 값 페어에 대해 동일한 들여쓰기를 사용해야 합니다.
- 키 값 페어는 지시문보다 들여 써야 합니다.

### 지원 필터

- Fargate는 `grep`, `parser`, `record_modifier`, `rewrite_tag`, `throttle`, `nest`, `modify`, `kubernetes` 등의 필터를 검증합니다.

### 지원 출력

- Fargate는 `es`, `firehose`, `kinesis_firehose`, `cloudwatch`, `cloudwatch_logs`, `kinesis` 등의 출력을 검증합니다.

### 로깅 사용 설정

- ConfigMap에서 지원되는 Output 플러그 인이 1개 이상 제공되어야 합니다.
- Filter 및 Parser는 로깅을 사용 설정하는 데 필수는 아닙니다.

### Kubernetes 필터 지원

이 기능을 사용하려면 다음과 같은 최소 Kubernetes 버전 및 플랫폼 수준 이상이 필요합니다.

| Kubernetes 버전 | 플랫폼 수준 |
| --------------- | ----------- |
| 1.23 이상       | eks.1       |

Fluent Bit Kubernetes 필터를 사용하면 로그 파일에 Kubernetes 메타데이터를 추가할 수 있습니다. 필터에 대한 자세한 내용은 Fluent Bit 설명서의 Kubernetes를 참조하세요. API 서버 엔드포인트를 사용하여 필터를 적용할 수 있습니다.

```yaml
filters.conf: |
  [FILTER]
      Name             kubernetes
      Match            kube.*
      Merge_Log        On
      Buffer_Size      0
      Kube_Meta_Cache_TTL 300s
```

| 중요: Kube_URL, Kube_CA_File, Kube_Token_Command 및 Kube_Token_File은 서비스 소유 구성 파라미터이므로 지정하면 안 됩니다. Amazon EKS Fargate가 이러한 값을 채웁니다.

| Kube_Meta_Cache_TTL은 Fluent Bit가 최신 메타데이터에 대해 API 서버와 통신할 때까지 대기하는 시간입니다. Kube_Meta_Cache_TTL을 지정하지 않으면 Amazon EKS Fargate는 API 서버의 로드를 줄이기 위해 기본값 30분을 추가합니다.

### 계정에 Fluent Bit 프로세스 로그 전송

다음 ConfigMap을 사용하여 Fluent Bit 프로세스 로그를 Amazon CloudWatch로 선택적으로 전송할 수 있습니다. Fluent Bit 프로세스 로그를 CloudWatch로 전송하려면 추가 로그 수집 및 스토리지 비용이 필요합니다. region-code를 클러스터가 있는 AWS 리전으로 바꿉니다.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: aws-logging
  namespace: aws-observability
  labels:
data:
  # Configuration files: server, input, filters and output
  # ======================================================
  flb_log_cw: "true" # Ships Fluent Bit process logs to CloudWatch.

  output.conf: |
    [OUTPUT]
        Name cloudwatch
        Match kube.*
        region region-code
        log_group_name fluent-bit-cloudwatch
        log_stream_prefix from-fluent-bit-
        auto_create_group true

  parsers.conf: |
    [PARSER]
        Name crio
        Format Regex
        Regex ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>P|F) (?<log>.*)$
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
```

로그는 CloudWatch 아래에 클러스터가 있는 AWS 리전에 있습니다.

| 참고: 프로세스 로그는 Fluent Bit 프로세스가 성공적으로 시작된 경우에만 전송됩니다. Fluent Bit를 시작하는 동안 오류가 발생하면 프로세스 로그가 누락됩니다. CloudWatch에는 프로세스 로그만 전송할 수 있습니다.

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: aws-logging
  namespace: aws-observability
  labels:
data:
  # Configuration files: server, input, filters and output
  # ======================================================
  flb_log_cw: "true" # Ships Fluent Bit process logs to CloudWatch. <--

  output.conf: |
    [OUTPUT]
        Name cloudwatch
        Match kube.*
        region region-code
        log_group_name fluent-bit-cloudwatch
        log_stream_prefix from-fluent-bit-
        auto_create_group true
```

계정으로 프로세스 로그 전송을 디버깅하려면 위 ConfigMap을 적용하여 프로세스 로그를 가져올 수 있습니다. Fluent Bit가 시작하지 못하는 것은 대개 시작하는 동안 Fluent Bit에 의해 구문 분석 또는 수락되지 않은 ConfigMap 때문입니다.

### Fluent Bit 프로세스 로그 전송을 중지하려면

| Fluent Bit 프로세스 로그를 CloudWatch로 전송하려면 추가 로그 수집 및 스토리지 비용이 필요합니다. 기존 ConfigMap 설정에서 프로세스 로그를 제외하려면 다음 단계를 수행하세요.

- Fargate 로깅을 활성화한 후 Amazon EKS 클러스터의 Fluent Bit 프로세스 로그에 대해 자동으로 생성된 CloudWatch 로그 그룹을 찾습니다. 형식 {cluster_name}-fluent-bit-logs을 따릅니다.
- CloudWatch 로그 그룹에서 각 Pod의 프로세스 로그에 대해 생성된 기존 CloudWatch 로그 스트림을 삭제합니다.
- ConfigMap을 편집하고 flb_log_cw: "false"를 설정합니다.
- 클러스터의 기존 Pods를 다시 시작합니다.
