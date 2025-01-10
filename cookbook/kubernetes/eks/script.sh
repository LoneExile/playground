#!/bin/bash

export AWS_PROFILE=apinant
REGION=ap-southeast-1

aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=eks-vpc}]' --output json | jq

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-vpc" --query "Vpcs[0].VpcId" --output text)

# Create public subnets
aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone "$REGION"a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-public-subnet-1},{Key=kubernetes.io/role/elb,Value=1}]' \
  --output json | jq

aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone "$REGION"b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-public-subnet-2},{Key=kubernetes.io/role/elb,Value=1}]' \
  --output json | jq

# Create private subnets
aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.3.0/24 \
  --availability-zone "$REGION"a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-private-subnet-1},{Key=kubernetes.io/role/internal-elb,Value=1}]' \
  --output json | jq

aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.4.0/24 \
  --availability-zone "$REGION"b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=eks-private-subnet-2},{Key=kubernetes.io/role/internal-elb,Value=1}]' \
  --output json | jq

# Store subnet IDs in variables
PUBLIC_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=eks-public-subnet-1" --query 'Subnets[0].SubnetId' --output text)
PUBLIC_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=eks-public-subnet-2" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=eks-private-subnet-1" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=eks-private-subnet-2" --query 'Subnets[0].SubnetId' --output text)

aws ec2 create-security-group \
  --group-name eks-cluster-sg \
  --description "Security group for EKS cluster" \
  --vpc-id "$VPC_ID" \
  --output json | jq

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=eks-cluster-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)


# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

# Create EKS cluster role with specific account permissions
aws iam create-role \
  --role-name eks-cluster-role \
  --output json \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "eks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' \
  --output json |jq

# Add inline policy to allow EKS to use the role
aws iam put-role-policy \
  --role-name eks-cluster-role \
  --policy-name eks-cluster-role-policy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "eks:*"
        ],
        "Resource": "*"
      }
    ]
  }' \
  --output json |jq

ROLE_ARN=$(aws iam get-role --role-name eks-cluster-role --query "Role.Arn" --output text)


# Attach required policies to cluster role
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
  --role-name eks-cluster-role


# Create EKS cluster with correct kubernetes version
aws eks create-cluster \
  --name my-eks-cluster \
  --role-arn "$ROLE_ARN" \
  --resources-vpc-config "subnetIds=$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2,$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2,securityGroupIds=$SECURITY_GROUP_ID" \
  --kubernetes-version 1.31 \
  --region "$REGION" \
  --output json | jq

# Wait for cluster to be created (this may take 15-20 minutes)
echo "Waiting for EKS cluster to be created..."
aws eks wait cluster-active \
  --name my-eks-cluster \
  --region "$REGION" \
  --output json | jq
echo "EKS cluster created successfully!"

aws iam create-role \
  --role-name eks-node-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }' \
  --output json | jq

# Attach required policies
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
  --role-name eks-node-role \
  --output json | jq

aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
  --role-name eks-node-role \
  --output json | jq

aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
  --role-name eks-node-role \
  --output json | jq

# Create IAM instance profile for the node role
aws iam create-instance-profile \
  --instance-profile-name eks-node-role \
  --output json | jq

# Add the role to the instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name eks-node-role \
  --role-name eks-node-role

# Wait for the instance profile to be ready
echo "Waiting for instance profile to propagate..."
sleep 10

# aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --region

AMI_ID=$(aws ssm get-parameters --names /aws/service/bottlerocket/aws-k8s-1.29/x86_64/latest/image_id --region "$REGION" --query "Parameters[0].Value" --output text)
NODE_INSTANCE_TYPE="t3.medium"
KEY_PAIR_NAME="your-key-pair"

aws ec2 create-key-pair \
    --key-name "$KEY_PAIR_NAME" \
    --query 'KeyMaterial' \
    --output text > "$KEY_PAIR_NAME".pem

# Get cluster information
CLUSTER_ENDPOINT=$(aws eks describe-cluster --name my-eks-cluster --query "cluster.endpoint" --output text)
CLUSTER_CA=$(aws eks describe-cluster --name my-eks-cluster --query "cluster.certificateAuthority.data" --output text)
CLUSTER_DNS=$(aws eks describe-cluster --name my-eks-cluster --query "cluster.kubernetesNetworkConfig.serviceIpv4Cidr" --output text)
CLUSTER_DNS_IP=$(echo "$CLUSTER_DNS" | awk -F'.' '{print $1"."$2"."$3".10"}')

# Create UserData script
USERDATA=$(cat <<EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -ex

/etc/eks/bootstrap.sh my-eks-cluster \
  --apiserver-endpoint '$CLUSTER_ENDPOINT' \
  --b64-cluster-ca '$CLUSTER_CA' \
  --dns-cluster-ip '$CLUSTER_DNS_IP' \
  --container-runtime containerd \
  --kubelet-extra-args '--max-pods=17' \
  --use-max-pods false

--==MYBOUNDARY==--
EOF
)

