# Kafka (Amazon MSK) with EKS

https://migratorydata.com/docs/server/deployment/aws/eks-msk/

- 위 Docs대로 진행해서 문제 없이 되었지만 직접 이미지를 만들어서 나중에 Message주고 받도록 하기

```bash
export EKS_CLUSTER_NAME=skills-eks-cluster
export EKS_SERVICE_ACCOUNT=skills-msk-sa
export EKS_NAMESPACE=skills
export EKS_ROLE_NAME=skills-msk-role
export EKS_SECURITY_GROUP=skills-msk-sg
export KAFKA_TOPIC=server
export IAM_POLICY_NAME=msk-cluster-access-policy
export MSK_CLUSTER_NAME=skills-msk-cluster
export MSK_CONFIGURATION_NAME=skills-msk-config
export VPC_NAME=skills-vpc
export AWS_REGION=ap-northeast-2
```

```bash
cat << EOF > msk-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "kafka-cluster:*",
            "Resource": "*"
        }
    ]
}
EOF
```

```bash
aws iam create-policy --policy-name $IAM_POLICY_NAME --policy-document file://msk-policy.json
```

```bash
POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$IAM_POLICY_NAME'].{ARN:Arn}" --output text)
```

```bash
eksctl create iamserviceaccount \
	--name $EKS_SERVICE_ACCOUNT \
	--namespace $EKS_NAMESPACE \
	--cluster $EKS_CLUSTER_NAME \
	--role-name $EKS_ROLE_NAME \
  --attach-policy-arn $POLICY_ARN \
	--approve
```

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values="$VPC_NAME" --query "Vpcs[].VpcId" --output text)
SUBNET_ID_1=$(aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID --query 'Subnets[?AvailabilityZone==`ap-northeast-2a`&&MapPublicIpOnLaunch==`true`].SubnetId' --output text)
SUBNET_ID_2=$(aws ec2 describe-subnets --filter Name=vpc-id,Values=$VPC_ID --query 'Subnets[?AvailabilityZone==`ap-northeast-2b`&&MapPublicIpOnLaunch==`true`].SubnetId' --output text)
```

```bash
aws ec2 create-security-group --group-name $EKS_SECURITY_GROUP --description "msk security group" --vpc-id $VPC_ID
```

```bash
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filter Name=vpc-id,Values=$VPC_ID Name=group-name,Values=$EKS_SECURITY_GROUP --query 'SecurityGroups[*].[GroupId]' --output text)
```

```bash
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 9098 --cidr 0.0.0.0/0
```

```bash
cat << EOF > configuration.txt
auto.create.topics.enable=true
EOF
```

```bash
MSK_CONFIGURATION_ARN=$(aws kafka create-configuration --name "${MSK_CONFIGURATION_NAME}" --description "Auto create topics enabled" --kafka-versions "3.8.x" --server-properties fileb://configuration.txt --query "Arn" --output text)
```

```bash
cat << EOF > brokernodegroupinfo.json
{
  "InstanceType": "kafka.t3.small",
  "ClientSubnets": [
    "${SUBNET_ID_1}",
    "${SUBNET_ID_2}"
  ],
  "SecurityGroups": [
    "${SECURITY_GROUP_ID}"
  ]
}
EOF
```

```bash
cat << EOF > client-authentication.json
{
  "Sasl": {
    "Iam": {
      "Enabled": true
    }
  }
}
EOF
```

```bash
cat << EOF > configuration.json
{
  "Revision": 1,
  "Arn": "${MSK_CONFIGURATION_ARN}"
}
EOF
```

- 생성하는데 15 ~ 30분정도 소요됨

```bash
aws kafka create-cluster --cluster-name $MSK_CLUSTER_NAME \
	--broker-node-group-info file://brokernodegroupinfo.json \
	--kafka-version "3.8.x" \
	--client-authentication file://client-authentication.json \
	--configuration-info file://configuration.json \
	--number-of-broker-nodes 2
```

```bash
MSK_ARN=$(aws kafka list-clusters --query 'ClusterInfoList[*].ClusterArn' --output text)
KAFKA_BOOTSTRAP_SERVER=$(aws kafka get-bootstrap-brokers --cluster-arn $MSK_ARN --output text)
```

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

```bash
kubectl create namespace $EKS_NAMESPACE
```

```bash
cat << EOF > deploy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: client-properties
  labels:
    name: client-properties
  namespace: skills
data:
  client.properties: |-
    security.protocol=SASL_SSL
    sasl.mechanism=AWS_MSK_IAM
    sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
    sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
---
apiVersion: v1
kind: Service
metadata:
  namespace: skills
  name: skills-cs
  labels:
    app: skills
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
spec:
  type: LoadBalancer
  ports:
    - name: client-port
      port: 80
      protocol: TCP
      targetPort: 8800
  selector:
    app: skills
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: skills
  namespace: skills
  labels:
    app: skills
spec:
  selector:
    matchLabels:
      app: skills
  replicas: 3
  template:
    metadata:
      labels:
        app: skills
    spec:
      serviceAccountName: skills-msk-sa
      containers:
      - name: skills
        imagePullPolicy: Always
        image: migratorydata/server:latest
        volumeMounts:
        - name: client-properties
          mountPath: "/skills/addons/kafka/consumer.properties"
          subPath: client.properties
          readOnly: true
        - name: client-properties
          mountPath: "/skills/addons/kafka/producer.properties"
          subPath: client.properties
          readOnly: true
        env:
          - name: MIGRATORYDATA_EXTRA_OPTS
            value: "-DMemory=512MB -DX.ConnectionOffload=true -DClusterEngine=kafka"
          - name: MIGRATORYDATA_KAFKA_EXTRA_OPTS
            value: "-Dbootstrap.servers=$KAFKA_BOOTSTRAP_SERVER -Dtopics=$KAFKA_TOPIC"
          - name: MIGRATORYDATA_JAVA_GC_LOG_OPTS
            value: "-XX:+PrintCommandLineFlags -XX:+PrintGC -XX:+PrintGCDetails -XX:+DisableExplicitGC -Dsun.rmi.dgc.client.gcInterval=0x7ffffffffffffff0 -Dsun.rmi.dgc.server.gcInterval=0x7ffffffffffffff0 -verbose:gc"
        resources:
          requests:
            memory: "512Mi"
        ports:
          - name: client-port
            containerPort: 8800
        readinessProbe:
          tcpSocket:
            port: 8800
          initialDelaySeconds: 20
          failureThreshold: 5
          periodSeconds: 5
        livenessProbe:
          tcpSocket:
            port: 8800
          initialDelaySeconds: 10
          failureThreshold: 5
          periodSeconds: 5
      volumes:
      - name: client-properties
        configMap:
          name: client-properties
EOF
```

```bash
kubectl apply -f deploy.yaml
```

```bash
kubectl get pods -n skills
```

!image.png
</content>
