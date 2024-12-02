# syntax=docker/dockerfile:1.4

##
## Base layers used to build images
##

# These layers include Debian apt caches, so layers that extend `apt-base`
# should not be published. Instead, these layers should be used to provide
# cached data to individual `RUN` commands.

FROM docker.io/library/debian:bookworm-slim as apt-base
RUN echo 'deb http://deb.debian.org/debian bookworm-backports main' >>/etc/apt/sources.list
RUN DEBIAN_FRONTEND=noninteractive apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip xz-utils
COPY --link bin/scurl /usr/local/bin/

FROM apt-base as apt-node
RUN apt-get install -y gnupg2
ARG NODE_MAJOR=20
RUN mkdir -p /etc/apt/keyrings && scurl https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
RUN apt-get update && apt-get install nodejs -y

# At the moment, we can use the LLVM version shipped by Debian bookworm. If we
# need to diverge in the future we can update this layer to use an alternate apt
# source. See https://apt.llvm.org/.
FROM apt-base as apt-llvm
# RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg2
# RUN curl --tlsv1.2 -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key |apt-key add -
# RUN ( echo 'deb http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-14 main' \
#     && echo 'deb-src http://apt.llvm.org/bookworm/ llvm-toolchain-bookworm-14 main' ) >> /etc/apt/sources.list
# RUN DEBIAN_FRONTEND=noninteractive apt-get update

##
## Scripting tools
##

# j5j Turns JSON5 into plain old JSON (i.e. to be processed by jq).
FROM apt-base as j5j
ARG J5J_VERSION=v0.2.0
RUN url="https://github.com/olix0r/j5j/releases/download/${J5J_VERSION}/j5j-${J5J_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin j5j

# just runs build/test recipes. Like `make` but a bit more ergonomic.
FROM apt-base as just
ARG JUST_VERSION=1.24.0
RUN url="https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin just

# yq is kind of like jq, but for YAML.
FROM apt-base as yq
ARG YQ_VERSION=v4.33.3
RUN url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" ; \
    scurl -o /yq "$url" && chmod +x /yq

FROM scratch as tools-script
COPY --link --from=j5j /usr/local/bin/j5j /bin/
COPY --link --from=just /usr/local/bin/just /bin/
COPY --link --from=yq /yq /bin/
COPY --link bin/scurl /bin/

##
## Kubernetes tools
##

# helm templates kubernetes manifests.
FROM apt-base as helm
ARG HELM_VERSION=v3.14.1
RUN url="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - --strip-components=1 -C /usr/local/bin linux-amd64/helm


# helm-docs generates documentation from helm charts.
FROM apt-base as helm-docs
ARG HELM_DOCS_VERSION=v1.12.0
RUN url="https://github.com/norwoodj/helm-docs/releases/download/$HELM_DOCS_VERSION/helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin helm-docs

# kubectl controls kubernetes clusters.
FROM apt-base as kubectl
ARG KUBECTL_VERSION=v1.29.2
RUN url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" ; \
    scurl -o /usr/local/bin/kubectl "$url" && chmod +x /usr/local/bin/kubectl

# k3d runs kubernetes clusters in docker.
FROM apt-base as k3d
ARG K3D_VERSION=v5.6.0
RUN url="https://raw.githubusercontent.com/rancher/k3d/$K3D_VERSION/install.sh" ; \
    scurl "$url" | USE_SUDO=false K3D_INSTALL_DIR=/usr/local/bin bash
# just-k3d is a utility that encodes many of the common k3d commands we use.
COPY --link bin/just-k3d /usr/local/bin/
# `K3S_IMAGES_JSON` configures just-k3d so that it uses a pinned version of k3s.
# This is generated by `just sync-k3s-images` and i
ENV K3S_IMAGES_JSON=/usr/local/etc/k3s-images.json
COPY --link k3s-images.json "$K3S_IMAGES_JSON"

# step is a tool for managing certificates.
FROM apt-base as step
ARG STEP_VERSION=v0.25.2
RUN scurl -O "https://dl.step.sm/gh-release/cli/docs-cli-install/${STEP_VERSION}/step-cli_${STEP_VERSION#v}_amd64.deb" \
    && dpkg -i "step-cli_${STEP_VERSION#v}_amd64.deb" \
    && rm "step-cli_${STEP_VERSION#v}_amd64.deb"

