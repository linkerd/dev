version := ''
image := 'ghcr.io/linkerd/dev'
platform := 'linux/amd64,linux/arm64'
_tag :=  if version != '' { "--tag=" + image + ':' + version } else { "" }

k3s-image := 'docker.io/rancher/k3s'

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

export DOCKER_PROGRESS := env_var_or_default('DOCKER_PROGRESS', 'auto')

all: sync-k3s-images build

build *build_args='': && _list-if-load
    #!/usr/bin/env bash
    set -euo pipefail
    for tgt in {{ targets }} ; do
        just output='{{ output }}' \
             image='{{ image }}' \
             version='{{ version }}' \
             platform='{{ platform }}' \
            _target "$tgt" {{ build_args }}
    done

_list-if-load:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ '{{ load }}' = 'true' ] ; then
        just image='{{ image }}' \
             targets='{{ targets }}' \
             version='{{ version }}' \
             platform='{{ platform }}' \
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

# Fetch the latest version of k3s images and record their tags and digests.
sync-k3s-images:
    #!/usr/bin/env bash
    set -euo pipefail
    CHANNELS=$(just minimum-k8s='{{ minimum-k8s }}' _k3s-channels)
    DIGESTS=$(for tag in $(echo "$CHANNELS" | jq -r 'to_entries | .[].value' | sort -u) ; do
        jo key="$tag" value="$(just k3s-image='{{ k3s-image }}' _k3s-inspect "${tag}" | jq -r '.Digest')"
    done | jq -cs 'from_entries')
    jo name='{{ k3s-image }}' channels="$CHANNELS" digests="$DIGESTS" \
        | jq . > k3s-images.json
    jq . k3s-images.json

minimum-k8s := '20'

# Inspect a k3s image by tag
_k3s-inspect tag:
    skopeo inspect 'docker://{{ k3s-image }}:{{ tag }}'

# Fetch the latest tag for non-EOL channels.
_k3s-channels:
    #!/usr/bin/env bash
    set -euo pipefail
    scurl 'https://update.k3s.io/v1-release/channels' \
        | jq -cr '[.data[]
                | select(.type == "channel")
                | select(.id | test("^(.*-)?testing") | not)
                | (.latest | sub("\\+"; "-")) as $tag
                | ($tag | capture("^v1\\.(?<v>\\d+)\\.\\d+-.*") | .v | tonumber) as $version
                | select($version >= {{ minimum-k8s }})
                | {key:.id, value:$tag}
            ] | from_entries'

_target target='' *args='':
    @just \
        output='{{ output }}' \
        image='{{ image }}' \
        platform='{{ platform }}' \
        _build --target='{{ target }}' \
            {{ if version == '' { '' } else { '--tag=' + image + ':' + version + if target == 'devcontainer' { '' } else { '-' + target } } }} \
            {{ args }}

# Build the devcontainer image
_build *args='':
    docker buildx build . {{ _tag }} --pull \
        --platform='{{ platform }}' \
        --progress='{{ DOCKER_PROGRESS }}' \
        --output='{{ output }}' \
        {{ args }}


md-lint *patterns="'**/*.md' '!repos/**'":
    @bin/just-md lint {{ patterns }}
