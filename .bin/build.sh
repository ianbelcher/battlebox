#!/usr/bin/env sh

# Shell 'strict' mode
set -ue

docker build --build-arg GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo dev)" --tag world .
