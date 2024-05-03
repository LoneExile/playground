# cert-manager, let's encrypt, Cloudflare tunnelc

start Kubernetes cluster

 ```bash
   minikube start
 ```

[cert-manager](https://cert-manager.io/docs/installation/)

 ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.yaml
 ```

- install cloudflared then

 ```bash
   cloudflared tunnel login
   
   ## create tunnel
   cloudflared tunnel create [<tunnel-name>]
   
   ## create route 
   cloudflared tunnel route dns [<tunnel>] [<hostname>]
   
   ## create ns
   kubectl create namespace cloudflared
   
   ## create secret
   kubectl create secret generic tunnel-credentials --from-file=credentials.json=/home/<USER>/.cloudflared/<YOUR_TUNNEL_ID>.json -n cloudflared
   kubectl create secret generic cloudflared-cert --from-file=cert.pem=/home/<USER>/.cloudflared/cert.pem -n cloudflared
 ```

- apply this your cloudflared.YAML with this config

 ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: cloudflared
     namespace: cloudflared
   data:
     # <service-name>.<namespace>.svc.cluster.local
     config.yaml: |
       tunnel: kube
       credentials-file: /etc/cloudflared/creds/credentials.json
       metrics: 0.0.0.0:2000
       no-autoupdate: true
       ingress:
       - hostname: <YOUR_DOMAIN>
         service: <http://my-service.default.svc.cluster.local:80>
       - service: http_status:404
   
 ```

 ```yaml
   # apiVersion: cert-manager.io/v1
   # kind: ClusterIssuer
   # metadata:
   #   name: letsencrypt-staging
   # spec:
   #   acme:
   #     # Staging Let's Encrypt URL
   #     server: https://acme-staging-v02.api.letsencrypt.org/directory
   #     email: <YOUR_EMAIL>
   #     privateKeySecretRef:
   #       name: letsencrypt-staging
   #     solvers:
   #     - http01:
   #         ingress:
   #           class: nginx
   
   # ---
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: <YOUR_EMAIL>
       privateKeySecretRef:
         name: letsencrypt-prod
       solvers:
         - http01:
             ingress:
               class: nginx
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: my-app
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: my-app
     template:
       metadata:
         labels:
           app: my-app
       spec:
         containers:
           - name: my-app
             image: nginx:latest
             ports:
               - containerPort: 80
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: my-service
   spec:
     selector:
       app: my-app
     ports:
       - port: 80
   ---
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: my-ingress
     annotations:
       cert-manager.io/cluster-issuer: "letsencrypt-staging" ## can change to `prod`
   spec:
     ingressCclassName: nginx
     rules:
     - host: <YOUR_DOMAIN>
       http:
         paths:
         - path: /
           pathType: Prefix
           backend:
             service:
               name: my-service
               port:
                 number: 80
     tls: # < placing a host in the TLS config will indicate a cert should be created
     - hosts:
       - <YOUR_DOMAIN>
       secretName: nginx-application-tls # cert-manager will store the created certificate in this secret.
 ```

- after all the above up, it's will try to go to the path `your-domain.com/.well-known/acme-challenge/<token>` to verify. but it's will get 404 since we point it to out nginx so we need to edit the cloudflare config to point to our new service that create by cert-manager

 ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: cloudflared
     namespace: cloudflared
   data:
     # <service-name>.<namespace>.svc.cluster.local
     config.yaml: |
       tunnel: kube
       credentials-file: /etc/cloudflared/creds/credentials.json
       metrics: 0.0.0.0:2000
       no-autoupdate: true
       ingress:
       - hostname: <YOUR_DOMAIN>
         service: http://cm-acme-http-solver-<some-number>.default.svc.cluster.local:8089
       - service: http_status:404
 ```

- to get the pem file out

 ```bash
   kubectl get secret nginx-application-tls -o jsonpath="{.data}" | jq -r '."tls.crt"' | base64 --decode > cert.crt
 ```
