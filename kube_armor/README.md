# KubeArmor 런타임 보안 실습

https://github.com/kubearmor/KubeArmor/blob/main/getting-started/deployment_guide.md

KubeArmor는 쿠버네티스 환경 내 컨테이너, 파드, 노드는 물론 가상 머신이나 베어 메탈 머신의 보안 태세를 강화하도록 설계된 클라우드 네이티브 런타임 보안 강화 시스템입니다. 시스템 수준에서 보안 정책을 적용하여 프로세스 실행, 파일 액세스, 네트워킹 작업과 같은 워크로드의 동작을 제한함으로써 보안을 강화합니다.

```yaml
apiVersion: security.kubearmor.com/v1 # KubeArmor API 버전을 지정합니다.
kind: KubeArmorPolicy # KubeArmor 보안 정책 리소스 타입을 지정합니다.
metadata: # 정책의 메타데이터를 정의합니다.
  name: policy-name # 정책의 고유 이름을 지정합니다.
  namespace: target-namespace # 정책이 적용될 네임스페이스를 지정합니다.
  labels: # 정책에 대한 라벨을 설정합니다.
    category: security # 정책 분류를 위한 라벨
  annotations: # 정책에 대한 추가 정보를 제공합니다.
    description: "Block malicious processes"

spec: # 정책의 세부 규칙을 정의합니다.
  tags: # 정책에 태그를 부여합니다.
    - WARNING # 알림 레벨 태그
    - COMPLIANCE # 컴플라이언스 태그

  severity: 5 # 정책 위반 시 심각도 레벨 (1-10)
  message: "Blocked execution" # 정책 위반 시 출력할 사용자 정의 메시지

  selector: # 정책이 적용될 Pod를 선택합니다.
    matchLabels: # 라벨 기반 Pod 선택
      app: nginx # app=nginx 라벨을 가진 Pod에 적용
    matchExpressions: # 표현식 기반 Pod 선택
      - key: environment
        operator: In
        values: ["prod", "staging"]

  file: # 파일 시스템 접근 제어 규칙을 정의합니다.
    matchPaths: # 특정 파일 경로를 지정합니다.
      - path: /etc/passwd # 정확한 파일 경로
        readOnly: true # 읽기 전용 설정 (선택사항)
      - path: /etc/shadow
        ownerOnly: true # 소유자만 접근 가능 (선택사항)

    matchDirectories: # 디렉토리 접근 제어를 정의합니다.
      - dir: /etc/ # 디렉토리 경로
        recursive: true # 하위 디렉토리까지 재귀적으로 적용
        readOnly: false # 읽기/쓰기 권한 설정
      - dir: /tmp/
        recursive: false # 해당 디렉토리만 적용 (하위 제외)

    matchPatterns: # 패턴 매칭으로 파일을 지정합니다.
      - pattern: "*.conf" # 확장자 기반 패턴
      - pattern: "/var/log/*" # 경로 패턴

  process: # 프로세스 실행 제어 규칙을 정의합니다.
    matchPaths: # 특정 실행 파일 경로를 지정합니다.
      - path: /usr/bin/wget # 정확한 실행 파일 경로
      - path: /bin/sh # 쉘 실행 파일
        ownerOnly: true # 소유자만 실행 가능

    matchDirectories: # 디렉토리 내 모든 실행 파일을 제어합니다.
      - dir: /usr/bin/ # 디렉토리 경로
        recursive: true # 하위 디렉토리 포함
      - dir: /sbin/
        recursive: false # 해당 디렉토리만

    matchPatterns: # 패턴으로 실행 파일을 지정합니다.
      - pattern: "*sh" # 패턴 매칭 (bash, zsh, etc.)

  network: # 네트워크 접근 제어 규칙을 정의합니다.
    matchProtocols: # 프로토콜 기반 제어
      - protocol: tcp # TCP 프로토콜
        ports: # 포트 범위
          - "80" # 특정 포트
          - "443"
      - protocol: udp # UDP 프로토콜
        ports:
          - "53" # DNS 포트

  capabilities: # 리눅스 Capability 제어
    matchCapabilities: # 특정 capability 제어
      - capability: NET_RAW # Raw socket 권한
      - capability: SYS_ADMIN # 시스템 관리 권한

  syscalls: # 시스템 콜 레벨 제어
    matchSyscalls: # 특정 시스템 콜 제어
      - syscall: # 시스템 콜 목록
          - execve # 프로그램 실행
          - open # 파일 열기
          - connect # 네트워크 연결
      - syscall:
          - mount # 파일시스템 마운트
          - umount # 파일시스템 언마운트
        fromSource: # 특정 소스에서만 적용
          - path: /usr/bin/mount

  action: # 정책 위반 시 수행할 액션을 지정합니다.
    Block # 차단 (기본값)
    # Audit                       # 감사 (로그만 기록, 허용)
    # Allow                       # 허용 (화이트리스트 모드)

  nodeSelector: # 특정 노드에만 정책 적용 (선택사항)
    matchLabels:
      node-type: worker
```

> Example Code

```yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: comprehensive-security-policy
  namespace: production
spec:
  tags: ["CRITICAL", "COMPLIANCE"]
  severity: 8
  message: "Security violation detected"
  selector:
    matchLabels:
      tier: frontend
  file:
    matchDirectories:
      - dir: /etc/
        recursive: true
        readOnly: true # /etc 디렉토리는 읽기만 허용
  process:
    matchPaths:
      - path: /bin/bash # bash 실행 차단
      - path: /usr/bin/wget # wget 다운로드 차단
  network:
    matchProtocols:
      - protocol: tcp
        ports: ["22"] # SSH 포트 차단
  action: Block
```

