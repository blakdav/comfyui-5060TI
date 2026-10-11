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
- C/C++ build tools and Python development headers for Triton's runtime compilation

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

### Download models inside the container

The image includes `model-get`, which downloads directly into the mounted models
directory as the container user:

```bash
docker exec -it comfyui model-get text_encoders \
  'https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors'
```

Use a direct file URL (Hugging Face `/resolve/` links, rather than `/blob/` pages).
Quote URLs, especially those containing query parameters. To choose the filename:

```bash
docker exec -it comfyui model-get vae 'https://example.com/download?id=123' --filename ae.safetensors
```

Supported categories: `text_encoders`, `vae`, `diffusion_models`, `checkpoints`,
`loras`, `upscale_models`, `controlnet`, `clip_vision`, `embeddings`, `vae_approx`.
Completed files are skipped. Downloads use a `.part` file and become visible under
their final name only after success. Run the same command to resume a failed or
interrupted download; the server must support HTTP range requests. Resume only
with the same URL/file content. To start over, remove the corresponding `.part`
file. Small `.lock` files prevent concurrent downloads to the same destination.

Public direct downloads are supported; authenticated/gated downloads and model
content/checksum validation are not implemented. The tool does not refresh the
ComfyUI frontend; refresh it after downloading. `COMFYUI_MODELS_DIR` can override
the default `/opt/comfyui/models` directory.

After publishing an image containing this command, update the server:

```bash
docker compose pull comfyui
docker compose up -d comfyui
docker exec comfyui model-get --help
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

BuildKit imports and exports a persistent registry cache at
`ghcr.io/blakdav/comfyui:buildcache` using `mode=max`. This preserves intermediate
build layers across GitHub-hosted runners. The first successful build populates
the cache; later builds reuse unchanged dependency layers. Changes to earlier
Dockerfile instructions still invalidate subsequent layers. The downloader is
copied after dependency installation and ownership changes, so editing it does
not rerun those expensive steps. Cache import/export and image transfer still
take time; caching does not eliminate large downloads to a fresh runner.

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
