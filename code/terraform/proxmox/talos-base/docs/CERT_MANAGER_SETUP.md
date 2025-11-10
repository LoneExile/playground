# Complete Guide: Cert-Manager with Self-Signed Certificates on Talos Kubernetes

This guide walks you through deploying cert-manager and configuring self-signed certificates for HTTPS access on your NGINX Ingress Controller.

---

## Installation Status - Current Deployment

**Installation Date**: 2025-11-10
**Status**: ✅ OPERATIONAL
**Version**: v1.13.3
**Cluster**: Talos v1.11.1, Kubernetes v1.33.3

### Current Configuration

**CA Type**: Self-signed (4096-bit RSA, 10-year validity)
**ClusterIssuer**: `ca-issuer`
**Certificate Validity**: 90 days (auto-renewal at 75 days before expiry)

### Components Running

```
Controller:       1/1
Webhook:          1/1
CA Injector:      1/1
```

### CA Certificate

**Location**: `docs/talos-ca.crt` (also available as `ca.crt` in project root)
**Subject**: CN=Talos Local CA, O=Talos Cluster, C=US
**Validity**: 10 years (expires 2035-11-08)

**Trust CA on macOS**:
```bash
sudo security add-trusted-cert -k /Library/Keychains/System.keychain docs/talos-ca.crt
```

**Trust CA on Linux**:
```bash
sudo cp docs/talos-ca.crt /usr/local/share/ca-certificates/talos-ca.crt
sudo update-ca-certificates
```

### Certificates Issued

- `harbor-cert` - Harbor Container Registry (harbor.cloud.local)

### Actual Installation Commands Used

```bash
# Install CRDs
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml

# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3

# Create self-signed CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -sha256 -days 3650 -key ca.key -out ca.crt \
  -subj "/CN=Talos Local CA/O=Talos Cluster/C=US"

# Create CA secret
kubectl create secret tls ca-secret --cert=ca.crt --key=ca.key -n cert-manager

# Create ClusterIssuer
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: ca-secret
EOF
```

### Verification Results

