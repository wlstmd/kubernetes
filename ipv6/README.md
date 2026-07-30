# IPv6 EKS 클러스터

IPv6 네트워킹으로 EKS 클러스터를 구성한다.

## cluster.yaml

`kubernetesNetworkConfig.ipFamily: IPv6`로 설정한 `skills-eks-cluster` 클러스터 정의. `public_a`/`public_b`/`private_a`/`private_b` 자리에 실제 서브넷 ID를 채운 뒤 `eksctl create cluster -f cluster.yaml`로 생성한다.

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
