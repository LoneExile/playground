#!/bin/bash
export AWS_REGION=ap-southeast-1
aws eks --region $AWS_REGION update-kubeconfig --name private_eks_cluster

KUBECONFIG_FILE="/home/ec2-user/.kube/config"

sed -i 's/apiVersion: client.authentication.k8s.io\/v1alpha1/apiVersion: client.authentication.k8s.io\/v1beta1/' "$KUBECONFIG_FILE"


cat <<EOF >aws_configure.sh
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_DEFAULT_REGION="ap-southeast-1"
EOF
chmod +x aws_configure.sh
source ./aws_configure.sh

kubectl get configmap aws-auth -n kube-system -o yaml >/tmp/aws-auth.yaml

kubectl patch configmap aws-auth -n kube-system -p "$(
  cat <<EOF
{
  "data": {
    "mapRoles": "- groups:\n    - system:masters\n  rolearn: arn:aws:iam::503561429380:role/eks-bastion\n  username: eks-bastion"
  }
}
EOF
)"

kubectl get configmap aws-auth -n kube-system -o yaml >cm.yaml
rm -f aws_configure.sh
echo "Config Updated" >updated.txt
