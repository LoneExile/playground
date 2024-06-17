#!/usr/bin/env bash

kubectl exec -it fortio-[id] -- fortio load -c 50 -qps 100 -t 300s "http://go-api-server.default.svc.cluster.local/fibonacci?n=100000"

# kubectl run -i --tty load-generator --rm --image=busybox:1.28 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- \"http://go-api-server/fibonacci?n=100000\"; done"
