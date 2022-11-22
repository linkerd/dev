##
## Base
##

# scurl is a curl wrapper that enforces use of HTTPS with TLSv1.3.
FROM docker.io/library/debian:bullseye-slim as scurl
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get install -y \
        curl \
        unzip \
        xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --link bin/scurl /usr/local/bin/

##
## Scripting tools
##

FROM docker.io/library/debian:bullseye-slim as jojq
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get install -y jo jq \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# j5j Turns JSON5 into plain old JSON (i.e. to be processed by jq).
FROM scurl as j5j
ARG J5J_VERSION=v0.2.0
RUN url="https://github.com/olix0r/j5j/releases/download/${J5J_VERSION}/j5j-${J5J_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin j5j

# just runs build/test recipes. Like make but a bit mroe ergonomic.
FROM scurl as just
ARG JUST_VERSION=1.8.0
RUN url="https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin just

# yq is kind of like jq, but for YAML.
FROM scurl as yq
ARG YQ_VERSION=v4.25.1
RUN url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" ; \
    scurl -o /usr/local/bin/yq "$url" && chmod +x /usr/local/bin/yq

FROM scratch as tools-script
COPY --link --from=j5j /usr/local/bin/j5j /
COPY --link --from=jojq /usr/bin/jo /usr/bin/jq /
COPY --link --from=just /usr/local/bin/just /
COPY --link --from=scurl /usr/local/bin/scurl /
COPY --link --from=yq /usr/local/bin/yq /

##
## Kubernetes tools
##

# helm templates kubernetes manifests.
FROM scurl as helm
ARG HELM_VERSION=v3.10.1
RUN url="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - --strip-components=1 -C /usr/local/bin linux-amd64/helm

# helm-docs generates documentation from helm charts.
FROM scurl as helm-docs
ARG HELM_DOCS_VERSION=v1.11.0
RUN url="https://github.com/norwoodj/helm-docs/releases/download/$HELM_DOCS_VERSION/helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin helm-docs

# kubectl controls kubernetes clusters.
FROM scurl as kubectl
ARG KUBECTL_VERSION=v1.25.3
RUN url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" ; \
    scurl -o /usr/local/bin/kubectl "$url" && chmod +x /usr/local/bin/kubectl

# k3d runs kubernetes clusters in docker.
FROM scurl as k3d
ARG K3D_VERSION=v5.4.6
RUN url="https://raw.githubusercontent.com/rancher/k3d/$K3D_VERSION/install.sh" ; \
    scurl "$url" | USE_SUDO=false K3D_INSTALL_DIR=/usr/local/bin bash
COPY --link bin/just-k3d /usr/local/bin/just-k3d

# step is a tool for managing certificates.
FROM scurl as step
ARG STEP_VERSION=v0.21.0
RUN scurl -O "https://dl.step.sm/gh-release/cli/docs-cli-install/${STEP_VERSION}/step-cli_${STEP_VERSION#v}_amd64.deb" \
    && dpkg -i "step-cli_${STEP_VERSION#v}_amd64.deb" \
    && rm "step-cli_${STEP_VERSION#v}_amd64.deb"

FROM scratch as tools-k8s
COPY --link --from=helm /usr/local/bin/helm /
COPY --link --from=helm-docs /usr/local/bin/helm-docs /
COPY --link --from=k3d /usr/local/bin/k3d /usr/local/bin/just-k3d /
COPY --link --from=kubectl /usr/local/bin/kubectl /
COPY --link --from=step /usr/bin/step-cli /

##
## Linting tools
##

# actionlint lints github actions workflows.
FROM scurl as actionlint
ARG ACTIONLINT_VERSION=v1.6.21
RUN url="https://github.com/rhysd/actionlint/releases/download/${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION#v}_linux_amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin actionlint

# checksec checks binaries for security issues.
FROM scurl as checksec
ARG CHECKSEC_VERSION=2.5.0
RUN url="https://raw.githubusercontent.com/slimm609/checksec.sh/${CHECKSEC_VERSION}/checksec" ; \
    scurl -o /usr/local/bin/checksec "$url" && chmod 755 /usr/local/bin/checksec

# shellcheck lints shell scripts.
FROM scurl as shellcheck
ARG SHELLCHECK_VERSION=v0.8.0
RUN url="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" ; \
    scurl "$url" | tar xJvf - --strip-components=1 -C /usr/local/bin "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
COPY --link bin/just-sh /usr/local/bin/

