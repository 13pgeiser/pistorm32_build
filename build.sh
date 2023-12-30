#!/bin/bash
set -e
source bash-scripts/helpers.sh
if [ -z "$1" ]; then
	run_shfmt_and_shellcheck ./*.sh
fi
docker_configure
docker_setup "pistorm32_build"
dockerfile_create
cat >>"$DOCKERFILE" <<'EOF'
RUN set -ex \
    && apt-get update \
    && apt-get dist-upgrade -y \
    && apt-get install -y --no-install-recommends \
    	build-essential \
    	gcc-aarch64-linux-gnu \
    	g++-aarch64-linux-gnu \
	cmake \
	git \
	ca-certificates \
	xz-utils \
	zip \
    && apt-get clean \
    && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*
RUN set -ex \
    && mkdir -p /release \
    && git clone https://github.com/michalsc/Emu68.git \
    && cd Emu68 \
    && git submodule update --init --recursive \
    && cp /usr/aarch64-linux-gnu/include/gnu/stubs-lp64.h /usr/aarch64-linux-gnu/include/gnu/stubs-lp64_be.h \
    && cd .. \
    && tar cvJf /release/pistorm32-lite_src.tar.xz Emu68
RUN set -ex \
    && cd Emu68 \
    && mkdir build install \
    && cd build \
    && cmake .. -DCMAKE_INSTALL_PREFIX=../install -DTARGET=raspi64 -DVARIANT=pistorm32lite \
    	-DCMAKE_TOOLCHAIN_FILE=../toolchains/aarch64-linux-gnu.cmake \
    && make -j $(nproc) \
    && make install
RUN set -ex \
    && cd Emu68/install \
    && zip -r /release/pistorm32-lite.zip ./*
EOF
docker_build_image_and_create_volume
docker run -d --name "$IMAGE_NAME" "$IMAGE_NAME" sleep 43200
docker cp "$IMAGE_NAME":/release ./
docker rm -f "$IMAGE_NAME" || true
