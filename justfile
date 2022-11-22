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

build: && _list-if-load
   #!/usr/bin/env bash
    set -euo pipefail
    for tgt in {{ targets }} ; do
        just output='{{ output }}' \
             image='{{ image }}' \
             version='{{ version }}' \
            _target "$tgt"
    done

_list-if-load:
    #!/usr/bin/env bash
     set -euo pipefail
     if [ '{{ load }}' = 'true' ] ; then
          just image='{{ image }}' \
               targets='{{ targets }}' \
               version='{{ version }}' \
              list
     fi

list:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z '{{ version }}' ]; then
        echo "Usage: just version=<version> list" >&2
        exit 64
    fi
    for tgt in {{ targets }} ; do
        if [ "$tgt" == "devcontainer" ]; then
            docker image ls {{ image }}:{{ version }} | sed 1d
        else
            docker image ls {{ image }}:{{ version }}-$tgt | sed 1d
        fi
    done

_target target='':
    @just output='{{ output }}' image='{{ image }}' _build --target='{{ target }}' \
        {{ if version == '' { '' } else { '--tag=' + image + ':' + version + if target == 'devcontainer' { '' } else { '-' + target } } }}

# Build the devcontainer image
_build *args='':
    docker buildx build . {{ _tag }} --pull \
        --progress='{{ DOCKER_PROGRESS }}' \
        --output='{{ output }}' \
        {{ args }}


md-lint *patterns="'**/*.md' '!repos/**'":
    @bin/just-md lint {{ patterns }}
