FROM nvidia/cuda:13.0.0-runtime-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git curl ca-certificates \
    libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --branch v0.7.0 --depth 1 https://github.com/Comfy-Org/ComfyUI.git comfyui
WORKDIR /opt/comfyui

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip

RUN pip install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu130
RUN pip install --no-cache-dir -r requirements.txt -r manager_requirements.txt

COPY --chmod=755 model-get /usr/local/bin/model-get

RUN chown -R 1000:1000 /opt/comfyui /opt/venv
USER 1000:1000

EXPOSE 8188
CMD ["python3", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--enable-manager"]
