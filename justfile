version := ''
image := 'ghcr.io/linkerd/dev'
_tag :=  if version != '' { "--tag=" + image + ':' + version } else { "" }

targets := 'go rust rust-musl tools devcontainer'

load := 'false'
push := 'false'
output := if push == 'true' {
        'type=registry'
    } else if load == 'true' {
        'type=docker'
    } else {
        'type=image'
    }

export DOCKER_PROGRESS := 'auto'

build:
   #!/usr/bin/env bash
    set -euo pipefail
    for tgt in {{ targets }} ; do
        just output='{{ output }}' \
             image='{{ image }}' \
             version='{{ version }}' \
            _target "$tgt"
    done

_target target='':
    @just output='{{ output }}' image='{{ image }}' _build --target='{{ target }}' \
        {{ if version == '' { '' } else { '--tag=' + image + ':' + version + if target == 'devcontainer' { '' } else { '-' + target } } }}

# Build the devcontainer image
_build *args='':
    docker buildx build . {{ _tag }} \
        --progress='{{ DOCKER_PROGRESS }}' \
        --output='{{ output }}' \
        {{ args }}

md-lint *patterns="'**/*.md' '!repos/**'":
    @bin/just-md lint {{ patterns }}
