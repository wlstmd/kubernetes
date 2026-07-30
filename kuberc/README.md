# kubectl kuberc (client-side preferences)

최근 플랫폼 운영팀은 Kubernetes 클러스터를 관리하는 과정에서 반복적인 `kubectl` 명령어 입력과 실수로 인한 리소스 삭제 위험을 줄이고자 합니다. 현재 운영자들은 Pod 목록을 조회할 때마다 전체 명령어를 반복해서 입력하고 있으며, 리소스를 삭제할 때도 별도의 확인 절차 없이 명령어가 즉시 실행되어 운영 리소스를 실수로 삭제할 가능성이 있습니다. 운영팀은 `kubectl` 클라이언트의 사용자 설정 기능을 활용하여 다음과 같이 명령어 사용 방식을 개선하려고 합니다.

- 자주 사용하는 Pod 조회 명령어를 짧은 사용자 정의 명령어로 실행할 수 있어야 합니다.
- 리소스 삭제 명령어를 실행할 때는 사용자가 삭제 여부를 직접 확인하도록 설정해야 합니다.
- 해당 설정은 셸의 단순 Alias가 아닌 `kubectl`에서 제공하는 클라이언트 설정 기능을 사용해야 합니다.
- 설정은 현재 사용자의 홈 디렉터리 아래 Kubernetes 기본 설정 경로에 저장해야 합니다.

### 요구 사항

- 아래 명령어를 실행하면 Pod 목록이 조회되도록 사용자 정의 명령어를 구성할 것

```bash
kubectl ls # 명령어는 kubectl get pods 명령어와 동일하게 동작해야 함
```

- 아래와 같이 리소스 삭제 명령어를 실행하면 실제 삭제 전에 사용자 확인 절차가 표시되도록 구성할 것

```bash
kubectl delete pod nginx
```

- 설정이 특정 터미널 세션에서만 동작하지 않도록 필요한 클라이언트 기능을 영구적으로 활성화할 것
- Kubernetes 클러스터 리소스나 API Server 설정은 변경하지 말 것

### 채점 기준

- 아래 명령어 실행 시 Pod 목록이 정상적으로 조회되는지 여부

```bash
kubectl ls
```

- 아래 명령어 실행 시 리소스가 즉시 삭제되지 않고 사용자 확인 절차가 표시되는지 여부

```bash
kubectl delete pod nginx
```

### Solution

- 아래의 명령어로 활성화 필요

```bash
export KUBECTL_KUBERC=true
```

- `~/.kube/kuberc`경로의 파일 생성

```yaml
apiVersion: kubectl.config.k8s.io/v1alpha1
kind: Preference

overrides:
  - command: delete
    flags:
      - name: interactive
        default: "true"

aliases:
  - name: ls
    command: get
    appendArgs:
      - pods
```
</content>