# Base64 encode the UserData
USERDATA_BASE64=$(echo "$USERDATA" | base64 -w 0)

# Create launch template with the proper UserData
aws ec2 create-launch-template \
  --launch-template-name eks-node-template \
  --version-description v1 \
  --launch-template-data '{
    "InstanceType": "'"$NODE_INSTANCE_TYPE"'",
    "ImageId": "'"$AMI_ID"'",
    "KeyName": "'"$KEY_PAIR_NAME"'",
    "UserData": "'"$USERDATA_BASE64"'",
    "IamInstanceProfile": {
        "Name": "eks-node-role"
    },
    "SecurityGroupIds": ["'"$SECURITY_GROUP_ID"'"]
  }' \
  --output json | jq

# Create Auto Scaling Group using private subnets
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name eks-node-group \
  --launch-template LaunchTemplateName=eks-node-template,Version='$Latest' \
  --min-size 2 \
  --max-size 4 \
  --desired-capacity 2 \
  --vpc-zone-identifier "$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2" \
  --tags \
    "Key=Name,Value=eks-node,PropagateAtLaunch=true" \
    "Key=kubernetes.io/cluster/my-eks-cluster,Value=owned,PropagateAtLaunch=true" \
    "Key=k8s.io/cluster-autoscaler/enabled,Value=true,PropagateAtLaunch=true" \
    "Key=k8s.io/cluster-autoscaler/my-eks-cluster,Value=owned,PropagateAtLaunch=true" \
  --output json | jq

aws eks update-kubeconfig --name my-eks-cluster --region "$REGION"


#####################################################################################################################################################
#####################################################################################################################################################
#####################################################################################################################################################

## Cean up

# Update the desired capacity, min and max size to 0
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-node-group \
  --min-size 0 \
  --max-size 0 \
  --desired-capacity 0

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-node-group \
  --query 'AutoScalingGroups[*].Instances[*]' \
  --output table

aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name eks-node-group

aws ec2 delete-launch-template \
  --launch-template-name eks-node-template

rm "$KEY_PAIR_NAME".pem

# Detach AmazonEKSWorkerNodePolicy
aws iam detach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

# Detach AmazonEKS_CNI_Policy
aws iam detach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

# Detach AmazonEC2ContainerRegistryReadOnly
aws iam detach-role-policy \
  --role-name eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam remove-role-from-instance-profile \
  --instance-profile-name eks-node-role \
  --role-name eks-node-role

aws iam delete-instance-profile \
  --instance-profile-name eks-node-role

aws iam delete-role \
  --role-name eks-node-role

POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='AmazonEKSClusterPolicy'].Arn" --output text)
aws iam detach-role-policy --role-name eks-cluster-role --policy-arn "$POLICY_ARN"
ROLE_POLICY_ARN=$(aws iam list-role-policies --role-name eks-cluster-role --query "PolicyNames[0]" --output text)
aws iam delete-role-policy --role-name eks-cluster-role --policy-name "$ROLE_POLICY_ARN"
aws iam delete-role --role-name eks-cluster-role

SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=eks-cluster-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Remove all inbound rules
aws ec2 revoke-security-group-ingress \
  --group-id "$SECURITY_GROUP_ID" \
  --protocol all \
  --source-group "$SECURITY_GROUP_ID"

# Remove all outbound rules
aws ec2 revoke-security-group-egress \
  --group-id "$SECURITY_GROUP_ID" \
  --protocol all \
  --port -1 \
  --cidr 0.0.0.0/0

aws ec2 delete-security-group \
  --group-id "$SECURITY_GROUP_ID"

# Get public subnet IDs
PUBLIC_SUBNET_1=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=eks-public-subnet-1" \
  --query "Subnets[0].SubnetId" \
  --output text)

PUBLIC_SUBNET_2=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=eks-public-subnet-2" \
  --query "Subnets[0].SubnetId" \
  --output text)

# Get private subnet IDs
PRIVATE_SUBNET_1=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=eks-private-subnet-1" \
  --query "Subnets[0].SubnetId" \
  --output text)

PRIVATE_SUBNET_2=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=eks-private-subnet-2" \
  --query "Subnets[0].SubnetId" \
  --output text)

# Delete public subnets
aws ec2 delete-subnet --subnet-id "$PUBLIC_SUBNET_1"
aws ec2 delete-subnet --subnet-id "$PUBLIC_SUBNET_2"

# Delete private subnets
aws ec2 delete-subnet --subnet-id "$PRIVATE_SUBNET_1"
aws ec2 delete-subnet --subnet-id "$PRIVATE_SUBNET_2"

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-vpc" --query "Vpcs[0].VpcId" --output text)
aws ec2 delete-vpc --vpc-id "$VPC_ID"
