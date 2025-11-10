# Complete Guide: NGINX Ingress Controller on Talos Kubernetes

This guide walks you through deploying the NGINX Ingress Controller on a Talos Kubernetes cluster using Helm with MetalLB LoadBalancer integration.

---

## Installation Status - Current Deployment

**Installation Date**: 2025-11-10
**Status**: ✅ OPERATIONAL
**Version**: Latest (Helm chart ingress-nginx/ingress-nginx)
**Cluster**: Talos v1.11.1, Kubernetes v1.33.3

### Current Configuration

**LoadBalancer IP**: 192.168.50.80 (via MetalLB)
**Ingress Class**: `nginx` (default)
**Replicas**: 1
**Metrics**: Enabled (port 10254, Prometheus compatible)

### Components Running

```
Controller:   1/1
```

### Services

```
LoadBalancer: 192.168.50.80
- HTTP:  80:31xxx/TCP
- HTTPS: 443:31xxx/TCP
Metrics: 10254/TCP (Prometheus)
```

### Ingress Resources

- `harbor-ingress` - Harbor Container Registry (harbor.cloud.local)

### Actual Installation Commands Used

```bash
# Add Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP=192.168.50.80 \
  --set controller.ingressClassResource.default=true \
  --set controller.metrics.enabled=true
```

### Verification Results

