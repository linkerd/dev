##
## Base
##

FROM docker.io/debian:bullseye-slim as base
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get upgrade -y --autoremove \
    && apt-get install -y \
        curl \
        file \
        git \
        jo \
        jq \
        time \
        unzip \
        xz-utils \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --link bin/scurl /usr/local/bin/

ARG YQ_VERSION=v4.25.1
RUN url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" ; \
    scurl -o /usr/local/bin/yq "$url" && chmod +x /usr/local/bin/yq

FROM base as just
ARG JUST_VERSION=1.8.0
RUN url="https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin just

##
## Kubernetes tools
##

FROM just as k8s

ARG KUBECTL_VERSION=v1.25.3
RUN url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" ; \
    scurl -o /usr/local/bin/kubectl "$url" && chmod +x /usr/local/bin/kubectl

ARG K3D_VERSION=v5.4.6
RUN url="https://raw.githubusercontent.com/rancher/k3d/$K3D_VERSION/install.sh" ; \
    scurl "$url" | USE_SUDO=false K3D_INSTALL_DIR=/usr/local/bin bash
COPY --link bin/just-k3d /usr/local/bin/just-k3d

ARG HELM_VERSION=v3.10.1
RUN url="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - --strip-components=1 -C /usr/local/bin linux-amd64/helm

ARG HELM_DOCS_VERSION=v1.11.0
RUN url="https://github.com/norwoodj/helm-docs/releases/download/$HELM_DOCS_VERSION/helm-docs_${HELM_DOCS_VERSION#v}_Linux_x86_64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin helm-docs

FROM base as step
RUN scurl -O https://dl.step.sm/gh-release/cli/docs-cli-install/v0.21.0/step-cli_0.21.0_amd64.deb \
    && dpkg -i step-cli_0.21.0_amd64.deb

##
## Action: Tools for linting repo actions
##

FROM k8s as action

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get upgrade -y --autoremove \
    && apt-get install -y gnupg \
    && ( . /etc/os-release \
        && scurl https://download.docker.com/linux/${ID}/gpg | gpg --dearmor > /usr/share/keyrings/docker-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list ) \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG SHELLCHECK_VERSION=v0.8.0
RUN url="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" ; \
    scurl "$url" | tar xJvf - --strip-components=1 -C /usr/local/bin "shellcheck-${SHELLCHECK_VERSION}/shellcheck"
COPY --link bin/just-sh /usr/local/bin/

ARG J5J_VERSION=v0.2.0
RUN url="https://github.com/olix0r/j5j/releases/download/${J5J_VERSION}/j5j-${J5J_VERSION}-x86_64-unknown-linux-musl.tar.gz" ; \
    scurl "$url" | tar zvxf - -C /usr/local/bin j5j

ARG ACTIONLINT_VERSION=v1.6.21
RUN url="https://github.com/rhysd/actionlint/releases/download/${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION#v}_linux_amd64.tar.gz" ; \
    scurl "$url" | tar xzvf - -C /usr/local/bin actionlint
COPY --link bin/action-* bin/just-dev /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/just-dev"]

##
## Protobuf
##

FROM base as protobuf
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
RUN rustup target add x86_64-unknown-linux-gnu
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get upgrade -y --autoremove \
    && apt-get install -y \
        clang \
        cmake \
        curl \
        file \
        git \
        jo \
        jq \
        libssl-dev \
        llvm \
        pkg-config \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY --link --from=cargo-action-fmt /usr/local/bin/cargo-action-fmt /usr/local/cargo/bin/
COPY --link --from=cargo-deny /usr/local/bin/cargo-deny /usr/local/cargo/bin/
COPY --link --from=cargo-nextest /usr/local/bin/cargo-nextest /usr/local/cargo/bin/
COPY --link --from=cargo-tarpaulin /usr/local/bin/cargo-tarpaulin /usr/local/cargo/bin/
COPY --link --from=checksec /usr/local/bin/checksec /usr/local/bin/checksec
COPY --link --from=just /usr/local/bin/just* /usr/local/bin/
COPY --link --from=protobuf /usr/local/bin/protoc /usr/local/bin/
COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1
ENV PROTOC=/usr/local/bin/protoc
ENV PROTOC_INCLUDE=/usr/local/include
COPY --link bin/scurl /usr/local/bin/scurl
COPY --link bin/just-cargo /usr/local/bin/just-cargo
ENV USER=root
ENTRYPOINT ["/usr/local/bin/just-cargo"]

FROM rust as rust-musl
RUN rustup target add \
        aarch64-unknown-linux-musl \
        armv7-unknown-linux-musleabihf \
        x86_64-unknown-linux-musl
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get upgrade -y --autoremove \
    && apt-get install -y \
        g++-aarch64-linux-gnu \
        g++-arm-linux-gnueabihf \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        libc6-dev-arm64-cross \
        libc6-dev-armhf-cross \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

##
## Go image
##

FROM docker.io/golang:1.18.7 as go
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get upgrade -y --autoremove \
    && apt-get install -y \
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
COPY --link bin/scurl /usr/local/bin/scurl
COPY --link --from=just /usr/local/bin/just /usr/local/bin/
COPY --link bin/just-cargo /usr/local/bin/
COPY --link --from=protobuf /usr/local/bin/protoc /usr/local/bin/
COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1
ENV PROTOC=/usr/local/bin/protoc
ENV PROTOC_INCLUDE=/usr/local/include

##
## Runtime
##

FROM docker.io/debian:bullseye as runtime
RUN export DEBIAN_FRONTEND=noninteractive ; \
    apt-get update && apt-get upgrade -y --autoremove \
    && apt-get install -y \
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
    && curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
ARG MARKDOWNLINT_VERSION=0.5.1
RUN npm install "markdownlint-cli2@${MARKDOWNLINT_VERSION}" --global

COPY --link --from=action /usr/local/bin/* /usr/local/bin/
COPY --link --from=checksec /usr/local/bin/checksec /usr/local/bin/checksec
COPY --link --from=ghcr.io/olix0r/hokay:v0.2.2 /hokay /usr/local/bin/
COPY --link --from=just /usr/local/bin/just /usr/local/bin/
COPY --link --from=k8s /usr/local/bin/* /usr/local/bin/
COPY --link --from=step /usr/bin/step-cli /usr/local/bin/step
COPY --link bin/just-md /usr/local/bin/

ENV GOPATH=/go
COPY --link --from=go /go/bin $GOPATH/bin
COPY --link --from=go /usr/local/go /usr/local/go
RUN find "$GOPATH" -type d -exec chmod 777 '{}' +
ENV PATH=/usr/local/go/bin:$GOPATH/bin:$PATH

ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
COPY --link --from=rust $CARGO_HOME $CARGO_HOME
COPY --link --from=rust $RUSTUP_HOME $RUSTUP_HOME
COPY --link --from=rust /usr/local/bin/just-cargo /usr/local/bin/
RUN find "$CARGO_HOME" "$RUSTUP_HOME" -type d -exec chmod 777 '{}' +
ENV PATH=$CARGO_HOME/bin:$PATH

COPY --link --from=protobuf /usr/local/include/google /usr/local/include/google
ENV PROTOC_NO_VENDOR=1
ENV PROTOC=/usr/local/bin/protoc
ENV PROTOC_INCLUDE=/usr/local/include

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

ENV HOME=/home/code
ENV USER=code
USER code
ENTRYPOINT ["/usr/local/share/docker-init.sh"]
CMD ["sleep", "infinity"]
