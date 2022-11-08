##
## Base
##

FROM docker.io/debian:bullseye-slim as base
RUN apt update && apt upgrade -y --autoremove \
    && apt install -y \
        curl \
        file \
        git \
        jo \
        jq \
        time \
        unzip \
        xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY bin/scurl /usr/local/bin/scurl

FROM base as just
ARG JUST_VERSION=1.6.0
RUN url="https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin just
COPY bin/* /usr/local/bin/

FROM base as protoc
ARG PROTOC_VERSION=v3.20.3
RUN url="https://github.com/google/protobuf/releases/download/$PROTOC_VERSION/protoc-${PROTOC_VERSION#v}-linux-$(uname -m).zip" ; \
    cd $(mktemp -d) && \
    scurl -o protoc.zip  "$url" && \
    unzip protoc.zip bin/protoc include/** && \
    mv bin/protoc /usr/local/bin/protoc && \
    chmod +x /usr/local/bin/protoc && \
    mkdir -p /usr/local/include && \
    mv include/google /usr/local/include/

FROM base as yq
ARG YQ_VERSION=v4.25.1
RUN url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" ; \
    scurl -o /usr/local/bin/yq "$url" && chmod +x /usr/local/bin/yq

##
## Rust image
##

FROM base as checksec
ARG CHECKSEC_VERSION=2.5.0
RUN url="https://raw.githubusercontent.com/slimm609/checksec.sh/${CHECKSEC_VERSION}/checksec" ; \
    scurl -o /usr/local/bin/checksec "$url" && chmod 755 /usr/local/bin/checksec

FROM base as cargo-action-fmt
ARG CARGO_ACTION_FMT_VERSION=1.0.2
RUN url="https://github.com/olix0r/cargo-action-fmt/releases/download/release%2Fv${CARGO_ACTION_FMT_VERSION}/cargo-action-fmt-x86_64-unknown-linux-gnu" ; \
    scurl -o /usr/local/bin/cargo-action-fmt "$url" && chmod +x /usr/local/bin/cargo-action-fmt

FROM base as cargo-cross
ARG CARGO_CROSS_VERSION=0.2.4
RUN url="https://github.com/cross-rs/cross/releases/download/v${CARGO_CROSS_VERSION}/cross-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin cross cross-util

FROM base as cargo-deny
ARG CARGO_DENY_VERSION=0.12.2
RUN url="https://github.com/EmbarkStudios/cargo-deny/releases/download/${CARGO_DENY_VERSION}/cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - --strip-components=1 -C /usr/local/bin "cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl/cargo-deny"

FROM base as cargo-nextest
ARG NEXTEST_VERSION=0.9.42
RUN url="https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-${NEXTEST_VERSION}/cargo-nextest-${NEXTEST_VERSION}-x86_64-unknown-linux-gnu.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin cargo-nextest

FROM base as cargo-tarpaulin
ARG CARGO_TARPAULIN_VERSION=0.22.0
RUN url="https://github.com/xd009642/tarpaulin/releases/download/${CARGO_TARPAULIN_VERSION}/cargo-tarpaulin-${CARGO_TARPAULIN_VERSION}-travis.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin cargo-tarpaulin

FROM docker.io/rust:1.64.0-slim-bullseye as rust
RUN rustup component add clippy rustfmt
RUN rustup target add x86_64-unknown-linux-gnu x86_64-unknown-linux-musl
RUN apt update && apt upgrade -y --autoremove \
    && apt install -y \
        binutils-x86-64-linux-gnu \
        clang \
        cmake \
        curl \
        file \
        git \
        jo \
        jq \
        libssl-dev \
        llvm \
        musl-tools \
        pkg-config \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --from=cargo-action-fmt /usr/local/bin/cargo-action-fmt /usr/local/cargo/bin/
COPY --from=cargo-deny /usr/local/bin/cargo-deny /usr/local/cargo/bin/
COPY --from=cargo-nextest /usr/local/bin/cargo-nextest /usr/local/cargo/bin/
COPY --from=cargo-tarpaulin /usr/local/bin/cargo-tarpaulin /usr/local/cargo/bin/
COPY --from=checksec /usr/local/bin/checksec /usr/local/bin/checksec
COPY --from=just /usr/local/bin/* /usr/local/bin/
COPY --from=protoc /usr/local/bin/protoc /usr/local/bin/
COPY --from=protoc /usr/local/include/google /usr/local/include/google
COPY --from=yq /usr/local/bin/yq /usr/local/bin/
COPY bin/scurl /usr/local/bin/scurl
ENV USER=root
ENV PROTOC_NO_VENDOR=1
ENV PROTOC=/usr/local/bin/protoc
ENV PROTOC_INCLUDE=/usr/local/include

FROM rust as rust-cross
# Two ways to cross-compile Rust binaries:
# 1. GNU cross complication utilities for aarch64 and armv7
# 2. The container-based `cross` tool for other platforms (especially MUSL)
RUN rustup target add \
        aarch64-unknown-linux-gnu \
        aarch64-unknown-linux-musl \
        armv7-unknown-linux-gnueabihf \
        armv7-unknown-linux-musleabihf
RUN apt update && apt upgrade -y --autoremove \
    && apt install -y \
        binutils-aarch64-linux-gnu \
        binutils-arm-linux-gnueabihf \
        g++-aarch64-linux-gnu \
        g++-arm-linux-gnueabihf \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        libc6-dev-arm64-cross \
        libc6-dev-armhf-cross \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
    CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++
COPY --from=cargo-cross /usr/local/bin/cross /usr/local/bin/cross-util /usr/local/cargo/bin/
ENV CROSS_DOCKER_IN_DOCKER=true

##
## Go image
##

FROM docker.io/golang:1.18.7 as go
RUN apt update && apt upgrade -y --autoremove \
    && apt install -y \
        curl \
        file \
        jq \
        time \
        unzip \
        xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN for p in \
    github.com/cweill/gotests/gotests@latest \
    github.com/go-delve/delve/cmd/dlv@latest \
    github.com/golangci/golangci-lint/cmd/golangci-lint@latest \
    github.com/fatih/gomodifytags@latest \
    github.com/haya14busa/goplay/cmd/goplay@latest \
    github.com/josharian/impl@latest \
    github.com/ramya-rao-a/go-outline@latest \
    github.com/uudashr/gopkgs/v2/cmd/gopkgs@latest \
    golang.org/x/tools/gopls@latest \
    google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2 \
    google.golang.org/protobuf/cmd/protoc-gen-go@v1.28.1 \
    gotest.tools/gotestsum@v0.4.2 \
    ; do go install "$p" ; done \
    && rm -rf /go/pkg/* /go/src/*
COPY bin/scurl /usr/local/bin/scurl
COPY --from=protoc /usr/local/bin/protoc /usr/local/bin/
COPY --from=protoc /usr/local/include/google /usr/local/include/google
COPY --from=just /usr/local/bin/* /usr/local/bin/
ENV PROTOC_NO_VENDOR=1
ENV PROTOC=/usr/local/bin/protoc
ENV PROTOC_INCLUDE=/usr/local/include

##
## Kubernetes tools
##

FROM base as k8s

ARG KUBECTL_VERSION=v1.25.3
RUN url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" ; \
    scurl -o /usr/local/bin/kubectl "$url" && chmod +x /usr/local/bin/kubectl

ARG K3D_VERSION=v5.4.6
RUN url="https://raw.githubusercontent.com/rancher/k3d/$K3D_VERSION/install.sh" ; \
    scurl "$url" | USE_SUDO=false K3D_INSTALL_DIR=/usr/local/bin bash

ARG HELM_VERSION=v3.10.1
RUN url="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - --strip-components=1 -C /usr/local/bin linux-amd64/helm

ARG HELM_DOCS_VERSION=v1.11.0
RUN url="https://github.com/norwoodj/helm-docs/releases/download/$HELM_DOCS_VERSION/helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin helm-docs

##
## Other tools
##

FROM base as shellcheck
ARG SHELLCHECK_VERSION=v0.8.0
RUN url="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" ; \
    scurl "$url" | tar xJvf - --strip-components=1 -C /usr/local/bin "shellcheck-${SHELLCHECK_VERSION}/shellcheck"

FROM shellcheck as actionlint
ARG ACTIONLINT_VERSION=v1.6.21
RUN url="https://github.com/rhysd/actionlint/releases/download/${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION#v}_linux_amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin actionlint

FROM base as j5j
ARG J5J_VERSION=v0.2.0
RUN url="https://github.com/olix0r/j5j/releases/download/${J5J_VERSION}/j5j-${J5J_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin j5j

FROM docker.io/node:16-bullseye-slim as node
ARG MARKDOWNLINT_VERSION=0.5.1
RUN npm install "markdownlint-cli2@${MARKDOWNLINT_VERSION}" --global

FROM base as step
RUN scurl -O https://dl.step.sm/gh-release/cli/docs-cli-install/v0.21.0/step-cli_0.21.0_amd64.deb \
    && dpkg -i step-cli_0.21.0_amd64.deb

FROM ghcr.io/olix0r/hokay:v0.2.2 as hokay

##
## Tools: Everything needed for a development environment, minus non-root settings.
##

FROM base as tools
COPY --from=actionlint /usr/local/bin/actionlint /usr/local/bin/
COPY --from=checksec /usr/local/bin/checksec /usr/local/bin/checksec
COPY --from=hokay /hokay /usr/local/bin/
COPY --from=j5j /usr/local/bin/j5j /usr/local/bin/
COPY --from=just /usr/local/bin/* /usr/local/bin/
COPY --from=k8s /usr/local/bin/helm /usr/local/bin/
COPY --from=k8s /usr/local/bin/helm-docs /usr/local/bin/
COPY --from=k8s /usr/local/bin/k3d /usr/local/bin/
COPY --from=k8s /usr/local/bin/kubectl /usr/local/bin/
COPY --from=protoc /usr/local/bin/protoc /usr/local/bin/
COPY --from=protoc /usr/local/include/google /usr/local/include/google
COPY --from=shellcheck /usr/local/bin/shellcheck /usr/local/bin/
COPY --from=step /usr/bin/step-cli /usr/local/bin/step
COPY --from=yq /usr/local/bin/yq /usr/local/bin/
COPY bin/* /usr/local/bin/
ENV PROTOC_NO_VENDOR=1
ENV PROTOC=/usr/local/bin/protoc
ENV PROTOC_INCLUDE=/usr/local/include

##
## Runtime
##

FROM docker.io/debian:bullseye as runtime
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update \
    && apt-get upgrade -y --autoremove \
    && apt-get install -y \
        apt-file \
        binutils-x86-64-linux-gnu \
        binutils-aarch64-linux-gnu \
        binutils-arm-linux-gnueabihf \
        clang \
        cmake \
        curl \
        dnsutils \
        file \
        g++-aarch64-linux-gnu \
        g++-arm-linux-gnueabihf \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        iproute2 \
        jo \
        jq \
        libc6-dev-arm64-cross \
        libc6-dev-armhf-cross \
        libssl-dev \
        locales \
        lsb-release \
        netcat \
        musl-tools \
        pkg-config \
        sudo \
        time \
        tshark \
        unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && (echo "LC_ALL=en_US.UTF-8" && echo "LANGUAGE=en_US.UTF-8") >/etc/default/locale
RUN groupadd --gid=1000 code \
    && useradd --create-home --uid=1000 --gid=1000 code \
    && echo "code ALL=(root) NOPASSWD:ALL" >/etc/sudoers.d/code \
    && chmod 0440 /etc/sudoers.d/code

# Copy node utilities first, because the bin directory include symlinks that we want to preserve.
COPY --from=node /usr/local/man/man1/node.1 /usr/local/man/man1/
COPY --from=node /usr/local/include/node /usr/local/include/node
COPY --from=node /opt/ /opt/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /usr/local/bin/ /usr/local/bin/

ENV GOPATH=/go
COPY --from=go /go/bin $GOPATH/bin
COPY --from=go /usr/local/go /usr/local/go
RUN find "$GOPATH" -type d -exec chmod 777 '{}' +
ENV PATH=/usr/local/go/bin:$GOPATH/bin:$PATH

ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
COPY --from=rust $CARGO_HOME $CARGO_HOME
COPY --from=rust $RUSTUP_HOME $RUSTUP_HOME
RUN find "$CARGO_HOME" "$RUSTUP_HOME" -type d -exec chmod 777 '{}' +
ENV PATH=$CARGO_HOME/bin:$PATH
RUN rustup component add rust-analysis rust-std
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
    CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
ENV CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER=arm-linux-gnueabihf-gcc \
    CC_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-gcc \
    CXX_armv7_unknown_linux_gnueabihf=arm-linux-gnueabihf-g++

COPY --from=tools /usr/local/bin/* /usr/local/bin/

COPY --from=protoc /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1
ENV PROTOC=/usr/local/bin/protoc
ENV PROTOC_INCLUDE=/usr/local/include

ENV DOCKER_BUILDKIT=1
RUN scurl https://raw.githubusercontent.com/microsoft/vscode-dev-containers/main/script-library/docker-debian.sh | bash -s \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ENV HOME=/home/code
ENV USER=code
USER code
ENTRYPOINT ["/usr/local/share/docker-init.sh"]
CMD ["sleep", "infinity"]
