
To use this in your Kubernetes cluster, you would create a ServiceAccount like this:

the name should match terraform output value `s3_access_role_arn`
```
terraform output s3_access_role_arn
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-access-sa
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: <s3_access_role_arn output value>
```

or

```bash
kubectl create sa s3-access-sa
kubectl annotate sa s3-access-sa eks.amazonaws.com/role-arn=arn:aws:iam::503561429380:role/eks-s3-access-role
```

Then reference this ServiceAccount in your pod/deployment spec to grant the pod access to the S3 bucket.

```
docker login harbor.voidbox.io
```

