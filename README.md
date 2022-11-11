# linkerd-dev

This repository contains utilities for managing the Linkerd development
environment, especially a [devcontainer](https://containers.dev/) configuration
that can be used

This repository is **NOT** intended to be used typical Linkerd development. This
repository includes submodules only for the purpose of validating and automating
dev tooling changes.

## `dev` images

The [Dockerfile] includes many targets. This can help caching when rebuilding
the dev images and, more importantly, it allows us to publish several images for
different uses:

- **tools** -- a variety of tools for testing and CI
- **go** -- build & test Go in development and CI
- **rust** -- build & test Rust in development and CI
- **rust-cross** -- build Rust for release in CI
- **runtime** -- interactive development (e.g. in Visual Studio Code)

The *runtime* image is tagged as `ghcr.io/linkerd/dev:vNN` and is expected to be
set in a `.devcontainer.json` file. For example:

```json
{
    "name": "linkerd-dev",
    "image": "ghcr.io/linkerd/dev:v33",
    "extensions": [
        "DavidAnson.vscode-markdownlint",
        "golang.go",
        "kokakiwi.vscode-just",
        "ms-kubernetes-tools.vscode-kubernetes-tools",
        "NathanRidley.autotrim",
        "rust-lang.rust-analyzer",
        "samverschueren.final-newline",
        "tamasfe.even-better-toml",
        "zxh404.vscode-proto3"
    ],
    "settings": {
        "go.lintTool": "golangci-lint"
    },
    "runArgs": [
        "--init",
        // Limit container memory usage.
        "--memory=12g",
        "--memory-swap=12g",
        // Use the host network so we can access k3d, etc.
        "--net=host"
    ],
    "overrideCommand": false,
    "remoteUser": "code",
    "mounts": [
        {
            "source": "/var/run/docker.sock",
            "target": "/var/run/docker-host.sock",
            "type": "bind"
        },
        {
            "source": "${localEnv:HOME}/.docker",
            "target": "/home/code/.docker",
            "type": "bind"
        }
    ]
}
```

### Building

Build a single target (e.g. while editing the Dockerfile):

```sh
:; just build --target=rust
```

Push all images:

```sh
:; just output='type=registry' image='ghcr.io/linkerd/dev:vNN' images
```

### Tools

This repository also includes additional tools in [bin/]. These scripts capture
some common build and testing tasks. Most of these scripts are implemented with
[`just`](https://just.systems/). Just is a tool for writing build and test
'recipes'. These recipes may be invoked in the course of development or from

- **just-dev** lints for Devcontainer configuration and GitHub Actions workflows
- **just-cargo** helpers for running cargo, especially in CI
- **just-k3d** helpers for interacting with k3d clusters used for testing
- **just-md** lints markdown in a repository
- **just-sh** lints shell scripts in a respository.
