# IPv6 EKS 클러스터

IPv6 네트워킹으로 EKS 클러스터를 구성하기 위한 폴더입니다. `bastion.sh`는 현재 빈 파일이며(작성된 명령이 없음), 클러스터 정의는 `cluster.yaml`에 있습니다.

## cluster.yaml

`kubernetesNetworkConfig.ipFamily: IPv6`로 설정된 `skills-eks-cluster` 클러스터 정의입니다. 다른 폴더(예: `Cluster/BottleRocket`, `GatewayAPI`)의 `bastion.sh` 패턴처럼, `public_a`/`public_b`/`private_a`/`private_b` 서브넷 ID 자리를 스크립트로 치환한 뒤 `eksctl create cluster -f cluster.yaml`로 생성하는 흐름이 될 것으로 보입니다(단, 이 폴더에는 해당 치환/생성 스크립트가 아직 없습니다).

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: skills-eks-cluster
  version: "1.31"
    region: ap-northeast-2

cloudWatch:
  clusterLogging:
    enableTypes: ["*"]

kubernetesNetworkConfig:
  ipFamily: IPv6

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest

iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: aws-load-balancer-controller
        namespace: kube-system
      wellKnownPolicies:
        awsLoadBalancerController: true
    - metadata:
        name: cert-manager
        namespace: cert-manager
      wellKnownPolicies:
        certManager: true

vpc:
  subnets:
    public:
      ap-northeast-2a: { id: public_a }
      ap-northeast-2b: { id: public_b }
    private:
      ap-northeast-2a: { id: private_a }
      ap-northeast-2b: { id: private_b }

managedNodeGroups:
  - name: skills-app-nodegroup
    instanceName: skills-app-nodegroup
    instanceType: t3.medium
    desiredCapacity: 2
    minSize: 2
    maxSize: 4
    privateNetworking: true
```

참고: `cluster.yaml`의 `metadata.region` 들여쓰기는 원본 파일에 있는 그대로이며(오타로 보임), 별도로 수정하지 않았습니다.
