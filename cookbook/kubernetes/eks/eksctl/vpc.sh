#!/bin/bash

# Set variables
export AWS_PROFILE=apinant
REGION=ap-southeast-1
VPC_CIDR="10.0.0.0/16"
CLUSTER_NAME="my-eks-cluster"
EKS_VERSION="1.31"

IS_CREATE_KEY_PAIR=false
KEY_PAIR_NAME="your-key-pair2"
NODE_INSTANCE_TYPE="t3.medium"
NODE_GROUP_NAME="al-nodes"

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --query 'Vpc.VpcId' \
    --output text \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=eks-vpc}]' \
    --region $REGION)

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames "{\"Value\":true}" \
    --region $REGION | jq

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' \
    --output text \
    --region $REGION)

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway \
    --vpc-id $VPC_ID \
    --internet-gateway-id $IGW_ID \
    --region $REGION | jq

# Create Subnets (3 public, 3 private across different AZs)
SUBNETS=()
AZS=($(aws ec2 describe-availability-zones \
    --region $REGION \
    --query 'AvailabilityZones[].ZoneName' \
    --output text))

# Public Subnets
for i in 0 1 2; do
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block "10.0.${i}.0/24" \
        --availability-zone ${AZS[i]} \
        --query 'Subnet.SubnetId' \
        --output text \
        --region $REGION)

    # Enable auto-assign public IP for public subnets
    aws ec2 modify-subnet-attribute \
        --subnet-id $SUBNET_ID \
        --map-public-ip-on-launch \
        --region $REGION
    
    # Tag public subnets
    aws ec2 create-tags \
        --resources $SUBNET_ID \
        --tags \
            Key=Name,Value="public-subnet-${i+1}" \
            Key=kubernetes.io/role/elb,Value=1 \
            Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared \
        --region $REGION | jq

    SUBNETS+=($SUBNET_ID)
done

# Private Subnets
for i in 0 1 2; do
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block "10.0.$((i+10)).0/24" \
        --availability-zone ${AZS[i]} \
        --query 'Subnet.SubnetId' \
        --output text \
        --region $REGION)
    
    # Tag private subnets
    aws ec2 create-tags \
        --resources $SUBNET_ID \
        --tags \
            Key=Name,Value="private-subnet-${i+1}" \
            Key=kubernetes.io/role/internal-elb,Value=1 \
            Key=kubernetes.io/cluster/$CLUSTER_NAME,Value=shared \
        --region $REGION | jq

    SUBNETS+=($SUBNET_ID)
done

# Create Route Tables
PUBLIC_ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.RouteTableId' \
    --output text \
    --region $REGION)

PRIVATE_ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.RouteTableId' \
    --output text \
    --region $REGION)

# Create route to internet gateway for public subnets
aws ec2 create-route \
    --route-table-id $PUBLIC_ROUTE_TABLE_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID \
    --region $REGION | jq

# Associate subnets with route tables
# First 3 subnets (public) associated with public route table
for i in 0 1 2; do
    aws ec2 associate-route-table \
        --subnet-id ${SUBNETS[i]} \
        --route-table-id $PUBLIC_ROUTE_TABLE_ID \
        --region $REGION | jq
done

echo "VPC ID: $VPC_ID"
echo -e "\nPublic Subnets:"
for i in 0 1 2; do
    echo "Public Subnet ${i+1} (${AZS[i]}): ${SUBNETS[i]}"
done

echo -e "\nPrivate Subnets:"
for i in 3 4 5; do
    echo "Private Subnet $((i-2)) (${AZS[i-3]}): ${SUBNETS[i]}"
done

# eksctl create cluster --name my-cluster --region ap-southeast-1 --version 1.31 --vpc-private-subnets subnet-ExampleID1,subnet-ExampleID2 --without-nodegroup

echo "VPC created successfully!"

eksctl create cluster --name $CLUSTER_NAME --region $REGION --vpc-private-subnets ${SUBNETS[3]},${SUBNETS[4]},${SUBNETS[5]} --without-nodegroup --version $EKS_VERSION
aws eks update-kubeconfig --name $CLUSTER_NAME --region "$REGION"