# taplo lints and formats toml files.
FROM scurl as taplo
ARG TAPLO_VERSION=v0.8.0
RUN url="https://github.com/tamasfe/taplo/releases/download/${TAPLO_VERSION#v}/taplo-linux-x86_64.gz" ; \
    scurl "$url" | gunzip >/usr/local/bin/taplo \
    && chmod 755 /usr/local/bin/taplo

FROM scratch as tools-lint
COPY --link --from=actionlint /usr/local/bin/actionlint /
COPY --link --from=checksec /usr/local/bin/checksec /
COPY --link --from=shellcheck /usr/local/bin/shellcheck /
COPY --link --from=taplo /usr/local/bin/taplo /
COPY --link bin/action-* bin/just-dev bin/just-sh /

##
## Protobuf
##

FROM scurl as protobuf
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

# cargo-action-fmt formats `cargo build` JSON output to GithubActions annotations.
FROM scurl as cargo-action-fmt
ARG CARGO_ACTION_FMT_VERSION=1.0.2
RUN url="https://github.com/olix0r/cargo-action-fmt/releases/download/release%2Fv${CARGO_ACTION_FMT_VERSION}/cargo-action-fmt-x86_64-unknown-linux-gnu" ; \
    scurl -o /usr/local/bin/cargo-action-fmt "$url" && chmod +x /usr/local/bin/cargo-action-fmt

# cargo-deny checks cargo dependencies for licensing and RUSTSEC security issues.
FROM scurl as cargo-deny
ARG CARGO_DENY_VERSION=0.12.2
RUN url="https://github.com/EmbarkStudios/cargo-deny/releases/download/${CARGO_DENY_VERSION}/cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - --strip-components=1 -C /usr/local/bin "cargo-deny-${CARGO_DENY_VERSION}-x86_64-unknown-linux-musl/cargo-deny"

# cargo-nextest is a nicer test runner.
FROM scurl as cargo-nextest
ARG NEXTEST_VERSION=0.9.42
RUN url="https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-${NEXTEST_VERSION}/cargo-nextest-${NEXTEST_VERSION}-x86_64-unknown-linux-gnu.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin cargo-nextest

# cargo-taraulin is a code coverage tool.
FROM scurl as cargo-tarpaulin
ARG CARGO_TARPAULIN_VERSION=0.22.0
RUN url="https://github.com/xd009642/tarpaulin/releases/download/${CARGO_TARPAULIN_VERSION}/cargo-tarpaulin-${CARGO_TARPAULIN_VERSION}-travis.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin cargo-tarpaulin

FROM scratch as tools-rust
COPY --link --from=cargo-action-fmt /usr/local/bin/cargo-action-fmt /
COPY --link --from=cargo-deny /usr/local/bin/cargo-deny /
COPY --link --from=cargo-nextest /usr/local/bin/cargo-nextest /
COPY --link --from=cargo-tarpaulin /usr/local/bin/cargo-tarpaulin /
COPY --link bin/just-cargo /

##
## Go tools
##

FROM docker.io/library/golang:1.18.7 as go-delve
RUN go install github.com/go-delve/delve/cmd/dlv@latest
RUN strip /go/bin/dlv

FROM docker.io/library/golang:1.18.7 as go-impl
RUN go install github.com/josharian/impl@latest

FROM docker.io/library/golang:1.18.7 as go-outline
RUN go install github.com/ramya-rao-a/go-outline@latest
RUN strip /go/bin/go-outline

FROM docker.io/library/golang:1.18.7 as go-protoc
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28.1
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2
RUN strip /go/bin/protoc-gen-go /go/bin/protoc-gen-go-grpc

FROM docker.io/library/golang:1.18.7 as golangci-lint
RUN go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
RUN strip /go/bin/golangci-lint

FROM docker.io/library/golang:1.18.7 as gomodifytags
RUN go install github.com/fatih/gomodifytags@latest
RUN strip /go/bin/gomodifytags

FROM docker.io/library/golang:1.18.7 as gopkgs
RUN go install github.com/uudashr/gopkgs/v2/cmd/gopkgs@latest
RUN strip /go/bin/gopkgs

FROM docker.io/library/golang:1.18.7 as goplay
RUN go install github.com/haya14busa/goplay/cmd/goplay@latest
RUN strip /go/bin/goplay

FROM docker.io/library/golang:1.18.7 as gopls
RUN go install golang.org/x/tools/gopls@latest
RUN strip /go/bin/gopls