```bash
# Controller pod running
$ kubectl get pods -n ingress-nginx
NAME                                       READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-xxxxx-xxxxx        1/1     Running   0          2h

# LoadBalancer service assigned IP
$ kubectl get service -n ingress-nginx
NAME                                 TYPE           EXTERNAL-IP      PORT(S)                      AGE
ingress-nginx-controller             LoadBalancer   192.168.50.80    80:31234/TCP,443:31432/TCP   2h
ingress-nginx-controller-admission   ClusterIP      10.96.xxx.xxx    443/TCP                      2h

# Ingress class available
$ kubectl get ingressclass
NAME    CONTROLLER             PARAMETERS   DEFAULT   AGE
nginx   k8s.io/ingress-nginx   <none>       true      2h

# Ingress resources
$ kubectl get ingress -A
NAMESPACE   NAME             CLASS   HOSTS                ADDRESS         PORTS     AGE
harbor      harbor-ingress   nginx   harbor.cloud.local   192.168.50.80   80, 443   1h

# Test connectivity
$ curl -I http://192.168.50.80
HTTP/1.1 404 Not Found
Server: nginx
```

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Install NGINX Ingress Controller](#step-1-install-nginx-ingress-controller)
4. [Step 2: Verify Installation](#step-2-verify-installation)
5. [Step 3: Create Test Ingress](#step-3-create-test-ingress)
6. [Step 4: Configure DNS](#step-4-configure-dns)
7. [Step 5: Enable HTTPS with Cert-Manager](#step-5-enable-https-with-cert-manager)
8. [Troubleshooting](#troubleshooting)
9. [Production Considerations](#production-considerations)

## Prerequisites

- **Talos Kubernetes cluster** running and accessible
- **kubectl** configured with cluster access
- **Helm 3** installed
- **MetalLB** installed and configured (for LoadBalancer service)
- **DNS** access or `/etc/hosts` file editing capability

### Component Requirements

- **LoadBalancer**: MetalLB or cloud provider LoadBalancer
- **Resources**: Minimum 1 CPU core and 512MB RAM per replica
- **Ingress Class**: Support for multiple ingress controllers

## Architecture Overview

NGINX Ingress Controller provides:
- **HTTP/HTTPS routing** to multiple backend services
- **Single LoadBalancer IP** for all HTTP/HTTPS services
- **SSL/TLS termination** at the ingress layer
- **Path-based and host-based routing**
- **WebSocket support**
- **TCP/UDP proxying** (advanced)

### How It Works

```
Internet
    |
    v
LoadBalancer (MetalLB: 192.168.50.80)
    |
    v
NGINX Ingress Controller Pods
    |
    +-- Host: app1.example.com --> Service: app1
    +-- Host: app2.example.com --> Service: app2
    +-- Host: api.example.com  --> Service: api
```

Instead of each service needing its own LoadBalancer IP, all HTTP/HTTPS traffic goes through a single ingress controller.

## Step 1: Install NGINX Ingress Controller

### 1.1: Add Ingress-NGINX Helm Repository

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

### 1.2: Create Namespace

```bash
kubectl create namespace ingress-nginx
```

### 1.3: Basic Installation with MetalLB

Install with LoadBalancer service type (MetalLB will assign an IP):

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP=192.168.50.80 \
  --set controller.ingressClassResource.default=true \
  --set controller.metrics.enabled=true \
  --set controller.podAnnotations."prometheus\.io/scrape"="true" \
  --set controller.podAnnotations."prometheus\.io/port"="10254"
```

**Parameters explained**:
- `controller.service.type=LoadBalancer` - Use MetalLB for external access
- `controller.service.loadBalancerIP=192.168.50.80` - Request specific IP from MetalLB
- `controller.ingressClassResource.default=true` - Make this the default ingress class
- `controller.metrics.enabled=true` - Enable Prometheus metrics

### 1.4: Installation with Custom Values

For more control, create `ingress-nginx-values.yaml`:

```yaml
# ingress-nginx-values.yaml
controller:
  # Replica configuration
  replicaCount: 2  # For high availability

  # Service configuration
  service:
    type: LoadBalancer
    loadBalancerIP: 192.168.50.80  # Request specific IP from MetalLB
    externalTrafficPolicy: Local  # Preserve source IP
    annotations: {}

  # Ingress class configuration
  ingressClassResource:
    name: nginx
    enabled: true
    default: true  # Make this the default ingress controller

  # Resource limits
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi

  # Enable metrics for monitoring
  metrics:
    enabled: true
    service:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "10254"

  # Pod annotations
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "10254"

  # Enable more detailed logging (optional)
  # config:
  #   log-format-upstream: '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_length $request_time [$proxy_upstream_name] [$proxy_alternative_upstream_name] $upstream_addr $upstream_response_length $upstream_response_time $upstream_status $req_id'

  # Admission webhooks configuration
  admissionWebhooks:
    enabled: true

  # Configure affinity for better pod distribution
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - ingress-nginx
          topologyKey: kubernetes.io/hostname

# Default backend (optional - returns 404 for unmatched routes)
defaultBackend:
  enabled: true
  replicaCount: 1
  resources:
    limits:
      cpu: 100m
      memory: 64Mi
    requests:
      cpu: 10m
      memory: 32Mi
```

Install using the values file:

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --values ingress-nginx-values.yaml
```

### 1.5: Monitor Installation Progress

```bash
# Watch pods starting up
kubectl get pods -n ingress-nginx -w

# Check Helm release
helm status ingress-nginx -n ingress-nginx
```

Installation typically takes 1-2 minutes.

## Step 2: Verify Installation

### 2.1: Check Ingress Controller Pods

```bash
kubectl get pods -n ingress-nginx
```

Expected output:
```
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-xxxxx              1/1     Running   0          2m
ingress-nginx-controller-xxxxx              1/1     Running   0          2m
```

### 2.2: Check LoadBalancer Service

```bash
kubectl get service -n ingress-nginx ingress-nginx-controller
```

Expected output:
```
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
ingress-nginx-controller   LoadBalancer   10.96.123.45    192.168.50.80   80:30080/TCP,443:30443/TCP
```

**Important**: The `EXTERNAL-IP` should show `192.168.50.80` (or your configured IP).

### 2.3: Check Ingress Class

```bash
kubectl get ingressclass
```

Expected output:
```
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       2m
```

### 2.4: Test Basic Connectivity

```bash
curl -I http://192.168.50.80
```

Expected output (404 is normal - no ingress rules yet):
```
HTTP/1.1 404 Not Found
Server: nginx
```

## Step 3: Create Test Ingress

### 3.1: Deploy Sample Applications

Create two sample apps to test ingress routing:

```bash
kubectl apply -f - <<'EOF'
---
# App 1: Hello World
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  labels:
    app: hello-world
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "<h1>Hello World App</h1><p>Hostname: $(hostname)</p>" > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
---
apiVersion: v1
kind: Service
metadata:
  name: hello-world
spec:
  selector:
    app: hello-world
  ports:
  - port: 80
    targetPort: 80
---
# App 2: Goodbye World
apiVersion: apps/v1
kind: Deployment
metadata:
  name: goodbye-world
  labels:
    app: goodbye-world
spec:
  replicas: 2
  selector:
    matchLabels:
      app: goodbye-world
  template:
    metadata:
      labels:
        app: goodbye-world
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "<h1>Goodbye World App</h1><p>Hostname: $(hostname)</p>" > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
---
apiVersion: v1
kind: Service
metadata:
  name: goodbye-world
spec:
  selector:
    app: goodbye-world
  ports:
  - port: 80
    targetPort: 80
EOF
```

### 3.2: Create Ingress Resource (Host-Based Routing)

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: hello.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-world
            port:
              number: 80
  - host: goodbye.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: goodbye-world
            port:
              number: 80
EOF
```

### 3.3: Create Ingress with Path-Based Routing

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-based-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: apps.local
    http:
      paths:
      - path: /hello
        pathType: Prefix
        backend:
          service:
            name: hello-world
            port:
              number: 80
      - path: /goodbye
        pathType: Prefix
        backend:
          service:
            name: goodbye-world
            port:
              number: 80
EOF
```

### 3.4: Verify Ingress Created

```bash
kubectl get ingress
```

Expected output:
```
NAME                 CLASS   HOSTS                        ADDRESS         PORTS   AGE
example-ingress      nginx   hello.local,goodbye.local    192.168.50.80   80      30s
path-based-ingress   nginx   apps.local                   192.168.50.80   80      30s
```

### 3.5: Test Host-Based Routing

Add entries to your `/etc/hosts` file:

```bash
# Add to /etc/hosts
192.168.50.80 hello.local goodbye.local apps.local
```

Test the ingress:

```bash
# Test host-based routing
curl http://hello.local
# Should show: Hello World App

curl http://goodbye.local
# Should show: Goodbye World App

# Test path-based routing
curl http://apps.local/hello
# Should show: Hello World App

curl http://apps.local/goodbye
# Should show: Goodbye World App
```

### 3.6: Test from Browser

Open your browser and visit:
- http://hello.local
- http://goodbye.local
- http://apps.local/hello
- http://apps.local/goodbye

## Step 4: Configure DNS

For production, configure DNS instead of `/etc/hosts`:

### 4.1: Wildcard DNS (Recommended)

Create a wildcard DNS entry pointing to your ingress controller IP:

```
*.example.com.  IN  A  192.168.50.80
```

This allows:
- `app1.example.com` → 192.168.50.80
- `app2.example.com` → 192.168.50.80
- Any subdomain → 192.168.50.80

### 4.2: Individual DNS Entries

Or create individual A records:

```
hello.example.com.    IN  A  192.168.50.80
goodbye.example.com.  IN  A  192.168.50.80
```

### 4.3: Using ExternalDNS (Advanced)

For automatic DNS management, install ExternalDNS:

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --set provider=cloudflare \
  --set cloudflare.apiToken=YOUR_TOKEN
```

Then add annotation to ingress:

```yaml
metadata:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: app.example.com
```

## Step 5: Enable HTTPS with Cert-Manager

### 5.1: Install Cert-Manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
```

Wait for cert-manager pods to be ready:

```bash
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=120s
```

### 5.2: Create ClusterIssuer (Let's Encrypt)

For production certificates:

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com  # Change this
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

For testing (higher rate limits):

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com  # Change this
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 5.3: Create Ingress with TLS

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-world-tls
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging  # or letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - hello.example.com
    secretName: hello-tls-cert
  rules:
  - host: hello.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-world
            port:
              number: 80
EOF
```

### 5.4: Verify Certificate

```bash
# Check certificate status
kubectl get certificate

# Check certificate details
kubectl describe certificate hello-tls-cert

# Wait for certificate to be ready
kubectl wait --for=condition=Ready certificate/hello-tls-cert --timeout=300s
```

### 5.5: Test HTTPS

```bash
curl -k https://hello.example.com
```

Or visit `https://hello.example.com` in your browser.

## Troubleshooting

### Ingress Controller Pods Not Running

**Symptom:**
```bash
kubectl get pods -n ingress-nginx
# Pods in Pending or CrashLoopBackOff
```

**Diagnosis:**
```bash
kubectl describe pod -n ingress-nginx <pod-name>
kubectl logs -n ingress-nginx <pod-name>
```

**Common Causes:**

#### Issue 1: No LoadBalancer IP assigned

**Solution**: Check MetalLB is running:
```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

#### Issue 2: Admission webhook issues

**Solution**: Disable webhooks temporarily:
```bash
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.admissionWebhooks.enabled=false
```

### Ingress Returns 404

**Symptom**: Accessing ingress IP returns 404 for configured hosts.

**Diagnosis:**
```bash
# Check ingress resource
kubectl get ingress
kubectl describe ingress <ingress-name>

# Check backend service
kubectl get service <service-name>
kubectl get endpoints <service-name>
```

**Common Causes:**

#### Issue 1: Wrong host header

**Solution**: Ensure you're using the correct hostname (curl with `-H` or browser with correct URL).

#### Issue 2: Backend service not ready

**Solution**: Check pods are running:
```bash
kubectl get pods -l app=<app-label>
```

#### Issue 3: Ingress class mismatch

**Solution**: Verify ingress class:
```bash
kubectl get ingress <name> -o yaml | grep ingressClassName
```

### HTTPS Not Working

**Symptom**: Certificate not issued or HTTPS connection fails.

**Diagnosis:**
```bash
# Check certificate status
kubectl get certificate
kubectl describe certificate <cert-name>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

**Common Causes:**

#### Issue 1: DNS not resolving

**Solution**: Verify DNS points to ingress IP:
```bash
dig hello.example.com
nslookup hello.example.com
```

#### Issue 2: HTTP01 challenge failing

**Solution**: Ensure port 80 is accessible for Let's Encrypt validation.

#### Issue 3: Rate limits (Let's Encrypt)

**Solution**: Use staging issuer for testing:
```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-staging
```

### Backend Service Unreachable

**Symptom**: 502 Bad Gateway or 503 Service Unavailable.

**Diagnosis:**
```bash
# Check nginx logs
kubectl logs -n ingress-nginx <controller-pod> -f

# Check backend pods
kubectl get pods -l app=<app-name>
kubectl logs <backend-pod>
```

**Common Causes:**

#### Issue 1: Backend pods not ready

**Solution**: Check pod status and readiness probes.

#### Issue 2: Service port mismatch

**Solution**: Verify service and ingress use correct ports:
```bash
kubectl get service <name> -o yaml
```

## Production Considerations

### High Availability

For production, run multiple controller replicas:

```yaml
controller:
  replicaCount: 3  # Minimum for HA

  # Configure pod anti-affinity
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - ingress-nginx
        topologyKey: kubernetes.io/hostname
```

### Resource Limits

Set appropriate resource limits:

```yaml
controller:
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 512Mi
```

### Performance Tuning

For high-traffic environments:

```yaml
controller:
  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    use-proxy-protocol: "false"
    worker-processes: "auto"
    max-worker-connections: "16384"

  # Increase replicas
  replicaCount: 5

  # Set min/max replicas for HPA
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 75
```

### Security Best Practices

1. **Enable ModSecurity WAF**:
```yaml
controller:
  config:
    enable-modsecurity: "true"
    enable-owasp-modsecurity-crs: "true"
```

2. **Rate limiting**:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rate-limit: "100"  # requests per minute
```

3. **Client certificate authentication**:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-secret: "default/ca-secret"
```

4. **IP whitelisting**:
```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
```

### Monitoring

Enable metrics and integrate with Prometheus:

```yaml
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

Create dashboard in Grafana using official NGINX Ingress dashboard (ID: 9614).

### Custom Error Pages

Create custom error pages:

```yaml
controller:
  config:
    custom-http-errors: "404,503"
  defaultBackend:
    enabled: true
    image:
      repository: custom/error-pages
      tag: latest
```

### TCP/UDP Services

Expose non-HTTP services:

```yaml
tcp:
  3306: "default/mysql:3306"
  5432: "default/postgres:5432"

udp:
  53: "kube-system/kube-dns:53"
```

## Common Use Cases

### 1. Simple Web Application

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

### 2. API with Path-Based Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /v1(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-v1
            port:
              number: 8080
      - path: /v2(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: api-v2
            port:
              number: 8080
```

### 3. WebSocket Application

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: websocket
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
spec:
  ingressClassName: nginx
  rules:
  - host: ws.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: websocket-service
            port:
              number: 8080
```

### 4. Basic Authentication

```bash
# Create htpasswd file
htpasswd -c auth admin

# Create secret
kubectl create secret generic basic-auth --from-file=auth
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: protected-app
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
spec:
  ingressClassName: nginx
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: protected-app
            port:
              number: 80
```

### 5. Multiple Apps with Single IP

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-app
spec:
  ingressClassName: nginx
  rules:
  - host: app1.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1
            port:
              number: 80
  - host: app2.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2
            port:
              number: 80
  - host: app3.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app3
            port:
              number: 80
```

## References

- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [NGINX Ingress Helm Chart](https://github.com/kubernetes/ingress-nginx/tree/main/charts/ingress-nginx)
- [Ingress API Reference](https://kubernetes.io/docs/reference/kubernetes-api/service-resources/ingress-v1/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)

## Appendix: Useful Commands

```bash
# Check ingress controller status
kubectl get pods -n ingress-nginx
kubectl get service -n ingress-nginx

# View controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# List all ingress resources
kubectl get ingress -A

# Describe ingress
kubectl describe ingress <name>

# Check ingress class
kubectl get ingressclass

# Test ingress endpoint
curl -H "Host: myapp.local" http://192.168.50.80

# Get controller version
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- /nginx-ingress-controller --version

# Reload configuration (automatic, but force if needed)
kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller

# Check backend endpoints
kubectl get endpoints <service-name>

# View controller metrics
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller-metrics 10254:10254
curl http://localhost:10254/metrics

# Upgrade ingress controller
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --values values.yaml
```

## Appendix: Complete Values File

```yaml
# production-ingress-values.yaml
controller:
  # Replica configuration
  replicaCount: 3

  # Service configuration
  service:
    type: LoadBalancer
    loadBalancerIP: 192.168.50.80
    externalTrafficPolicy: Local

  # Ingress class
  ingressClassResource:
    name: nginx
    enabled: true
    default: true

  # Resource limits
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 512Mi

  # Auto-scaling
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 75

  # Configuration
  config:
    use-forwarded-headers: "true"
    compute-full-forwarded-for: "true"
    use-proxy-protocol: "false"
    worker-processes: "auto"

  # Metrics
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true

  # Admission webhooks
  admissionWebhooks:
    enabled: true

  # Pod anti-affinity
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - ingress-nginx
        topologyKey: kubernetes.io/hostname

# Default backend
defaultBackend:
  enabled: true
  replicaCount: 2
  resources:
    limits:
      cpu: 100m
      memory: 64Mi
    requests:
      cpu: 10m
      memory: 32Mi
```

---

**Last Updated:** 2025-11-06
**Tested with:** Talos v1.11.1, Kubernetes v1.33.3, NGINX Ingress Controller v1.11.3
