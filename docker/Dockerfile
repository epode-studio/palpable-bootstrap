# Palpable Bootstrap Build Environment
# Based on Alpine Linux for initramfs creation
#
# Usage:
#   docker build -t palpable-builder docker/
#   docker run -v $(pwd):/work palpable-builder /work/build.sh

FROM alpine:3.19

# Install build tools
RUN apk add --no-cache \
    # Core build tools
    make \
    gcc \
    musl-dev \
    linux-headers \
    # Archive/compression
    cpio \
    xz \
    gzip \
    # Disk tools
    dosfstools \
    mtools \
    parted \
    # Download tools
    curl \
    wget \
    # Misc
    bash \
    coreutils \
    findutils \
    file

# Install Alpine SDK for package building (optional, for custom packages)
RUN apk add --no-cache \
    alpine-sdk \
    sudo \
    abuild \
    && adduser -D builder \
    && addgroup builder abuild \
    && echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Install QEMU user static for ARM cross-compilation
RUN apk add --no-cache \
    qemu-aarch64 \
    qemu-arm

# Create working directory
WORKDIR /work

# Default command
CMD ["bash"]