### 실습

```bash
curl -sfL http://get.kubearmor.io/ | sudo sh -s -- -b /usr/local/bin

karmor install
```

> `app: green` 라벨을 가진 Pod에서 `/bin/sleep` 실행을 차단

```yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: ksp-group-1-proc-path-block
  namespace: green
spec:
  severity: 5
  message: "block /bin/sleep"
  selector:
    matchLabels:
      app: green
  process:
    matchPaths:
      - path: /bin/sleep
  action: Block
```

```bash
kubectl apply -f kubearmor.yaml
```

- `/bin/sleep` 차단이 성공적으로 차단된 모습 확인 가능

!image.png

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: green-app
  namespace: green
spec:
  replicas: 1
  selector:
    matchLabels:
      app: green
  template:
    metadata:
      labels:
        app: green
    spec:
      containers:
        - name: green-container
          image: busybox
          command:
            - "sh"
            - "-c"
            - "echo 'Starting /bin/sleep'; /bin/sleep 3600"
          resources:
            limits:
              memory: "64Mi"
              cpu: "250m"
```

```bash
kubectl apply -f deployment.yaml
```

- KubeArmor가 해당 Pod들의 **실행 프로세스, 파일 접근 패턴, 네트워크 사용**을 **실시간으로 분석**
- 분석 결과를 바탕으로 **적절한 KubeArmorPolicy YAML**을 자동 생성

```bash
karmor recommend -n green # green 네임스페이스 안에 있는 Pod들을 대상
```

> `/account/` 디렉터리에 대한 접근 제한

```yaml
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: ksp-group-1-proc-path-block
  namespace: green
spec:
  severity: 5
  message: "a critical directory was accessed"
  selector:
    matchLabels:
      app: green
  file:
    matchDirectories:
      - dir: /account/
        fromSource:
          - path: /bin/cat
  action: Block
```

- `/bin/cat`으로 읽으면 성공적으로 차단된 모습 확인 가능

!image.png

- vi 명령어로는 차단되지 않고 열리는 모습 확인 가능

!image.png

### Nginx로 Test

```bash
kubectl create deployment nginx --image=nginx -n green
POD=$(kubectl get pod -l app=nginx -n green -o name)
echo $POD
```

> Process 실행 차단 정책

```bash
cat <<EOF | kubectl apply -f -
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: block-pkg-mgmt-tools-exec
  namespace: green
spec:
  selector:
    matchLabels:
      app: nginx
  process:
    matchPaths:
    - path: /usr/bin/apt
    - path: /usr/bin/apt-get
  action:
    Block
EOF
```

```bash
kubectl exec -it $POD -n green -- bash -c "apt update && apt install masscan"
```

- `apt 명령어`가 성공적으로 차단된 모습 확인 가능

!image.png

> 서비스 계정 토큰 접근 차단 정책

```bash
cat <<EOF | kubectl apply -f -
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: block-service-access-token-access
  namespace: green
spec:
  selector:
    matchLabels:
      app: nginx
  file:
    matchDirectories:
    - dir: /run/secrets/kubernetes.io/serviceaccount/
      recursive: true
  action:
    Block
EOF
```

```bash
kubectl exec -it $POD -n green -- bash -c "cat /run/secrets/kubernetes.io/serviceaccount/token"
```

- 서비스 계정 토큰 접근 차단이 성공적으로 된 모습 확인 가능

!image.png

> 감사 정책 (Audit)

- 네임스페이스에 가시성 활성화

```bash
kubectl annotate ns green kubearmor-visibility="process,file,network" --overwrite
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: audit-etc-nginx-access
  namespace: green
spec:
  selector:
    matchLabels:
      app: nginx
  file:
    matchDirectories:
    - dir: /etc/nginx/
      recursive: true
  action:
    Audit
EOF
```

```bash
kubectl exec -it $POD -n green -- bash -c "cat /etc/nginx/nginx.conf"
kubectl exec -it $POD -n green -- bash -c "ls -la /etc/nginx/"
kubectl exec -it $POD -n green -- bash -c "cat /etc/nginx/conf.d/default.conf"
```

- 감사 로그가 성공적으로 남은 모습

!image.png

> 최소 권한 정책 (Allow 기반) 화이트리스트

- 보안상태를 모두 거부하는 정책으로 적용

```bash
kubectl annotate ns green kubearmor-file-posture=block --overwrite
```

```bash
cat <<EOF | kubectl apply -f -
apiVersion: security.kubearmor.com/v1
kind: KubeArmorPolicy
metadata:
  name: only-allow-nginx-exec
  namespace: green
spec:
  selector:
    matchLabels:
      app: nginx
  file:
    matchDirectories:
    - dir: /
      recursive: true
  process:
    matchPaths:
    - path: /usr/sbin/nginx
    - path: /bin/bash
  action:
    Allow
EOF
```

```bash
# ✅ 허용됨 - 쉘 접근
kubectl exec -it $POD -n green -- bash

# ❌ 차단됨 - 다른 모든 명령어
kubectl exec -it $POD -n green -- ls        # Permission denied
kubectl exec -it $POD -n green -- cat       # Permission denied
kubectl exec -it $POD -n green -- whoami    # Permission denied
kubectl exec -it $POD -n green -- ps        # Permission denied
```

- bash 명령어 말고는 성공적으로 모두 차단된 모습 확인 가능

!image.png

!image.png
</content>
