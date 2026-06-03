# 03-image-gen — local text-to-image on the Radeon 780M

Terraform stage that stands up a privileged Debian 13 LXC (`103`, `image-gen`)
on `pve`, passes the **Radeon 780M iGPU** through via `/dev/dri` bind-mount,
builds [`stable-diffusion.cpp`](https://github.com/leejet/stable-diffusion.cpp)
with the **Vulkan** backend, and runs `sd-server` as a systemd service.

Same hardware path as the LLM stack in
[`notes/local-llm-radeon-780m.md`](../notes/local-llm-radeon-780m.md): Mesa RADV
Vulkan in an LXC, **no VM passthrough** (a dead end on Phoenix), **no ROCm**
(unofficial + fragile on gfx1103). The image-gen container shares the iGPU with
the llama-swap LXC (102).

## Why this design

| Choice | Reason |
|---|---|
| `stable-diffusion.cpp` + Vulkan | Same ggml/Vulkan/RADV runtime as your llama.cpp stack. No ROCm, no PyTorch, single binary. |
| Privileged LXC + `/dev/dri` | The only path that works on Phoenix iGPU. Provider wires the cgroup + dev nodes via `device_passthrough`. |
| `sd-server` systemd service | One model resident; A1111-compatible API so Open WebUI can use it. |
| CLIP/VAE on CPU + VAE tiling (default) | Mitigates documented AMD RDNA3 Vulkan output distortion (issues #563/#1279) and VAE alloc failures (#1290). |

## What gets deployed

- LXC 103, privileged, 8 cores / 24 GB RAM / 80 GB disk, static IP `10.0.10.78`
- `/dev/dri/card0` + `/dev/dri/renderD128` passed through
- `stable-diffusion.cpp` built at `/opt/sd-cpp/src/build/bin/sd-server`
- Models in `/opt/sd-cpp/models/` (default: **SDXL-Turbo** + **FLUX.1-schnell** set, ~22 GB, no HF auth)
- `sd-server` on `:7860` — API root `/`, A1111 compat `/sdapi/v1`

## Usage

```bash
cd 03-image-gen
cp terraform.tfvars.example terraform.tfvars   # fill creds + ssh key
terraform init
terraform apply
```

`apply` creates the container, then provisions it over SSH→`pct exec` (build +
model download — **the first apply is slow**: compiling sd.cpp + pulling ~22 GB).
Watch progress:

```bash
ssh root@10.0.10.10 -- pct exec 103 -- journalctl -u sd-server -f
```

### Generate

Web UI (only if `build_frontend = true`): `http://10.0.10.78:7860/`

API (always on), A1111-compatible:

```bash
curl -s http://10.0.10.78:7860/sdapi/v1/txt2img \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"a red fox in snow, cinematic","steps":4,"cfg_scale":1.0,"width":1024,"height":1024}' \
  | jq -r '.images[0]' | base64 -d > out.png
```

> SDXL-Turbo wants **`steps` 1–4, `cfg_scale` 1.0**. Bump steps for the FLUX/other models.
> Exact API field names depend on the sd.cpp release — check `http://10.0.10.78:7860/` and
> the [server README](https://github.com/leejet/stable-diffusion.cpp/tree/master/examples/server)
> (native API lives under `/sdcpp/v1`, plus `/v1` and `/sdapi/v1` compat shims).

### Switch models live

```bash
pct exec 103 -- sd-switch flux      # -> FLUX.1-schnell (higher quality, slower)
pct exec 103 -- sd-switch single    # -> SDXL-Turbo (fast)
```

### Wire into your existing Open WebUI (LXC 102)

Open WebUI has built-in image generation. Point it at this server:
**Admin → Settings → Images → Image Generation (Automatic1111)**, Base URL
`http://10.0.10.78:7860`. Now `chat.0dl.me` can generate images using the 780M.

## ⚠️ Expectations & gotchas

- **Measured on this box**: SDXL-Turbo 768×768, 4 steps, with the default
  `--clip-on-cpu --vae-on-cpu` mitigations = **~131 s/image** (first run; clean,
  no distortion — the RDNA3 Vulkan artefact bug does *not* hit the 780M). Bandwidth-bound
  (DDR5-5600 ~90 GB/s), not compute-bound. To go faster once you trust the output:
  drop `--clip-on-cpu --vae-on-cpu`, lower to 512×512, or fewer steps. FLUX.1-schnell
  is heavier still (12B) — expect multiple minutes.
- **GPU memory is shared with LXC 102.** Both draw from the same ~55 GB pool
  (16 GB UMA + 39 GB GTT). Running a 30B LLM *and* FLUX resident at once can
  exhaust it → OOM. Don't gen + infer heavy simultaneously, or unload one
  (`curl -X POST http://10.0.10.79:11434/unload` on the LLM side).
- **If output is blurry/noisy** (the RDNA3 Vulkan bug): keep the default
  `--clip-on-cpu --vae-on-cpu`. If still bad, test CPU-only by removing
  `-DSD_VULKAN` — CPU output is correct but slow. The 780M (gfx1103) is *not*
  in the confirmed-broken list (890M/680M are), but verify your first images.
- **First service start lags** — model loads after the unit goes active; the
  port starts listening only once weights are in. `TimeoutStartSec=0` is set so
  it won't be killed.
- **DHCP/IP drift**: `ct_ip` is static in the container config, but also reserve
  `10.0.10.78` on the UDM-SE so nothing else grabs it.

## Files

| Path | What |
|---|---|
| `main.tf` | provider, template download, container, provisioning `null_resource` |
| `variables.tf` / `outputs.tf` | inputs / endpoints |
| `scripts/provision-sd.sh` | in-container installer (apt, build, model pull, systemd) |
| `scripts/run-server.sh` | service launcher — reads `server.env`, assembles flags |
| `scripts/sd-switch.sh` | flip `single` ↔ `flux` and restart |
| `templates/server.env.tftpl` | rendered model config |
| `templates/models.tsv.tftpl` | rendered download manifest |

## Gateway route (LAN)

Exposed at **`img.home.0dl.me`** via `02-helm-stack/manifests/image-gen.yaml`
(selector-less Service + EndpointSlice → `10.0.10.78:7860` + HTTPRoute, same
shape as `llm.yaml`). Registered in `02-helm-stack/apps.tf` under `app_files`.
Apply from that stage:

```bash
cd ../02-helm-stack && terraform apply -var-file=../terraform.tfvars
```

LAN-only by design — no Cloudflare Tunnel (image gen has no auth). TLS
terminates at the gateway via the `*.home.0dl.me` wildcard cert. If the LXC IP
changes, update the EndpointSlice `addresses` field and re-apply.
