#!/bin/bash

export AWS_PROFILE=apinant
REGION=ap-southeast-1
VPC_CIDR="10.0.0.0/16"
CLUSTER_NAME="my-eks-cluster"
EKS_VERSION="1.31"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-vpc" --query "Vpcs[0].VpcId" --output text)

# Function to cleanup EKS cluster
cleanup_eks_cluster() {
  echo "Deleting EKS Cluster..."
  eksctl delete cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --wait
}

# Function to delete load balancers
cleanup_load_balancers() {
  echo "Deleting Load Balancers..."
  # Get and delete classic and application load balancers
  aws elb describe-load-balancers --region $REGION |
    jq -r '.LoadBalancerDescriptions[].LoadBalancerName' |
    xargs -I {} aws elb delete-load-balancer --load-balancer-name {} --region $REGION

  aws elbv2 describe-load-balancers --region $REGION |
    jq -r '.LoadBalancers[].LoadBalancerArn' |
    xargs -I {} aws elbv2 delete-load-balancer --load-balancer-arn {} --region $REGION
}

# Function to delete subnets
cleanup_subnets() {
  echo "Deleting Subnets..."
  # Get all subnets in the VPC
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].SubnetId' \
    --output text \
    --region $REGION)

  for subnet in $SUBNET_IDS; do
    aws ec2 delete-subnet \
      --subnet-id $subnet \
      --region $REGION
  done
}

# Function to delete route tables
cleanup_route_tables() {
  echo "Deleting Route Tables..."
  # Get route tables (excluding main route table)
  aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[*].RouteTableId' \
    --output text \
    --region $REGION | tr '\t' '\n' | tr -s ' ' '\n' | while read -r route_table; do
      if [ -n "$route_table" ]; then
        echo "Deleting Route Table: $route_table"
        aws ec2 delete-route-table \
          --route-table-id "$route_table" \
          --region $REGION
      fi
    done
}

# Function to detach and delete internet gateway
cleanup_internet_gateway() {
  echo "Deleting Internet Gateway..."
  # Get Internet Gateway ID
  IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[*].InternetGatewayId' \
    --output text \
    --region $REGION)

  if [ -n "$IGW_ID" ]; then
    # Detach Internet Gateway
    aws ec2 detach-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --vpc-id $VPC_ID \
      --region $REGION

    # Delete Internet Gateway
    aws ec2 delete-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --region $REGION
  fi
}

# Function to delete NAT Gateways
cleanup_nat_gateways() {
  echo "Deleting NAT Gateways..."
  NAT_GATEWAY_IDS=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC_ID" \
    --query 'NatGateways[*].NatGatewayId' \
    --output text \
    --region $REGION)

  for nat_gateway in $NAT_GATEWAY_IDS; do
    aws ec2 delete-nat-gateway \
      --nat-gateway-id $nat_gateway \
      --region $REGION
  done

  # Wait for NAT Gateways to be deleted
  echo "Waiting for NAT Gateways to be deleted..."
  sleep 30
  # aws ec2 wait nat-gateway-available --region $REGION
}

# Function to delete Network Interfaces
cleanup_network_interfaces() {
  echo "Deleting Network Interfaces..."
  ENI_IDS=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[*].NetworkInterfaceId' \
    --output text \
    --region $REGION)

  for eni in $ENI_IDS; do
    aws ec2 delete-network-interface \
      --network-interface-id $eni \
      --region $REGION
  done
}

# Function to delete Security Groups
cleanup_security_groups() {
  echo "Deleting Security Groups..."
  # Get all security groups in the VPC except the default one
  SEC_GROUP_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text \
    --region $REGION)

  for sg in $SEC_GROUP_IDS; do
    aws ec2 delete-security-group \
      --group-id $sg \
      --region $REGION
  done
}

# Function to delete VPC
cleanup_vpc() {
  echo "Deleting VPC..."
  aws ec2 delete-vpc \
    --vpc-id $VPC_ID \
    --region $REGION
}

# Main cleanup function
main() {
  # Cleanup in order
  cleanup_eks_cluster
  cleanup_load_balancers
  cleanup_nat_gateways
  cleanup_network_interfaces
  cleanup_subnets
  cleanup_route_tables
  cleanup_internet_gateway
  cleanup_security_groups
  cleanup_vpc

  echo "Cleanup completed!"
}

# Run cleanup
main
