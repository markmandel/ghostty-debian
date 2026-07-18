# ghostty-debian

Builds a release `.deb` package of [Ghostty](https://ghostty.org) for Debian
testing, using Docker so you don't need Zig or Ghostty's build dependencies
installed on your own machine. Ghostty isn't packaged in Debian, so this
compiles it from the official release source tarball following the
[upstream build instructions](https://ghostty.org/docs/install/build).

## Prerequisites

- Docker with BuildKit (Docker 23+ has this by default).

## Usage

```sh
DOCKER_BUILDKIT=1 docker build --output=build .
```

This produces `build/ghostty_<version>_<arch>.deb`. Install it with:

```sh
sudo apt install ./build/ghostty_*.deb
```

## How it works

The `Dockerfile` is a multi-stage build:

1. **`builder`** (`debian:testing`) installs Ghostty's build dependencies
   (`libgtk-4-dev`, `libgtk4-layer-shell-dev`, `libadwaita-1-dev`, `gettext`,
   `libxml2-utils`), downloads the pinned Zig compiler release, downloads and
   extracts the Ghostty source tarball, and runs
   `zig build -Doptimize=ReleaseFast` into a staging root. It then assembles a
   Debian control file — with `Depends` computed via `dpkg-shlibdeps` against
   the built binary, so it tracks whatever library versions Debian testing
   actually ships — and packages everything with `dpkg-deb`.
2. **`export`** (`scratch`) just holds the resulting `.deb`. Because it's the
   final stage, `docker build --output=build .` copies it straight into
   `./build/` on the host — no `docker run` or volume mount required.

## Bumping versions

The Ghostty and Zig versions are build args at the top of the `Dockerfile`:

```dockerfile
ARG GHOSTTY_VERSION=1.3.1
ARG ZIG_VERSION=0.15.2
```

Ghostty pins a specific Zig version per release (see the
[build docs](https://ghostty.org/docs/install/build) for the current
mapping) — when bumping `GHOSTTY_VERSION`, check whether `ZIG_VERSION` needs
to change too, or the build will fail. You can also override either at build
time without editing the file:

```sh
DOCKER_BUILDKIT=1 docker build --output=build \
  --build-arg GHOSTTY_VERSION=1.3.1 \
  --build-arg ZIG_VERSION=0.15.2 \
  .
```
