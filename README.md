# comfyui-docker

Self-hosted [ComfyUI](https://github.com/Comfy-Org/ComfyUI) container built on the NVIDIA CUDA runtime image. Built via GitHub Actions and published to GHCR.

Runs as a non-root user (UID/GID 1000) with the GPU exposed through the NVIDIA Container Toolkit.

## Requirements

On the Docker host:

- NVIDIA GPU with a working driver (`nvidia-smi` must succeed on the host)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) installed and configured for Docker:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify the toolkit works before starting the container:

```bash
docker run --rm --gpus all ubuntu nvidia-smi
```

## Image

Built from `nvidia/cuda:13.0.0-runtime-ubuntu24.04`. Includes:

- ComfyUI (pinned to a release tag — see the `Dockerfile`)
- PyTorch with CUDA 13.0 wheels (cu130 or newer is required for RTX 20-series and above)
- ComfyUI-Manager, enabled via `--enable-manager`

## Usage

```bash
git clone https://github.com/blakdav/comfyui-docker.git
cd comfyui-docker
mkdir -p models output input user custom_nodes
sudo chown -R 1000:1000 models output input user custom_nodes
docker compose up -d
```

The `chown` matters. The container runs as UID 1000 and will fail to write its
SQLite database or create subdirectories under `input/` if the bind-mounted
directories are owned by root.

Check startup:

```bash
docker logs -f comfyui
```

A healthy start reports the GPU (`Device: cuda:0 ...`), initializes the database,
and ends with `Starting server`.

## Volumes

| Host path      | Container path            | Contents                            |
|----------------|---------------------------|-------------------------------------|
| `models/`      | `/opt/comfyui/models`     | Checkpoints, upscalers, VAEs, LoRAs |
| `input/`       | `/opt/comfyui/input`      | Source images for workflows         |
| `output/`      | `/opt/comfyui/output`     | Generated images and video          |
| `user/`        | `/opt/comfyui/user`       | Workflows, settings, SQLite DB      |
| `custom_nodes/`| `/opt/comfyui/custom_nodes` | Nodes installed via Manager       |

## Models

ComfyUI ships with no models. Place them under the appropriate subdirectory of
`models/` and refresh the browser (`R`) to pick them up:

```
models/
├── checkpoints/      # SDXL, Flux, etc.
├── upscale_models/   # ESRGAN-family .pth files
├── text_encoders/
├── vae/
└── diffusion_models/
```

Anything downloaded outside the container needs its ownership fixed:

```bash
sudo chown -R 1000:1000 models
```

## Networking

The compose file attaches to an external `npm_internal` network and exposes no
host ports — a reverse proxy reaches the container by name on port 8188.

To reach it directly instead, add a port mapping:

```yaml
    ports:
      - "8188:8188"
```

## Notes

**No authentication.** ComfyUI has none built in. Anyone who can reach port 8188
has full control, and ComfyUI-Manager can install and execute arbitrary code from
GitHub. Keep it on an internal network behind an authenticating proxy — never
expose it directly.

**API nodes cost money.** Some bundled workflow templates use hosted models (Wan,
Seedance, and similar) that bill per generation and display a price badge on the
node. They do not run locally. Add `--disable-api-nodes` to the `CMD` to remove
them entirely.

**Version pinning.** The `Dockerfile` clones a release tag rather than `master`.
Upstream warns that commits outside stable releases can be unstable and break
custom nodes. Bump the tag deliberately.

**Build size.** The image lands around 10–15 GB, mostly PyTorch and CUDA. Building
locally leaves a similar amount in build cache — `docker builder prune -a` clears
it. Building in CI and pulling the finished image avoids this on the host.

## CI

`.github/workflows/build.yml` builds on push to `main` and on manual dispatch,
pushing to `ghcr.io/blakdav/comfyui:latest`. The workflow frees disk space before
building; GitHub-hosted runners ship with roughly 14 GB free, which a CUDA and
PyTorch image will otherwise exhaust.

To pull the built image instead of building locally, replace `build: .` with:

```yaml
    image: ghcr.io/blakdav/comfyui:latest
```

Packages are private by default. Either make the package public in its GitHub
settings, or authenticate on the host:

```bash
docker login ghcr.io -u blakdav
```

using a personal access token with `read:packages`.