FROM docker.io/library/golang:1.18.7 as gotests
RUN go install github.com/cweill/gotests/gotests@latest
RUN strip /go/bin/gotests

FROM docker.io/library/golang:1.18.7 as gotestsum
RUN go install gotest.tools/gotestsum@v0.4.2
RUN strip /go/bin/gotestsum

FROM scratch as tools-go
COPY --link --from=go-delve /go/bin/dlv /
COPY --link --from=go-impl /go/bin/impl /
COPY --link --from=go-outline /go/bin/go-outline /
COPY --link --from=go-protoc /go/bin/protoc-gen-* /
COPY --link --from=golangci-lint /go/bin/golangci-lint /
COPY --link --from=gomodifytags /go/bin/gomodifytags /
COPY --link --from=goplay /go/bin/goplay /
COPY --link --from=gopls /go/bin/gopls /
COPY --link --from=gopkgs /go/bin/gopkgs /
COPY --link --from=gotests /go/bin/gotests /
COPY --link --from=gotestsum /go/bin/gotestsum /

# Networking utilities
FROM scratch as tools-net
COPY --link --from=ghcr.io/olix0r/hokay:v0.2.2 /hokay /

##
## Tools (for CI)
##

FROM scratch as tools
COPY --from=tools-go /* /
COPY --from=tools-k8s /* /
COPY --from=tools-lint /* /
COPY --from=tools-net /* /
COPY --from=tools-rust /* /
COPY --from=tools-script /* /

##
## Base images
##

FROM docker.io/library/golang:1.18.7 as go
COPY --link --from=tools-script /* /usr/local/bin/
COPY --link --from=tools-go /* /usr/local/bin/
COPY --link --from=protobuf /usr/local/bin/protoc /usr/local/bin/
COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1 \
    PROTOC=/usr/local/bin/protoc \
    PROTOC_INCLUDE=/usr/local/include

FROM docker.io/rust:1.64.0-slim-bullseye as rust
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get install -y \
        clang \
        cmake \
        git \
        llvm \
        pkg-config \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN rustup component add clippy rustfmt
COPY --link --from=tools-script /* /usr/local/bin/
COPY --link --from=tools-rust /* /usr/local/bin/
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
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get install -y \
        g++-aarch64-linux-gnu \
        g++-arm-linux-gnueabihf \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        libc6-dev-arm64-cross \
        libc6-dev-armhf-cross \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

##
## Devcontainer
##

FROM docker.io/library/debian:bullseye as devcontainer
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get install -y \
        clang \
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
        llvm \
        netcat \
        pkg-config \
        sudo \
        time \
        tshark \
        unzip \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --link --from=tools /* /usr/local/bin/

ARG MARKDOWNLINT_VERSION=0.5.1
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN npm install "markdownlint-cli2@${MARKDOWNLINT_VERSION}" --global
COPY --link bin/just-md /usr/local/bin/

COPY --link --from=go /usr/local/go /usr/local/go
ENV PATH=/usr/local/go/bin:$PATH

ENV RUSTUP_HOME=/usr/local/rustup
COPY --link --from=rust $RUSTUP_HOME $RUSTUP_HOME

COPY --link --from=protobuf /usr/local/bin/protoc /usr/local/bin/protoc
COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1 \
    PROTOC=/usr/local/bin/protoc \
    PROTOC_INCLUDE=/usr/local/include

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && (echo "LC_ALL=en_US.UTF-8" && echo "LANGUAGE=en_US.UTF-8") >/etc/default/locale
RUN groupadd --gid=1000 code \
    && useradd --create-home --uid=1000 --gid=1000 code \
    && echo "code ALL=(root) NOPASSWD:ALL" >/etc/sudoers.d/code \
    && chmod 0440 /etc/sudoers.d/code

RUN scurl https://raw.githubusercontent.com/microsoft/vscode-dev-containers/main/script-library/docker-debian.sh | bash -s \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV DOCKER_BUILDKIT=1

ENV HOME=/home/code \
    USER=code
USER code

ENV CARGO_HOME="$HOME/.cargo"
RUN mkdir "$CARGO_HOME"

ENV GOPATH="$HOME/go"
RUN mkdir -p "$GOPATH/go"
ENV PATH="$GOPATH/bin:$PATH"

ENTRYPOINT ["/usr/local/share/docker-init.sh"]
CMD ["sleep", "infinity"]
