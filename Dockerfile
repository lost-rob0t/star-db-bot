# syntax=docker/dockerfile:1
FROM nixos/nix:2.28.3 AS build
WORKDIR /src
COPY . .
RUN nix --extra-experimental-features 'nix-command flakes' --option sandbox false \
      build --no-update-lock-file .#default --out-link /out && \
    mkdir -p /rootfs/nix/store /rootfs/bin /rootfs/tmp && \
    chmod 1777 /rootfs/tmp && \
    for runtime_path in $(nix-store --query --requisites /out); do \
      cp -a "$runtime_path" /rootfs/nix/store/; \
    done && \
    ln -s /out/bin/databaseActor /rootfs/bin/databaseActor && \
    cp -a /out /rootfs/out

FROM scratch
COPY --from=build /rootfs/ /
WORKDIR /work
ENTRYPOINT ["/bin/databaseActor"]
