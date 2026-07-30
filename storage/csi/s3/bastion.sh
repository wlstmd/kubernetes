export CLUSTER_NAME="skills-eks-cluster"
export AWS_REGION=ap-northeast-2
export CLUSTER_OIDC=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
export ACCOUNT=$(aws sts get-caller-identity --query "Account" --output text)

aws s3 mb s3://skills-s3-csi-driver

cat << EOF > s3-policy.json
{
   "Version": "2012-10-17",
   "Statement": [
        {
            "Sid": "MountpointFullBucketAccess",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::skills-s3-csi-driver"
            ]
        },
        {
            "Sid": "MountpointFullObjectAccess",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::skills-s3-csi-driver/*"
            ]
        }
   ]
}
EOF

aws iam create-policy --policy-name AmazonS3CSIDriverPolicy --policy-document file://s3-policy.json

cat << EOF > aws-s3-csi-driver-trust-policy.json 
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/OIDC"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "OIDC:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

sed -i "s|ACCOUNT_ID|$ACCOUNT|g" aws-s3-csi-driver-trust-policy.json
sed -i "s|OIDC|$CLUSTER_OIDC|g" aws-s3-csi-driver-trust-policy.json

aws iam create-role --role-name AmazonEKS_S3_CSI_DriverRole --assume-role-policy-document file:///home/ec2-user/aws-s3-csi-driver-trust-policy.json

aws iam attach-role-policy --policy-arn arn:aws:iam::362708816803:policy/AmazonS3CSIDriverPolicy --role-name AmazonEKS_S3_CSI_DriverRole

eksctl create addon --name aws-mountpoint-s3-csi-driver --cluster $CLUSTER_NAME --service-account-role-arn arn:aws:iam::$ACCOUNT:role/AmazonEKS_S3_CSI_DriverRole --force

eksctl delete addon --cluster $CLUSTER_NAME --name aws-mountpoint-s3-csi-driver --preserve

kubectl apply -f static_provisioning.yaml

kubectl get pod s3-app

aws s3 ls skills-s3-csi-driver