```bash
# Cert-manager pods
$ kubectl get pods -n cert-manager
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-5d7f9c8c9b-xxxxx               1/1     Running   0          2h
cert-manager-cainjector-5d8c5d5f8c-xxxxx    1/1     Running   0          2h
cert-manager-webhook-7d9b8c9d8f-xxxxx       1/1     Running   0          2h

# ClusterIssuer ready
$ kubectl get clusterissuer
NAME        READY   AGE
ca-issuer   True    2h

# Certificates issued
$ kubectl get certificates -A
NAMESPACE   NAME          READY   SECRET              AGE
default     harbor-cert   True    harbor-tls-secret   1h
```

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Install Cert-Manager](#step-1-install-cert-manager)
4. [Step 2: Create Self-Signed CA](#step-2-create-self-signed-ca)
5. [Step 3: Configure ClusterIssuer](#step-3-configure-clusterissuer)
6. [Step 4: Create Certificates](#step-4-create-certificates)
7. [Step 5: Configure Ingress with TLS](#step-5-configure-ingress-with-tls)
8. [Step 6: Test HTTPS Access](#step-6-test-https-access)
9. [Alternative: Let's Encrypt](#alternative-lets-encrypt)
10. [Troubleshooting](#troubleshooting)
11. [Production Considerations](#production-considerations)

## Prerequisites

- **Talos Kubernetes cluster** running and accessible
- **kubectl** configured with cluster access
- **Helm 3** installed
- **NGINX Ingress Controller** installed and configured
- **OpenSSL** installed on your local machine

## Architecture Overview

### Self-Signed Certificate Flow

```
                Cert-Manager Objects                        Application Objects

               ┌───────────────────────┐                    ┌─────────────────────────────────┐
Created CA     │ kind: Secret          │                    │                                 │
private key ──►│ name: ca-secret       │◄─────────┐         │ kind: Ingress                   │
and cert       │ tls.key: **priv key** │          │         │ name: my-app-ingress            │
               │ tls.crt: **cert**     │          │         │ tls:                            │
               └───────────────────────┘          │         │   - hosts:                      │
                                                  │         │     - hello.local               │
               ┌──────────────────────────────┐   │    ┌────┼───secretName: hello-tls-secret  │
               │                              │   │    │    │                                 │
               │ kind: ClusterIssuer          │   │    │    └─────────────────────────────────┘
           ┌───┤►name: ca-issuer              │   │    │
           │   │ secretName: ca-secret────────┼───┘    │
           │   │                              │        │
           │   └──────────────────────────────┘        │
           │                                           │
           │   ┌───────────────────────────────┐       │
           │   │                               │       │
           │   │ kind: Certificate             │       │
           │   │ name: hello-cert              │       │
           └───┼─issuerRef:                    │       │
               │   name: ca-issuer             │       │
               │   kind: ClusterIssuer         │       │
               │ dnsNames:                     │       │
               │   - hello.local               │       │
           ┌───┼─secretName: hello-tls-secret  │       │
           │   │                               │       │
           │   └──────────┬────────────────────┘       │
           │              │                            │
           │              │ will be created            │
           │              ▼ and managed automatically  │
           │   ┌───────────────────────────────┐       │
           │   │                               │       │
           │   │ kind: Secret                  │       │
           └───┤►name: hello-tls-secret◄───────┼───────┘
               │ (auto-managed by cert-manager)│
               └───────────────────────────────┘
```

### How It Works

1. **CA Secret**: You create a self-signed Certificate Authority (CA) and store it as a Kubernetes secret
2. **ClusterIssuer**: References the CA secret and acts as the certificate issuer
3. **Certificate**: Defines what domains need certificates (managed by cert-manager)
4. **TLS Secret**: Automatically created and updated by cert-manager with signed certificates
5. **Ingress**: References the TLS secret for HTTPS termination

## Step 1: Install Cert-Manager

### 1.1: Add Cert-Manager Helm Repository

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### 1.2: Install CRDs

Cert-manager requires Custom Resource Definitions (CRDs):

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml
```

### 1.3: Create Namespace

```bash
kubectl create namespace cert-manager
```

### 1.4: Install Cert-Manager with Helm

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.13.3 \
  --set installCRDs=false \
  --set global.leaderElection.namespace=cert-manager
```

**Note**: We use `installCRDs=false` because we manually installed CRDs in step 1.2.

### 1.5: Verify Installation

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Should show 3 pods running:
# - cert-manager
# - cert-manager-cainjector
# - cert-manager-webhook
```

Wait for all pods to be **Running** and **Ready**.

```bash
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=120s
```

## Step 2: Create Self-Signed CA

### 2.1: Generate CA Private Key

```bash
openssl genrsa -out ca.key 4096
```

This creates a 4096-bit RSA private key for your Certificate Authority.

### 2.2: Create CA Certificate

```bash
openssl req -new -x509 -sha256 -days 3650 -key ca.key -out ca.crt \
  -subj "/CN=Talos Local CA/O=Talos Cluster/C=US"
```

**Parameters explained**:
- `-days 3650`: Valid for 10 years
- `-sha256`: Use SHA-256 hash
- `CN=Talos Local CA`: Common Name for your CA
- `O=Talos Cluster`: Organization name
- `C=US`: Country code

You can customize the subject line:
```bash
openssl req -new -x509 -sha256 -days 3650 -key ca.key -out ca.crt \
  -subj "/CN=My Custom CA/O=My Organization/L=My City/ST=My State/C=US"
```

### 2.3: Verify CA Certificate

```bash
openssl x509 -in ca.crt -text -noout
```

You should see certificate details including:
- Issuer (your CA name)
- Validity dates
- Public key information

### 2.4: Trust the CA Certificate (Important!)

For your browser to trust the certificates, you need to add the CA to your system's trusted root store.

**macOS**:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt
```

**Linux (Ubuntu/Debian)**:
```bash
sudo cp ca.crt /usr/local/share/ca-certificates/talos-ca.crt
sudo update-ca-certificates
```

**Windows**:
1. Double-click `ca.crt`
2. Click "Install Certificate"
3. Select "Local Machine"
4. Choose "Place all certificates in the following store"
5. Select "Trusted Root Certification Authorities"
6. Click Finish

**Browser-Specific (Firefox)**:
1. Firefox → Settings → Privacy & Security → Certificates → View Certificates
2. Authorities → Import
3. Select `ca.crt`
4. Trust for identifying websites

## Step 3: Configure ClusterIssuer

### 3.1: Create CA Secret in Kubernetes

```bash
kubectl create secret tls ca-secret \
  --cert=ca.crt \
  --key=ca.key \
  --namespace=cert-manager
```

**Important**: The CA secret must be in the `cert-manager` namespace.

### 3.2: Verify Secret Created

```bash
kubectl get secret ca-secret -n cert-manager
```

### 3.3: Create ClusterIssuer

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: ca-secret
EOF
```

**ClusterIssuer vs Issuer**:
- `ClusterIssuer`: Can issue certificates for any namespace (recommended)
- `Issuer`: Only issues certificates in the same namespace

### 3.4: Verify ClusterIssuer

```bash
kubectl get clusterissuer ca-issuer

# Check status
kubectl describe clusterissuer ca-issuer
```

Status should show `Ready: True`.

## Step 4: Create Certificates

### 4.1: Create Certificate for Test Applications

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: hello-cert
  namespace: default
spec:
  secretName: hello-tls-secret
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - hello.local
  duration: 2160h  # 90 days
  renewBefore: 360h  # Renew 15 days before expiry
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: goodbye-cert
  namespace: default
spec:
  secretName: goodbye-tls-secret
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - goodbye.local
  duration: 2160h
  renewBefore: 360h
EOF
```

### 4.2: Wait for Certificates to be Ready

```bash
kubectl wait --for=condition=Ready certificate/hello-cert --timeout=60s
kubectl wait --for=condition=Ready certificate/goodbye-cert --timeout=60s
```

### 4.3: Verify Certificates

```bash
# Check certificate status
kubectl get certificate

# Should show:
# NAME           READY   SECRET               AGE
# goodbye-cert   True    goodbye-tls-secret   30s
# hello-cert     True    hello-tls-secret     30s
```

### 4.4: Check Generated Secrets

```bash
kubectl get secret hello-tls-secret goodbye-tls-secret
```

Cert-manager automatically creates these secrets with the signed certificates.

### 4.5: Inspect Certificate Details

```bash
# Get certificate from secret
kubectl get secret hello-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

You should see:
- Issuer: Your CA
- Subject: hello.local
- Validity dates
- DNS names (SANs)

## Step 5: Configure Ingress with TLS

### 5.1: Deploy Test Applications

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
          echo "<h1>Hello World App</h1><p>Hostname: $(hostname)</p><p>Secured with HTTPS!</p>" > /usr/share/nginx/html/index.html
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
          echo "<h1>Goodbye World App</h1><p>Hostname: $(hostname)</p><p>Secured with HTTPS!</p>" > /usr/share/nginx/html/index.html
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

### 5.2: Create Ingress with TLS

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress-tls
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - hello.local
    secretName: hello-tls-secret
  - hosts:
    - goodbye.local
    secretName: goodbye-tls-secret
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

**Key Configuration**:
- `tls:` section defines which secrets to use for which hosts
- `ssl-redirect: "true"` automatically redirects HTTP to HTTPS

### 5.3: Verify Ingress Configuration

```bash
kubectl get ingress example-ingress-tls
kubectl describe ingress example-ingress-tls
```

## Step 6: Test HTTPS Access

### 6.1: Update /etc/hosts

```bash
echo "192.168.50.80 hello.local goodbye.local" | sudo tee -a /etc/hosts
```

### 6.2: Test with curl

```bash
# Test HTTP redirect to HTTPS
curl -I http://hello.local
# Should return 308 Permanent Redirect to https://

# Test HTTPS (if CA is trusted)
curl https://hello.local
# Should return: <h1>Hello World App</h1>...

# Test with verbose output
curl -v https://hello.local

# Test without CA trust (skip verification)
curl -k https://hello.local
```

### 6.3: Test in Browser

Open your browser and visit:
- https://hello.local
- https://goodbye.local

**If CA is trusted**: You should see a green padlock (secure connection)
**If CA is not trusted**: You'll see a security warning (click "Advanced" → "Proceed")

### 6.4: Verify Certificate in Browser

In Chrome/Firefox:
1. Click the padlock icon
2. Click "Connection is secure"
3. Click "Certificate is valid"
4. Verify:
   - Issued by: Your CA name
   - Issued to: hello.local
   - Valid dates

### 6.5: Test Certificate Details

```bash
# Test TLS handshake
openssl s_client -connect hello.local:443 -servername hello.local
```

Look for:
- Certificate chain
- Issuer: Your CA
- Subject: hello.local
- Verify return code: 0 (if CA is trusted)

### 6.6: Test from Within Cluster

```bash
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never -- \
  curl -v https://hello-world.default.svc.cluster.local
```

## Alternative: Let's Encrypt

For production with public domains, use Let's Encrypt instead of self-signed certificates.

### Let's Encrypt ClusterIssuer (Staging)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
```

### Let's Encrypt ClusterIssuer (Production)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

### Use in Certificate

```yaml
spec:
  issuerRef:
    name: letsencrypt-prod  # or letsencrypt-staging
    kind: ClusterIssuer
```

**Requirements for Let's Encrypt**:
- Public DNS pointing to your ingress IP
- Port 80 accessible from internet (for HTTP-01 challenge)
- Valid email address

## Troubleshooting

### Certificate Not Ready

**Symptom**:
```bash
kubectl get certificate
# READY shows False
```

**Diagnosis**:
```bash
kubectl describe certificate hello-cert
kubectl get certificaterequest
kubectl describe certificaterequest <name>
```

**Common Causes**:

#### Issue 1: ClusterIssuer not ready

**Solution**:
```bash
kubectl get clusterissuer ca-issuer
kubectl describe clusterissuer ca-issuer
```

Ensure `Status: Ready = True`.

#### Issue 2: CA secret missing or wrong namespace

**Solution**: CA secret must be in `cert-manager` namespace:
```bash
kubectl get secret ca-secret -n cert-manager
```

If missing, recreate:
```bash
kubectl create secret tls ca-secret \
  --cert=ca.crt \
  --key=ca.key \
  --namespace=cert-manager
```

#### Issue 3: Invalid CA certificate

**Solution**: Verify CA cert format:
```bash
openssl x509 -in ca.crt -text -noout
```

### Ingress Shows Certificate Error

**Symptom**: Browser shows certificate error or wrong certificate.

**Diagnosis**:
```bash
# Check TLS secret exists
kubectl get secret hello-tls-secret

# Check certificate content
kubectl get secret hello-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

**Common Causes**:

#### Issue 1: Wrong secret name in ingress

**Solution**: Ensure ingress `tls.secretName` matches certificate `spec.secretName`.

#### Issue 2: Certificate not ready yet

**Solution**: Wait for certificate to be issued:
```bash
kubectl wait --for=condition=Ready certificate/hello-cert --timeout=60s
```

### Browser Shows "Not Secure"

**Symptom**: Browser shows "Your connection is not private" or "Not secure".

**Solutions**:

1. **Trust the CA certificate** (see [Step 2.4](#24-trust-the-ca-certificate-important))

2. **Verify certificate chain**:
```bash
openssl s_client -connect hello.local:443 -servername hello.local
```

3. **Check certificate details** in browser:
   - Click padlock → Certificate details
   - Verify issued by your CA

4. **Bypass warning** (testing only):
   - Chrome: Type `thisisunsafe` while on the warning page
   - Firefox: Click "Advanced" → "Accept the Risk and Continue"

### Certificate Not Auto-Renewing

**Symptom**: Certificate expired or not renewed before `renewBefore` threshold.

**Diagnosis**:
```bash
# Check certificate status
kubectl describe certificate hello-cert

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

**Solution**:
```bash
# Force renewal
kubectl delete secret hello-tls-secret
# Cert-manager will recreate it automatically
```

## Production Considerations

### Security Best Practices

1. **Protect CA Private Key**:
   ```bash
   # Store CA key securely, never commit to git
   chmod 600 ca.key

   # Consider using a secrets manager
   # Delete local copies after uploading to Kubernetes
   ```

2. **Rotate CA Periodically**:
   - Create new CA every 1-2 years
   - Gradually migrate certificates to new CA
   - Update all client trust stores

3. **Use Separate CAs**:
   - Development CA
   - Staging CA
   - Production CA (or use Let's Encrypt)

### Certificate Lifecycle

1. **Auto-Renewal**: Cert-manager automatically renews certificates before `renewBefore` threshold

2. **Monitor Expiry**:
   ```bash
   # Check certificate expiry
   kubectl get certificate -o json | \
     jq -r '.items[] | "\(.metadata.name): \(.status.notAfter)"'
   ```

3. **Set Up Alerts**: Configure Prometheus alerts for certificate expiry

### Multiple Domains

For multiple domains, use Subject Alternative Names (SANs):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: multi-domain-cert
spec:
  secretName: multi-domain-tls
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - app.example.com
    - www.app.example.com
    - api.app.example.com
```

### Wildcard Certificates

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
spec:
  secretName: wildcard-tls
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - "*.example.com"
    - example.com
```

### Namespace Isolation

For better security, use `Issuer` per namespace instead of `ClusterIssuer`:

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: my-app
spec:
  ca:
    secretName: ca-secret
```

## Common Use Cases

### 1. Development/Testing Environment

Use self-signed CA (this guide):
- Full control over certificates
- No external dependencies
- Works offline
- No rate limits

### 2. Internal Services

For services not exposed to internet:
- Use self-signed CA
- Deploy CA cert to all internal clients
- Consider internal PKI infrastructure

### 3. Public Production

Use Let's Encrypt:
- Trusted by all browsers
- Free
- Automatic renewal
- Requires public DNS

### 4. Enterprise Production

Use enterprise CA:
- Internal PKI infrastructure
- Policy compliance
- Audit trails
- Integration with enterprise identity

## References

- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Cert-Manager GitHub](https://github.com/cert-manager/cert-manager)
- [NGINX Ingress TLS](https://kubernetes.github.io/ingress-nginx/user-guide/tls/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [OpenSSL Cookbook](https://www.feistyduck.com/library/openssl-cookbook/)

## Appendix: Useful Commands

```bash
# Cert-Manager
kubectl get certificate -A
kubectl get certificaterequest -A
kubectl get clusterissuer
kubectl describe certificate <name>

# Check certificate in secret
kubectl get secret <name> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

# Force certificate renewal
kubectl delete secret <tls-secret-name>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager -f
kubectl logs -n cert-manager deployment/cert-manager-webhook -f

# Test TLS connection
openssl s_client -connect <host>:443 -servername <host>

# Check certificate expiry
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | \
  openssl x509 -noout -dates

# Verify certificate chain
curl -v https://<host>

# Trust CA on macOS
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt

# Trust CA on Linux
sudo cp ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Remove trusted CA (macOS)
sudo security delete-certificate -c "Your CA Name"

# Check trusted CAs (Linux)
awk -v cmd='openssl x509 -noout -subject' '/BEGIN/{close(cmd)};{print | cmd}' < /etc/ssl/certs/ca-certificates.crt | grep "Your CA"
```

## Appendix: Complete Example

Here's a complete example for a production-like setup:

```yaml
---
# 1. CA Secret (created manually)
# kubectl create secret tls ca-secret --cert=ca.crt --key=ca.key -n cert-manager

---
# 2. ClusterIssuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ca-issuer
spec:
  ca:
    secretName: ca-secret

---
# 3. Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: production
spec:
  secretName: myapp-tls
  issuerRef:
    name: ca-issuer
    kind: ClusterIssuer
  dnsNames:
    - myapp.example.com
    - www.myapp.example.com
  duration: 2160h  # 90 days
  renewBefore: 720h  # Renew 30 days before expiry

---
# 4. Ingress with TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.example.com
    - www.myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
  - host: www.myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
```

---

**Last Updated:** 2025-11-06
**Tested with:** Talos v1.11.1, Kubernetes v1.33.3, Cert-Manager v1.13.3, NGINX Ingress v1.14.0
