# Cluster Mesh

```bash
# copy .kube/config from each node to the local machine
# let's name as node1, node2
# vim ndoe1 > s/default/node1/g
# vim node2 > s/default/node2/g

export KUBECONFIG=~/root/node1.yaml:/root/node2.yaml
kubectl config view --flatten > ~/.kube/merged_config
mv ~/.kube/config ~/.kube/config.bak
mv ~/.kube/merged_config ~/.kube/config

cilium clustermesh connect \
  --context node1 \
  --destination-context node2
```

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rebel-base
spec:
  selector:
    matchLabels:
      name: rebel-base
  replicas: 2
  template:
    metadata:
      labels:
        name: rebel-base
    spec:
      containers:
        - name: rebel-base
          image: docker.io/nginx:1.15.8
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html/
          livenessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 1
          readinessProbe:
            httpGet:
              path: /
              port: 80
      volumes:
        - name: html
          configMap:
            name: rebel-base-response
            items:
              - key: message
                path: index.html
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: x-wing
spec:
  selector:
    matchLabels:
      name: x-wing
  replicas: 2
  template:
    metadata:
      labels:
        name: x-wing
    spec:
      containers:
        - name: x-wing-container
          image: docker.io/cilium/json-mock:1.2
          livenessProbe:
            exec:
              command:
                - curl
                - -sS
                - -o
                - /dev/null
                - localhost
          readinessProbe:
            exec:
              command:
                - curl
                - -sS
                - -o
                - /dev/null
                - localhost

---
apiVersion: v1
kind: Service
metadata:
  name: rebel-base
spec:
  type: ClusterIP
  ports:
    - port: 80
  selector:
    name: rebel-base
```

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: rebel-base-response
data:
  message: "{\"Cluster\": \"Koornacht\", \"Planet\": \"N'Zoth\"}\n"
```



```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: rebel-base-response
data:
  message: "{\"Cluster\": \"Tion\", \"Planet\": \"Foran Tutha\"}\n"
```

```bash
kubectl exec -ti deployments/x-wing -- /bin/sh -c 'for i in $(seq 1 10); do curl rebel-base; done'

# ⚠️ In *both* the Koornacht and Tion tabs
kubectl annotate service rebel-base service.cilium.io/global="true"
# ⚠️ In the Koornacht tab
kubectl exec -ti deployments/x-wing -- /bin/sh -c 'for i in $(seq 1 10); do curl rebel-base; done'
# You should see a mix of replies from the Koornacht and Tion

## test fault tolerance
# ⚠️ In the Koornacht tab
kubectl scale deployment rebel-base --replicas 0
# ⚠️ In the Koornacht tab
kubectl exec -ti deployments/x-wing -- /bin/sh -c 'for i in $(seq 1 10); do curl rebel-base; done'
```

```bash
## Global vs Shared
# ⚠️ In the Koornacht tab
kubectl annotate service rebel-base service.cilium.io/shared="false"

## Global services & latency
# ⚠️ In the Koornacht tab
kubectl annotate service rebel-base service.cilium.io/affinity=local
# ⚠️ In the Koornacht tab
kubectl exec -ti deployments/x-wing -- /bin/sh -c 'for i in $(seq 1 10); do curl rebel-base; done'
# ⚠️ In the Koornacht tab
kubectl scale deployment rebel-base --replicas 0
# ⚠️ In the Koornacht tab
kubectl exec -ti deployments/x-wing -- /bin/sh -c 'for i in $(seq 1 10); do curl rebel-base; done'
# All traffic now goes to the Tion cluster
# The opposite effect can be obtained by using remote as the annotation value.

kubectl annotate service rebel-base service.cilium.io/affinity-

```


- By default, all communication is allowed between the pods. In order to implement Network Policies, we thus need to start with a default deny rule, which will disallow communication. We will then add specific rules to add the traffic we want to allow.

```yaml
## default-deny.yaml
---
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "default-deny"
spec:
  description: "Default Deny"
  endpointSelector: {}
  ingress:
    - {}
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
          rules:
            dns:
              - matchPattern: "*"
```

```bash
# ⚠️ In *both* the Koornacht and Tion tabs
kubectl apply -f default-deny.yaml
# ⚠️ In the Koornacht tab
kubectl exec -ti deployments/x-wing -- /bin/sh -c 'for i in $(seq 1 10); do curl --max-time 2 rebel-base; done'
# As expected from the application of the default deny policy, all requests now time out.

## You can use its CLI to visualize packet drops:
# ⚠️ In the Koornacht tab
hubble observe --verdict DROPPED --from-pod default/x-wing
```

```yaml
---
## x-wing-to-rebel-base.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "x-wing-to-rebel-base"
spec:
  description: "Allow x-wing in Koornacht to contact rebel-base"
  endpointSelector:
    matchLabels:
      name: x-wing
      io.cilium.k8s.policy.cluster: koornacht
  egress:
  - toEndpoints:
    - matchLabels:
        name: rebel-base

---
## rebel-base-from-x-wing.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: "rebel-base-from-x-wing"
spec:
  description: "Allow rebel-base to be contacted by Koornacht's x-wing"
  endpointSelector:
    matchLabels:
      name: rebel-base
  ingress:
  - fromEndpoints:
    - matchLabels:
        name: x-wing
        io.cilium.k8s.policy.cluster: koornacht
```

```bash
# ⚠️ In the Koornacht tab
kubectl apply -f x-wing-to-rebel-base.yaml
kubectl apply -f rebel-base-from-x-wing.yaml

# It works, but only partially
# This is because we haven't applied any specific policies to the Tion cluster, where the default deny policy was also deployed.

# ⚠️ In the Tion tab
kubectl apply -f rebel-base-from-x-wing.yaml
# ⚠️ In the Koornacht tab
kubectl exec -ti deployments/x-wing -- /bin/sh -c 'for i in $(seq 1 10); do curl --max-time 2 rebel-base; done'
# The requests all go through, and we have successfully secured our service across clusters!
```
