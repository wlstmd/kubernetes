export CLUSTER_NAME=skills-eks-cluster
export REGION_CODE=ap-northeast-2
export NODE_GROUP_NAME=skills-app-nodegroup

eksctl create iamserviceaccount \
    --name file-cache-csi-controller-sa \
    --namespace kube-system \
    --cluster $CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonFSxFullAccess \
    --approve \
    --role-name AmazonEKSFileCacheCSIDriverFullAccess \
    --region $REGION_CODE

cat << EOF > file-cache-csi-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ds:DescribeDirectories",
                "fsx:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "iam:CreateServiceLinkedRole",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": [
                        "fsx.amazonaws.com"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "iam:CreateServiceLinkedRole",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "iam:AWSServiceName": [
                        "s3.data-source.lustre.fsx.amazonaws.com"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:*:*:log-group:/aws/fsx/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "firehose:PutRecord"
            ],
            "Resource": [
                "arn:aws:firehose:*:*:deliverystream/aws-fsx-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:route-table/*"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:RequestTag/AmazonFSx": "ManagedByAmazonFSx"
                },
                "ForAnyValue:StringEquals": {
                    "aws:CalledVia": [
                        "fsx.amazonaws.com"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcs"
            ],
            "Resource": "*",
            "Condition": {
                "ForAnyValue:StringEquals": {
                    "aws:CalledVia": [
                        "fsx.amazonaws.com"
                    ]
                }
            }
        }
    ]
}
EOF

aws iam create-policy --policy-name FileCacheCSIPolicy --policy-document file://file-cache-csi-policy.json

NODEGROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $NODE_GROUP_NAME --query "nodegroup.nodeRole" --output text | cut -d'/' -f2-)

aws iam attach-role-policy --role-name $NODEGROUP_ROLE_NAME --policy-arn arn:aws:iam::362708816803:policy/FileCacheCSIPolicy

kubectl annotate serviceaccount file-cache-csi-controller-sa -n kube-system meta.helm.sh/release-name=aws-file-cache-csi-driver --overwrite
kubectl annotate serviceaccount file-cache-csi-controller-sa -n kube-system meta.helm.sh/release-namespace=kube-system --overwrite
kubectl label serviceaccount file-cache-csi-controller-sa -n kube-system app.kubernetes.io/managed-by=Helm --overwrite

helm repo add aws-file-cache-csi-driver https://kubernetes-sigs.github.io/aws-file-cache-csi-driver/
helm repo update
helm install aws-file-cache-csi-driver aws-file-cache-csi-driver/aws-file-cache-csi-driver \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=file-cache-csi-controller-sa

# Security Group 규칙 변경
export CLUSTER_SG=$(aws eks describe-cluster --name $CLUSTER_NAME --query cluster.resourcesVpcConfig.clusterSecurityGroupId --output text)

aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --protocol tcp --port 988 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-egress --group-id $CLUSTER_SG --protocol tcp --port 988 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --protocol tcp --port 1018-1023  --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-egress --group-id $CLUSTER_SG --protocol tcp --port 1018-1023  --cidr 0.0.0.0/0 > /dev/null

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-file-cache-csi-driver/main/examples/kubernetes/dynamic_provisioning/specs/storageclass.yaml

kubectl apply -f storageclass.yaml

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-file-cache-csi-driver/main/examples/kubernetes/dynamic_provisioning/specs/claim.yaml
kubectl apply -f claim.yaml
kubectl describe pvc

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-file-cache-csi-driver/main/examples/kubernetes/dynamic_provisioning/specs/pod.yaml

kubectl exec -ti fc-app -- df -h

kubectl exec -it fc-app -- ls /data

