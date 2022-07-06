FROM ghcr.io/drewcarlson/image-builder:master

RUN apt-get update && apt-get install -y \
    binfmt-support \
    gpg \
    qemu \
    qemu-user-static \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

COPY builder /builder/

# create rootfs
CMD /builder/build.sh
