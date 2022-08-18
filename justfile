# See https://just.systems/man/en

lint: md-lint sh-lint

##
## Devcontainer
##

devcontainer-build-mode := "load"
devcontainer-image := "ghcr.io/linkerd/dev"

devcontainer-build tag:
    #!/usr/bin/env bash
    set -euo pipefail
    for tgt in tools go rust runtime ; do
        just devcontainer-build-mode={{ devcontainer-build-mode }} \
            _devcontainer-build {{ tag }} "${tgt}"
    done

_devcontainer-build tag target='':
    docker buildx build .devcontainer \
        --progress=plain \
        --tag='{{ devcontainer-image }}:{{ tag }}{{ if target != "runtime" { "-" + target }  else { "" } }}' \
        --target='{{ target }}' \
        --{{ if devcontainer-build-mode == "push" { "push" } else { "load" } }}

##
## GitHub Actions
##

# Format actionlint output for Github Actions if running in CI.
_actionlint-fmt := if env_var_or_default("GITHUB_ACTIONS", "") != "true" { "" } else {
  '{{range $err := .}}::error file={{$err.Filepath}},line={{$err.Line}},col={{$err.Column}}::{{$err.Message}}%0A```%0A{{replace $err.Snippet "\\n" "%0A"}}%0A```\n{{end}}'
}

# Lints all GitHub Actions workflows
action-lint:
    actionlint \
        {{ if _actionlint-fmt != '' { "-format '" + _actionlint-fmt + "'" } else { "" } }} \
        */.github/workflows/*.yml

# Ensure all devcontainer versions are in sync
action-dev-check:
    action-dev-check
    git submodule foreach action-dev-check

##
## Other tools...
##

md-lint:
    markdownlint-cli2 '**/*.md' '!**/node_modules' '!**/target'

sh-lint:
    bin/shellcheck-all

##
## Git
##

# Display the git history minus Dependabot updates
history *paths='.':
    @-git log --oneline --graph --invert-grep --author="dependabot" -- {{ paths }}

# Display the history of Dependabot changes
history-dependabot *paths='.':
    @-git log --oneline --graph --author="dependabot" -- {{ paths }}

# vim: set ft=make :
