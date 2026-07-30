# kube-proxy IPVS 모드 전환

## 사전 준비 및 Worker Node 접속

```sh
EKS_CLUSTER_NAME=skills-eks-cluster

sudo yum install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm

aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=skills-app-nodegroup" --query "Reservations[*].Instances[*].InstanceId" --output text

aws ssm start-session --target <instance-id>
```

## Worker Node 접속 확인 (ipvsadm, lsmod)

```sh
sudo ipvsadm -L

sudo lsmod | egrep -i "ip_vs|ip_vs_rr|ip_vs_wrr|ip_vs_sh|nf_conntrack"
```

## kube-proxy addon을 IPVS 모드로 변경

```sh
aws eks list-addons --cluster-name $EKS_CLUSTER_NAME | grep proxy

aws eks update-addon --cluster-name $EKS_CLUSTER_NAME --addon-name kube-proxy \
    --addon-version v1.31.2-eksbuild.3\
    --configuration-values '{"ipvs": {"scheduler": "rr"}, "mode": "ipvs"}' \
    --resolve-conflicts OVERWRITE

kubectl get cm kube-proxy-config -n kube-system -o yaml > kube-proxy-config-old.yml

kubectl edit cm kube-proxy-config -n kube-system
```

## Nodegroup 확인

```sh
eksctl get nodegroup --cluster=$EKS_CLUSTER_NAME
```

## scale-in

```sh
eksctl scale nodegroup --cluster=$EKS_CLUSTER_NAME --nodes=0 --name=skills-app-nodegroup --nodes-min=0 --nodes-max=4 --wait
```

## scale-out

```sh
eksctl scale nodegroup --cluster=$EKS_CLUSTER_NAME --nodes=2 --name=skills-app-nodegroup --nodes-min=2 --nodes-max=4 --wait
```

## 재확인

```sh
sudo ipvsadm -L
```
