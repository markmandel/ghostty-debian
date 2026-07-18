# syntax=docker/dockerfile:1

# Copyright 2026 Mark Mandel
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Builds a release .deb package of Ghostty (https://ghostty.org) for Debian
# stable or testing. Follows the official build instructions at
# https://ghostty.org/docs/install/build
#
# Usage:
#   DOCKER_BUILDKIT=1 docker build --output=build .
#   sudo apt install ./build/ghostty_*.deb
#
# Build against Debian stable instead of testing, and/or bump the package
# revision for a rebuild-only release:
#   DOCKER_BUILDKIT=1 docker build --output=build \
#     --build-arg DEBIAN_SUITE=stable \
#     --build-arg PKG_REVISION=2 \
#     .

ARG GHOSTTY_VERSION=1.3.1
# Must match the Zig version required by GHOSTTY_VERSION, per
# https://ghostty.org/docs/install/build
ARG ZIG_VERSION=0.15.2
ARG MAINTAINER="Mark Mandel <mark@compoundtheory.com>"
# Debian suite to build against: stable or testing.
ARG DEBIAN_SUITE=testing
# Debian package revision. Bump this (and reset it to 1 whenever
# GHOSTTY_VERSION changes) to force a new release without a new upstream
# Ghostty version, e.g. after a dependency-only rebuild.
ARG PKG_REVISION=1

FROM debian:${DEBIAN_SUITE} AS builder
ARG GHOSTTY_VERSION
ARG ZIG_VERSION
ARG MAINTAINER
ARG DEBIAN_SUITE
ARG PKG_REVISION

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    xz-utils \
    pkg-config \
    libgtk-4-dev \
    libgtk4-layer-shell-dev \
    libadwaita-1-dev \
    gettext \
    libxml2-utils \
    dpkg-dev \
    && rm -rf /var/lib/apt/lists/*

# Install the exact Zig version Ghostty requires (static binary release).
RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in \
         amd64) ZIG_ARCH=x86_64 ;; \
         arm64) ZIG_ARCH=aarch64 ;; \
         *) echo "unsupported architecture: $ARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/zig.tar.xz \
         "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz
ENV PATH="/opt/zig:${PATH}"

# Fetch the release source tarball (git clones are discouraged upstream).
RUN mkdir -p /src \
    && curl -fsSL -o /tmp/ghostty.tar.gz \
         "https://release.files.ghostty.org/${GHOSTTY_VERSION}/ghostty-${GHOSTTY_VERSION}.tar.gz" \
    && tar -xzf /tmp/ghostty.tar.gz -C /src \
    && rm /tmp/ghostty.tar.gz

WORKDIR /src/ghostty-${GHOSTTY_VERSION}

# Build straight into a staging root laid out for packaging.
RUN zig build -Doptimize=ReleaseFast -p "/pkg/ghostty-${GHOSTTY_VERSION}/usr"

# Assemble the .deb control metadata and build the package.
RUN set -eu; \
    PKGROOT="/pkg/ghostty-${GHOSTTY_VERSION}"; \
    ARCH="$(dpkg --print-architecture)"; \
    CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-$DEBIAN_SUITE}")"; \
    PKG_VERSION="${GHOSTTY_VERSION}-${PKG_REVISION}~${CODENAME}"; \
    mkdir -p "${PKGROOT}/DEBIAN"; \
    rm -f "${PKGROOT}/usr/share/terminfo/g/ghostty"; \
    mkdir -p /tmp/shlibs/debian; \
    printf 'Source: ghostty\nPackage: ghostty\nArchitecture: %s\n' "${ARCH}" \
      > /tmp/shlibs/debian/control; \
    DEPENDS="$(cd /tmp/shlibs && dpkg-shlibdeps -O "${PKGROOT}/usr/bin/ghostty" \
      | sed -n 's/^shlibs:Depends=//p')"; \
    { \
      echo "Package: ghostty"; \
      echo "Version: ${PKG_VERSION}"; \
      echo "Section: utils"; \
      echo "Priority: optional"; \
      echo "Architecture: ${ARCH}"; \
      echo "Maintainer: ${MAINTAINER}"; \
      echo "Depends: ${DEPENDS}"; \
      echo "Recommends: ncurses-term"; \
      echo "Homepage: https://ghostty.org"; \
      echo "Vcs-Browser: https://github.com/markmandel/ghostty-debian"; \
      echo "Vcs-Git: https://github.com/markmandel/ghostty-debian.git"; \
      echo "Description: Fast, native, GPU-accelerated terminal emulator"; \
      echo " Ghostty is a terminal emulator that differentiates itself from other"; \
      echo " terminal emulators in a few key ways: fast, feature-rich, and native."; \
      echo " This build was compiled from the official release source tarball"; \
      echo " (ReleaseFast) and packaged for Debian ${CODENAME}."; \
    } > "${PKGROOT}/DEBIAN/control"; \
    mkdir -p /out; \
    dpkg-deb --build --root-owner-group "${PKGROOT}" \
      "/out/ghostty_${PKG_VERSION}_${ARCH}.deb"

FROM scratch AS export
COPY --from=builder /out/*.deb /
