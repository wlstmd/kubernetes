# CloudWatch Agent + Fluent Bit (Container Insights Quickstart) 설치

## ENV

```sh
EKS_CLUSTER_NAME="skills-eks-cluster"
REGION_CODE="<REGION>"
FluentBitHttpServer='On'
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
FluentBitReadFromTail='On'
```

## Install CloudWatch Agent

```sh
wget https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml
sed -i 's/{{cluster_name}}/'${EKS_CLUSTER_NAME}'/;s/{{region_name}}/'${REGION_CODE}'/;s/{{http_server_toggle}}/'${FluentBitHttpServer}'/;s/{{http_server_port}}/'${FluentBitHttpPort}'/;s/{{read_from_head}}/'${FluentBitReadFromHead}'/;s/{{read_from_tail}}/'${FluentBitReadFromTail}'/' cwagent-fluent-bit-quickstart.yaml
# 환경변수 체크해주기
kubectl apply -f cwagent-fluent-bit-quickstart.yaml
```

## Check

```sh
kubectl get ds,pod,cm,sa -n amazon-cloudwatch
kubectl describe clusterrole cloudwatch-agent-role fluent-bit-role # 클러스터롤 확인
kubectl describe clusterrolebindings cloudwatch-agent-role-binding fluent-bit-role-binding  # 클러스터롤 바인딩 확인
kubectl -n amazon-cloudwatch logs -l name=cloudwatch-agent -f # 파드 로그 확인
kubectl -n amazon-cloudwatch logs -l k8s-app=fluent-bit -f    # 파드 로그 확인
```

## cloudwatch-agent 설정 확인 (아래의 JSON을 참고)

```sh
kubectl describe cm cwagentconfig -n amazon-cloudwatch
```

```json
{
  "agent": {
    "region": "ap-northeast-2"
  },
  "logs": {
    "metrics_collected": {
      "kubernetes": {
        "cluster_name": "myeks",
        "metrics_collection_interval": 60
      }
    },
    "force_flush_interval": 5
  }
}
```

## DaemonSet 확인

```sh
kubectl describe -n amazon-cloudwatch ds cloudwatch-agent 
```

## Fluent Bit Cluster Info 확인

```sh
kubectl get cm -n amazon-cloudwatch fluent-bit-cluster-info -o yaml | yh
```

## Fluent Bit 설정 확인

```sh
kubectl describe cm fluent-bit-config -n amazon-cloudwatch 
```

## Add Log & Check Log

```sh
kubectl exec -it -n skills deployment.apps/skills-app-deployment -- curl localhost:8080/healthcheck > /dev/null 2>&1
kubectl logs -n skills deployment.apps/skills-app-deployment -c skills-app
```
