# ghostty-debian

> ⚠️ **Warning**: I'm still testing this out for my own usage, but so far so good.
> In the long term would like to expand this to Debian stable, testing and experimental - but first time building out this kind of packaging infra, so taking things step by step and dogfooding my own tools in the process.

Builds a release `.deb` package of [Ghostty](https://ghostty.org) for Debian
stable and testing, using Docker so you don't need Zig or Ghostty's build
dependencies installed on your own machine. Ghostty isn't packaged in Debian,
so this compiles it from the official release source tarball following the
[upstream build instructions](https://ghostty.org/docs/install/build).

## Prerequisites

- Docker with BuildKit (Docker 23+ has this by default).

## Usage

```sh
DOCKER_BUILDKIT=1 docker build --output=build .
```

This produces `build/ghostty_<version>_<arch>.deb`, built against Debian
testing by default. Install it with:

```sh
sudo apt install ./build/ghostty_*.deb
```

To build against Debian stable instead:

```sh
DOCKER_BUILDKIT=1 docker build --output=build --build-arg DEBIAN_SUITE=stable .
```

## How it works

The `Dockerfile` is a multi-stage build:

1. **`builder`** (`debian:${DEBIAN_SUITE}`, `testing` by default) installs
   Ghostty's build dependencies (`libgtk-4-dev`, `libgtk4-layer-shell-dev`,
   `libadwaita-1-dev`, `gettext`, `libxml2-utils`), downloads the pinned Zig
   compiler release, downloads and extracts the Ghostty source tarball, and
   runs `zig build -Doptimize=ReleaseFast` into a staging root. It then
   assembles a Debian control file — with `Depends` computed via
   `dpkg-shlibdeps` against the built binary, so it tracks whatever library
   versions that specific suite actually ships — and packages everything
   with `dpkg-deb`. Building stable and testing separately (rather than one
   build "for both") matters: each `.deb`'s minimum library versions are only
   correct for the suite it was actually linked against.
2. **`export`** (`scratch`) just holds the resulting `.deb`. Because it's the
   final stage, `docker build --output=build .` copies it straight into
   `./build/` on the host — no `docker run` or volume mount required.

## Versioning

Package versions look like `1.3.1-1~trixie` / `1.3.1-1~forky`:

- `1.3.1` is the upstream Ghostty version (`GHOSTTY_VERSION`).
- `1` is the Debian package revision (`PKG_REVISION`) — bump this (and reset
  it to `1` whenever `GHOSTTY_VERSION` changes) to force a new release
  without a new upstream Ghostty version, e.g. after a dependency-only
  rebuild.
- `~trixie`/`~forky` is the actual Debian codename the package was built
  against (read from `/etc/os-release` inside the build, not hardcoded) —
  the same tilde-suffix convention used by Debian backports and Ubuntu PPAs
  for suite-specific builds of one upstream version.

## Bumping versions

The Ghostty and Zig versions are build args at the top of the `Dockerfile`:

```dockerfile
ARG GHOSTTY_VERSION=1.3.1
ARG ZIG_VERSION=0.15.2
```

Ghostty pins a specific Zig version per release (see the
[build docs](https://ghostty.org/docs/install/build) for the current
mapping) — when bumping `GHOSTTY_VERSION`, check whether `ZIG_VERSION` needs
to change too, or the build will fail. You can also override any of the build
args at build time without editing the file:

```sh
DOCKER_BUILDKIT=1 docker build --output=build \
  --build-arg GHOSTTY_VERSION=1.3.1 \
  --build-arg ZIG_VERSION=0.15.2 \
  --build-arg DEBIAN_SUITE=stable \
  --build-arg PKG_REVISION=2 \
  .
```

## GitHub Actions

Two workflows live in `.github/workflows/`:

- **`build-release.yml`** — manually triggered (Actions tab, or
  `gh workflow run build-release.yml -f ghostty_version=1.3.1 -f pkg_revision=1`).
  Builds the `.deb` for both `stable` and `testing` in parallel, then
  creates (or updates, if re-run for the same version/revision) a GitHub
  Release tagged `v<ghostty_version>-<pkg_revision>` with both `.deb` files
  attached.
- **`check-ghostty-version.yml`** — runs weekly (and can be triggered
  manually). Compares the latest `ghostty-org/ghostty` release to the
  version pinned in `Dockerfile` and files a tracking issue if they differ.
  It never bumps versions or builds anything itself — bumping also means
  checking whether `ZIG_VERSION` needs to change, which needs a human to
  check the build docs.
