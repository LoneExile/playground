# BGP test bed — MetalLB / Cilium / Kube-OVN vs UDM-SE

Test L3 LoadBalancer announcement from the Talos cluster to the UDM-SE over BGP.

## Topology

| Thing | Value |
|---|---|
| Router (UDM-SE) ASN | `65000` @ `10.0.10.1` |
| Cluster ASN | `65001` |
| Talos nodes | `10.0.10.201/.202/.203` (ctrl), `10.0.10.205` (worker) |
| Advertised LB pool | `10.0.30.0/24` (NOT in `10.0.10.0/24` — must be learned via BGP) |

## Hard rules

- **Cilium and Kube-OVN are both CNIs → mutually exclusive.** One per cluster.
- **Don't run MetalLB with Cilium BGP** — both fight to announce LB IPs.
- So this is **3 sequential rounds** (rebuild CNI between B and C), not parallel.

## Step 0 — UDM-SE (once, all rounds)

1. Upload `frr/udmse-frr.conf`: UniFi → Settings → Routing → BGP → Upload Configuration (Network app 8.x+).
2. Ensure a firewall rule lets LAN clients reach `10.0.30.0/24`.
3. Verify: SSH UDM → `vtysh -c "show bgp summary"`. After a round is applied, neighbors flip to `Established`.

> Re-upload the FRR conf after Network-app upgrades — UniFi can clobber it.

## Round A — MetalLB

```bash
kubectl apply -f round-a-metallb/metallb-bgp.yaml
kubectl apply -f demo/demo-lb.yaml
```

## Round B — Cilium (`--set bgpControlPlane.enabled=true`)

```bash
kubectl apply -f round-b-cilium/cilium-bgp.yaml
kubectl apply -f demo/demo-lb.yaml
cilium bgp peers          # should show session up + advertised routes
```

## Round C — Kube-OVN

```bash
# pin image tag in the manifest to your installed kube-ovn version first
kubectl apply -f round-c-kube-ovn/kube-ovn-bgp.yaml
kubectl annotate subnet ovn-default ovn.kubernetes.io/bgp=true
```

## Verify (any round)

```bash
kubectl get svc bgp-demo -o wide        # EXTERNAL-IP from 10.0.30.0/24
ssh <udmse> 'vtysh -c "show ip route bgp"'   # /32 for the LB IP, next-hop = node(s)
curl http://<EXTERNAL-IP>                # from a LAN host -> nginx welcome
```

## Files

```
frr/udmse-frr.conf            UDM-SE FRRouting config (GUI upload)
round-a-metallb/              BGPPeer + IPAddressPool + BGPAdvertisement
round-b-cilium/               CiliumBGPClusterConfig + PeerConfig + Advertisement + LB pool
round-c-kube-ovn/             kube-ovn-speaker DaemonSet
demo/demo-lb.yaml             nginx + LoadBalancer svc (label bgp=announce)
```
