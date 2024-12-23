# ArgoCD

https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#traefik-v30

- values.yaml

```yaml
global:
  domain: argocd.home.voidbox.io
configs:
  params:
    server.insecure: true
```

```bash
helm install --values values.yaml argocd argo/argo-cd --namespace argocd --create-namespace
# NAME: argocd
# LAST DEPLOYED: Mon Dec 23 17:25:11 2024
# NAMESPACE: argocd
# STATUS: deployed
# REVISION: 1
# TEST SUITE: None
# NOTES:
# In order to access the server UI you have the following options:

# 1. kubectl port-forward service/argocd-server -n argocd 8080:443

#     and then open the browser on http://localhost:8080 and accept the certificate

# 2. enable ingress in the values file `server.ingress.enabled` and either
#       - Add the annotation for ssl passthrough: https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#option-1-ssl-passthrough
#       - Set the `configs.params."server.insecure"` in the values file and terminate SSL at your ingress: https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#option-2-multiple-ingress-objects
# -and-hosts


# After reaching the UI the first time you can login with username: admin and the random password generated during the installation. You can find the password by running:

# kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# (You should delete the initial secret afterwards as suggested by the Getting Started Guide: https://argo-cd.readthedocs.io/en/stable/getting_started/#4-login-using-the-cli)
```

- cert.yaml

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-cert
  namespace: argocd
spec:
  secretName: argocd-cert-secret
  issuerRef:
    name: cloudflare-cluster-issuer
    kind: ClusterIssuer
  dnsNames:
    - argocd.home.voidbox.io
```

- ingressroute.yaml

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`argocd.home.voidbox.io`)
      priority: 10
      services:
        - name: argocd-server
          port: 80
    - kind: Rule
      match: Host(`argocd.home.voidbox.io`) && Header(`Content-Type`, `application/grpc`)
      priority: 11
      services:
        - name: argocd-server
          port: 80
          scheme: h2c
  tls:
    secretName: argocd-cert-secret
```

```bash
k apply -f cert.yaml
k apply -f ingressroute.yaml
k rollout restart deployment -n traefik traefik
k rollout restart deploy/argocd-server -n argocd

kubectl logs -n argocd deployments/argocd-server
kubectl logs -n traefik deployment/traefik
```
