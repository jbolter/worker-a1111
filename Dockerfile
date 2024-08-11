
# ---------------------------------------------------------------------------- #
#                         Stage 1: Download the models                         #
# ---------------------------------------------------------------------------- #
FROM alpine/git:2.43.0 as download

COPY builder/clone.sh /clone.sh

# Define a build-time argument for the CivitAI API token
ARG CIVITAI_API_TOKEN

RUN mkdir -p /models
RUN mkdir -p /models/Lora && mkdir -p /models/ControlNet

# NOTE: CivitAI usually requires an API token, so you need to add it in the header
#       of the wget command if you're using a model from CivitAI.
RUN apk add --no-cache wget && \
    wget -q -O /cyberrealistic_v50.safetensors "https://civitai.com/api/download/models/537505?type=Model&format=SafeTensor&size=pruned&fp=fp32&token=${CIVITAI_API_TOKEN}" && \
    wget -q -O /models/Lora/ip-adapter-faceid-plusv2_sd15_lora.safetensors "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sd15_lora.safetensors" && \
    wget -q -O /models/ControlNet/ip-adapter-faceid-plusv2_sd15.bin "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sd15.bin" && \
    wget -q -O /models/ControlNet/control_openpose-fp16.safetensors "https://huggingface.co/webui/ControlNet-modules-safetensors/resolve/main/control_openpose-fp16.safetensors" && \
    wget -q -O /models/ControlNet/control_v11p_sd15_openpose.pth "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose.pth" && \
    wget -q -O /models/ControlNet/control_v11p_sd15_openpose.yaml "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose.yaml" && \
    wget -q -O /models/ControlNet/t2iadapter_openpose-fp16.safetensors "https://huggingface.co/webui/ControlNet-modules-safetensors/resolve/main/t2iadapter_openpose-fp16.safetensors"

RUN . /clone.sh extensions adetailer https://github.com/Bing-su/adetailer.git 25e7509fe018de8aa063a5f1902598f5eda0c06c && \
    . /clone.sh extensions sd-webui-controlnet https://github.com/Mikubill/sd-webui-controlnet 56cec5b2958edf3b1807b7e7b2b1b5186dbd2f81 && \
    . /clone.sh extensions sd-webui-additional-network https://github.com/kohya-ss/sd-webui-additional-networks d2758b6c8e2e8e956865a87b31fd74d3d7c010cb

# ---------------------------------------------------------------------------- #
#                        Stage 2: Build the final image                        #
# ---------------------------------------------------------------------------- #
FROM python:3.10.14-slim as build_final_image

ARG A1111_RELEASE=v1.9.3

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    ROOT=/stable-diffusion-webui \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN export COMMANDLINE_ARGS="--skip-torch-cuda-test --precision full --no-half"
RUN export TORCH_COMMAND='pip install ---no-cache-dir torch==2.1.2+cu118 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118'

RUN apt-get update && \
    apt install -y \
    fonts-dejavu-core rsync git jq moreutils aria2 wget libgoogle-perftools-dev libtcmalloc-minimal4 procps libgl1 libglib2.0-0 && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/* && apt-get clean -y

RUN --mount=type=cache,target=/cache --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade pip && \
    ${TORCH_COMMAND} && \
    pip install --no-cache-dir xformers==0.0.23.post1 --index-url https://download.pytorch.org/whl/cu118

RUN --mount=type=cache,target=/root/.cache/pip \
    git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git && \
    cd stable-diffusion-webui && \
    git reset --hard ${A1111_RELEASE} && \
    python -c "from launch import prepare_environment; prepare_environment()" --skip-torch-cuda-test

COPY --from=download /extensions/ ${ROOT}/extensions/
COPY --from=download /models/ ${ROOT}/models/
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r ${ROOT}/extensions/sd-webui-controlnet/requirements.txt

COPY --from=download /cyberrealistic_v50.safetensors /cyberrealistic_v50.safetensors

# Install RunPod SDK
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir runpod

ADD src .

COPY builder/cache.py /stable-diffusion-webui/cache.py
RUN cd /stable-diffusion-webui && python cache.py --use-cpu=all --ckpt /cyberrealistic_v50.safetensors

# Set permissions and specify the command to run
RUN chmod +x /start.sh
CMD /start.sh cyberrealistic_v50
