# Bottlerocket EKS 클러스터 - 서브넷 설정

`skills-` 접두사로 태그된 VPC 서브넷 ID를 조회해서 `cluster.yaml`의 플레이스홀더 값을 실제 서브넷 ID로 치환한다.

## 서브넷 ID 조회 및 cluster.yaml 값 치환

퍼블릭/프라이빗 서브넷 ID를 조회한 뒤 `sed`로 `cluster.yaml`에 있는 `public_a`, `public_b`, `private_a`, `private_b` 자리에 실제 값을 채워 넣습니다.

```sh
#!/bin/bash
public_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-public-subnet-a" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
public_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-public-subnet-b" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-subnet-a" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-subnet-b" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)


sed -i "s|public_a|$public_a|g" cluster.yaml
sed -i "s|public_b|$public_b|g" cluster.yaml
sed -i "s|private_a|$private_a|g" cluster.yaml
sed -i "s|private_b|$private_b|g" cluster.yaml
```
