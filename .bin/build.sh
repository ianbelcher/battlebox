#!/usr/bin/env sh

# Shell 'strict' mode
set -ue

# CI passes GIT_SHA (its build container has no git); local builds derive it.
SHA="${GIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo dev)}"
docker build --build-arg GIT_SHA="$(echo "$SHA" | cut -c1-12)" --tag world .