FROM scratch as tools-k8s
COPY --link --from=helm /usr/local/bin/helm /bin/
COPY --link --from=helm-docs /usr/local/bin/helm-docs /bin/
COPY --link --from=k3d /usr/local/bin/* /bin/
ENV K3S_IMAGES_JSON=/etc/k3s-images.json
COPY --link --from=k3d /usr/local/etc/k3s-images.json "$K3S_IMAGES_JSON"
COPY --link --from=kubectl /usr/local/bin/kubectl /bin/
COPY --link --from=step /usr/bin/step-cli /bin/

##
## Linting tools
##

# actionlint lints github actions workflows.
FROM apt-base as actionlint
ARG ACTIONLINT_VERSION=v1.6.26
RUN url="https://github.com/rhysd/actionlint/releases/download/${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION#v}_linux_amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin actionlint

# checksec checks binaries for security issues.
FROM apt-base as checksec
ARG CHECKSEC_VERSION=2.5.0
RUN url="https://raw.githubusercontent.com/slimm609/checksec.sh/${CHECKSEC_VERSION}/checksec" ; \
    scurl -o /usr/local/bin/checksec "$url" && chmod 755 /usr/local/bin/checksec

# shellcheck lints shell scripts.
FROM apt-base as shellcheck
ARG SHELLCHECK_VERSION=v0.9.0
RUN url="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" ; \
    scurl "$url" | tar xJvf - --strip-components=1 -C /usr/local/bin "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
COPY --link bin/just-sh /usr/local/bin/

FROM scratch as tools-lint
COPY --link --from=actionlint /usr/local/bin/actionlint /bin/
COPY --link --from=checksec /usr/local/bin/checksec /bin/
COPY --link --from=shellcheck /usr/local/bin/shellcheck /bin/
COPY --link bin/action-* bin/just-dev bin/just-sh /bin/

##
## Protobuf
##

FROM apt-base as protobuf
ARG PROTOC_VERSION=v3.20.3
RUN url="https://github.com/google/protobuf/releases/download/$PROTOC_VERSION/protoc-${PROTOC_VERSION#v}-linux-$(uname -m).zip" ; \
    cd $(mktemp -d) && \
    scurl -o protoc.zip  "$url" && \
    unzip protoc.zip bin/protoc include/** && \
    mv bin/protoc /usr/local/bin/protoc && \
    chmod +x /usr/local/bin/protoc && \
    mkdir -p /usr/local/include && \
    mv include/google /usr/local/include/

##
## Rust tools
##

# cargo-action-fmt formats `cargo build` JSON output to Github Actions annotations.
FROM apt-base as cargo-action-fmt
ARG CARGO_ACTION_FMT_VERSION=1.0.2
RUN url="https://github.com/olix0r/cargo-action-fmt/releases/download/release%2Fv${CARGO_ACTION_FMT_VERSION}/cargo-action-fmt-x86_64-unknown-linux-gnu" ; \
    scurl -o /usr/local/bin/cargo-action-fmt "$url" && chmod +x /usr/local/bin/cargo-action-fmt

# cargo-deny checks cargo dependencies for licensing and RUSTSEC security issues.
FROM apt-base as cargo-deny
ARG CARGO_DENY_VERSION=0.16.3
RUN url="https://github.com/EmbarkStudios/cargo-deny/releases/download/${CARGO_DENY_VERSION}/cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - --strip-components=1 -C /usr/local/bin "cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl/cargo-deny"

# cargo-nextest is a nicer test runner.
FROM apt-base as cargo-nextest
ARG NEXTEST_VERSION=0.9.67
RUN url="https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-${NEXTEST_VERSION}/cargo-nextest-${NEXTEST_VERSION}-x86_64-unknown-linux-gnu.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin cargo-nextest

# cargo-tarpaulin is a code coverage tool.
FROM apt-base as cargo-tarpaulin
ARG CARGO_TARPAULIN_VERSION=0.27.3
RUN url="https://github.com/xd009642/tarpaulin/releases/download/${CARGO_TARPAULIN_VERSION}/cargo-tarpaulin-x86_64-unknown-linux-musl.tar.gz" ;\
    scurl "$url" | tar xzvf - -C /usr/local/bin cargo-tarpaulin

FROM scratch as tools-rust
COPY --link --from=cargo-action-fmt /usr/local/bin/cargo-action-fmt /bin/
COPY --link --from=cargo-deny /usr/local/bin/cargo-deny /bin/
COPY --link --from=cargo-nextest /usr/local/bin/cargo-nextest /bin/
COPY --link --from=cargo-tarpaulin /usr/local/bin/cargo-tarpaulin /bin/
COPY --link bin/just-cargo /bin/

##
## Go tools
##

FROM docker.io/library/golang:1.23 as go-delve
RUN go install github.com/go-delve/delve/cmd/dlv@latest

FROM docker.io/library/golang:1.23 as go-impl
RUN go install github.com/josharian/impl@latest

FROM docker.io/library/golang:1.23 as go-outline
RUN go install github.com/ramya-rao-a/go-outline@latest

FROM docker.io/library/golang:1.23 as go-protoc
ARG PROTOC_GEN_GO_VERSION=v1.35.2
ARG PROTOC_GEN_GO_GRPC_VERSION=v1.5.1
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@${PROTOC_GEN_GO_VERSION}
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@${PROTOC_GEN_GO_GRPC_VERSION}

FROM docker.io/library/golang:1.23 as golangci-lint
RUN go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

FROM docker.io/library/golang:1.23 as gomodifytags
RUN go install github.com/fatih/gomodifytags@latest

FROM docker.io/library/golang:1.23 as gopkgs
RUN go install github.com/uudashr/gopkgs/v2/cmd/gopkgs@latest

FROM docker.io/library/golang:1.23 as goplay
RUN go install github.com/haya14busa/goplay/cmd/goplay@latest

FROM docker.io/library/golang:1.23 as gopls
RUN go install golang.org/x/tools/gopls@latest

FROM docker.io/library/golang:1.23 as gotests
RUN go install github.com/cweill/gotests/gotests@latest

FROM docker.io/library/golang:1.23 as gotestsum
ARG GOTESTSUM_VERSION=v1.12.0
RUN go install gotest.tools/gotestsum@${GOTESTSUM_VERSION}

FROM scratch as tools-go
COPY --link --from=go-delve /go/bin/dlv /bin/
COPY --link --from=go-impl /go/bin/impl /bin/
COPY --link --from=go-outline /go/bin/go-outline /bin/
COPY --link --from=go-protoc /go/bin/protoc-gen-* /bin/
COPY --link --from=golangci-lint /go/bin/golangci-lint /bin/
COPY --link --from=gomodifytags /go/bin/gomodifytags /bin/
COPY --link --from=goplay /go/bin/goplay /bin/
COPY --link --from=gopls /go/bin/gopls /bin/
COPY --link --from=gopkgs /go/bin/gopkgs /bin/
COPY --link --from=gotests /go/bin/gotests /bin/
COPY --link --from=gotestsum /go/bin/gotestsum /bin/

# Networking utilities
FROM scratch as tools-net
COPY --link --from=ghcr.io/olix0r/hokay:v0.2.2 /hokay /bin/

##
## All Tools
##

FROM scratch as tools
COPY --link --from=tools-go /bin/* /bin/
COPY --link --from=tools-k8s /bin/* /bin/
COPY --link --from=tools-k8s /etc/* /etc/
ENV K3S_IMAGES_JSON=/etc/k3s-images.json
COPY --link --from=tools-lint /bin/* /bin/
COPY --link --from=tools-net /bin/* /bin/
COPY --link --from=tools-rust /bin/* /bin/
COPY --link --from=tools-script /bin/* /bin/

##
## Base images
##

# A Go build environment.
FROM docker.io/library/golang:1.23 as go
RUN --mount=type=cache,from=apt-base,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-base,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-base,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y file jo jq
COPY --link --from=tools-script /bin/* /usr/local/bin/
COPY --link --from=tools-go /bin/* /usr/local/bin/
COPY --link --from=protobuf /usr/local/bin/protoc /usr/local/bin/
COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1 \
    PROTOC=/usr/local/bin/protoc \
    PROTOC_INCLUDE=/usr/local/include

# A Rust build environment.
FROM docker.io/library/rust:1.83-slim-bookworm as rust
RUN --mount=type=cache,from=apt-base,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-base,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-base,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        cmake \
        curl \
        file \
        git \
        jo \
        jq \
        libssl-dev \
        pkg-config
RUN --mount=type=cache,from=apt-llvm,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-llvm,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-llvm,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y clang-14 llvm-14
RUN rustup component add clippy rustfmt
COPY --link --from=tools-lint /bin/checksec /usr/local/bin/
COPY --link --from=tools-script /bin/* /usr/local/bin/
COPY --link --from=tools-rust /bin/* /usr/local/bin/
COPY --link --from=protobuf /usr/local/bin/protoc /usr/local/bin/
COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1 \
    PROTOC=/usr/local/bin/protoc \
    PROTOC_INCLUDE=/usr/local/include
# Rust settings for CI
ENV CARGO_INCREMENTAL=0 \
    CARGO_NET_RETRY=10 \
    RUST_BACKTRACE=short \
    RUSTUP_MAX_RETRIES=10
ENTRYPOINT ["/usr/local/bin/just-cargo"]

COPY --link --from=just /usr/local/bin/just /usr/local/bin/
FROM rust as rust-musl
RUN rustup target add \
        aarch64-unknown-linux-musl \
        armv7-unknown-linux-musleabihf \
        x86_64-unknown-linux-musl
RUN --mount=type=cache,from=apt-base,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-base,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-base,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        g++-aarch64-linux-gnu \
        g++-arm-linux-gnueabihf \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        libc6-dev-arm64-cross \
        libc6-dev-armhf-cross

##
## Devcontainer
##

FROM docker.io/library/debian:bookworm as devcontainer
RUN --mount=type=cache,from=apt-base,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-base,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-base,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        cmake \
        curl \
        dnsutils \
        file \
        iproute2 \
        jo \
        jq \
        libssl-dev \
        locales \
        lsb-release \
        netcat-openbsd \
        pkg-config \
        skopeo \
        sudo \
        time \
        tshark \
        unzip

# Link the gnu versions of ranlib to the musl toolchain.
# See: https://github.com/linkerd/linkerd2/issues/13350
RUN ln -s /usr/bin/aarch64-linux-gnu-ranlib /usr/bin/aarch64-linux-musl-ranlib && \
    ln -s /usr/bin/arm-linux-gnueabihf-ranlib /usr/bin/arm-linux-musl-ranlib && \
    ln -s /usr/bin/x86_64-linux-gnu-ranlib /usr/bin/x86_64-linux-musl-ranlib

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && (echo "LC_ALL=en_US.UTF-8" && echo "LANGUAGE=en_US.UTF-8") >/etc/default/locale

RUN groupadd --gid=1000 code \
    && useradd --create-home --uid=1000 --gid=1000 code \
    && echo "code ALL=(root) NOPASSWD:ALL" >/etc/sudoers.d/code \
    && chmod 0440 /etc/sudoers.d/code

# git v2.34+ has new subcommands and supports code signing via SSH.
RUN --mount=type=cache,from=apt-base,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-base,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-base,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -t bookworm-backports git

RUN --mount=type=cache,from=apt-llvm,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-llvm,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-llvm,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y clang-14 llvm-14

# Use microsoft's Docker setup script to install the Docker CLI.
#
# A distinct cache is used because the script adds an apt repo that we don't
# want to pull in for other layers.
#
# TODO(ver): replace this with a devcontainer feature?
RUN --mount=type=cache,id=apt-docker,from=apt-base,source=/etc/apt,target=/etc/apt \
    --mount=type=cache,id=apt-docker,from=apt-base,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-docker,from=apt-base,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=bind,from=tools,source=/bin/scurl,target=/usr/local/bin/scurl \
    scurl https://raw.githubusercontent.com/microsoft/vscode-dev-containers/main/script-library/docker-debian.sh | bash -s
ENV DOCKER_BUILDKIT=1

ARG MARKDOWNLINT_VERSION=0.10.0
RUN --mount=type=cache,from=apt-node,source=/etc/apt,target=/etc/apt,ro \
    --mount=type=cache,from=apt-node,source=/var/cache/apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,from=apt-node,source=/var/lib/apt/lists,target=/var/lib/apt/lists,sharing=locked \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
RUN npm install "markdownlint-cli2@${MARKDOWNLINT_VERSION}" --global

COPY --link --from=go /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:$PATH"

ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
COPY --link --from=rust $CARGO_HOME $CARGO_HOME
COPY --link --from=rust $RUSTUP_HOME $RUSTUP_HOME
RUN find "$CARGO_HOME" "$RUSTUP_HOME" -type d -exec chmod 777 '{}' +
ENV PATH="$CARGO_HOME/bin:$PATH"

COPY --link --from=protobuf /usr/local/bin/protoc /usr/local/bin/protoc
COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1 \
    PROTOC=/usr/local/bin/protoc \
    PROTOC_INCLUDE=/usr/local/include

COPY --link bin/just-md /usr/local/bin/
COPY --link --from=tools /bin/* /usr/local/bin/
COPY --link --from=tools /etc/* /usr/local/etc/
ENV K3S_IMAGES_JSON=/usr/local/etc/k3s-images.json

ENV HOME=/home/code \
    USER=code
USER code
ENV GOPATH="$HOME/go"
RUN mkdir "$GOPATH"
ENV PATH="$GOPATH/bin:$PATH"

ENTRYPOINT ["/usr/local/share/docker-init.sh"]
CMD ["sleep", "infinity"]