# Wait for cluster to be fully ready
echo "Waiting for EKS cluster to be fully ready (this may take several minutes)..."
until aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.status" --output text | grep -q "ACTIVE"; do
    echo "Waiting for cluster to be ready..."
    sleep 30
done

# Validate connectivity to the cluster
echo "Validating cluster connectivity..."
if ! kubectl get svc &>/dev/null; then
    echo "Error: Unable to connect to the cluster. Please check your VPC configuration and try again."
    exit 1
fi

# Create key pair
if [ "$IS_CREATE_KEY_PAIR" = true ]; then
    echo "Creating SSH key pair..."
    aws ec2 create-key-pair \
        --key-name "$KEY_PAIR_NAME" \
        --query 'KeyMaterial' \
        --output text >"$KEY_PAIR_NAME".pem
fi

PUBLIC_SUBNETS=($(aws ec2 describe-subnets --filters "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[*].SubnetId' --output text))
PRIVATE_SUBNETS=($(aws ec2 describe-subnets --filters "Name=map-public-ip-on-launch,Values=false" --query 'Subnets[*].SubnetId' --output text))

SUBNETS=()

for i in 1 2 3; do
    echo "Public Subnet $i: ${PUBLIC_SUBNETS[i]}"
    SUBNETS+=(${PUBLIC_SUBNETS[i]})
done
for i in 1 2 3; do
    echo "Private Subnet $i: ${PRIVATE_SUBNETS[i]}"
    SUBNETS+=(${PRIVATE_SUBNETS[i]})
done

for i in 1 2 3 4 5 6; do
    echo "Subnet $i: ${SUBNETS[i]}"
done

cat <<EOF >eksctl-config.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}

vpc:
  subnets:
    public:
      public-subnet-1:
        id: ${SUBNETS[1]}
      public-subnet-2:
        id: ${SUBNETS[2]}
      public-subnet-3:
        id: ${SUBNETS[3]}
    private:
      private-subnet-1:
        id: ${SUBNETS[4]}
      private-subnet-2:
        id: ${SUBNETS[5]}
      private-subnet-3:
        id: ${SUBNETS[6]}

managedNodeGroups: []
nodeGroups:
  - name: ${NODE_GROUP_NAME}
    instanceType: ${NODE_INSTANCE_TYPE}
    desiredCapacity: 1
    minSize: 1
    maxSize: 2
    privateNetworking: false
    ssh:
      allow: true
      publicKeyName: ${KEY_PAIR_NAME}
    ami: ${AMI_ID}
    amiFamily: Bottlerocket
    subnets: [${SUBNETS[1]}, ${SUBNETS[2]}, ${SUBNETS[3]}]
    bottlerocket:
      settings:
        kubernetes:
          system-reserved:
            cpu: "10m"
            memory: "100Mi"
            ephemeral-storage: "1Gi"
EOF


# Create nodegroup with error handling
echo "Creating nodegroup..."
if ! eksctl create nodegroup \
  --config-file eksctl-config.yaml; then
    echo "Error: Failed to create nodegroup. Please check the cluster connectivity and try again."
    exit 1
fi

echo "Nodegroup creation completed successfully!"

#   # --node-private-networking \
# eksctl create nodegroup \
#   --cluster $CLUSTER_NAME \
#   --name $NODE_GROUP_NAME \
#   --node-type $NODE_INSTANCE_TYPE \
#   --nodes 2 \
#   --nodes-min 2 \
#   --nodes-max 2 \
#   --managed \
#   --taint "node.cilium.io/agent-not-ready=true:NoExecute" \
#   --ssh-access \
#   --ssh-public-key $KEY_PAIR_NAME \
#   --max-pods-per-node 110 \
#   --subnet-ids subnet-02e9782a32d96b9eb,subnet-0e864ce562d8d7c81,subnet-0dae34501f8b92150
