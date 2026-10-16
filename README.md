# photocraft-archlinux-pkg

Local pacman packages for [PhotoCraft](https://github.com/storytold/photocraft), built automatically by GitHub Actions for **every upstream tag release**.

Upstream is not on Arch Linux and ships no Arch package, so this repo repackages its official Linux release tarballs into `.pkg.tar.zst` files and assembles them into a pacman repository you can install from.

## How it works

- `.github/workflows/build.yml` triggers on `release: published` upstream, so a new `vX.Y.Z` release produces packages with no changes needed here.
- `workflow_dispatch` backfills existing tags and lets you pick architectures.
- One job per (tag × architecture) in an official `archlinux:base-devel` container; `aarch64`/`riscv64` run under QEMU.
- The tarball's sha256 is read from upstream's own `SHA256SUMS.txt` at build time, so every package is checksum-verified and any future tag works unchanged.
- Each architecture's packages are indexed with `repo-add` into a downloadable repository artifact.

### Repackaging metadata, compiled from source

Upstream publishes prebuilt release tarballs, but this repo ignores them and **compiles the workspace itself** with `cargo build --release --locked -p photocraft -p photocraft-cli`, matching upstream's own `packaging/linux/package.sh` targets and features.

Consequences worth knowing:

- **Toolchain**: Arch's `rust` package provides both `rustc` and `cargo` (1.99, covering the workspace's `rust-version = 1.95` and edition 2024).
- **Build deps**: `libpipewire` (headers + `.pc` for the `system_deps` probe in `pipewire-sys`, pulled in by `xcap`), `clang` (bindgen), `cmake` (`aws-lc-sys`), `wayland` (headers + `wayland-scanner`), `git` (pinned git dependencies on `craft-libs`).
- **Build cost**: the release profile uses `lto = "thin"` and `codegen-units = 1`, so a build peaks in memory and takes ~35 min. `-j2` plus stripping makepkg's automatic `-C debuginfo=2` keeps it inside a 4-core/16 GB runner.
- **Feature drift**: the `heif` (HEIC/HEIF) feature only exists from v0.5.0, so it is enabled only when the tag's manifest declares it.
- **Fonts**: upstream's optional `CRAFT_FONTS_DIR` is not used, so no extra fonts are embedded. The editor falls back to its built-in set.

## Installing

Download the `photocraft-arch-repo` artifact from a workflow run and unzip it. It contains one directory per architecture:

```
repo/x86_64/photocraft-0.9.0-1-x86_64.pkg.tar.zst
repo/x86_64/photocraft.db            # newest version only
repo/x86_64/photocraft-0.9.0-1.db    # one database per built version
repo/x86_64/photocraft-0.8.2-1.db
...
```

Add your architecture's directory to `/etc/pacman.conf`:

```ini
[photocraft]
SigLevel = Optional TrustAll
Server = file:///path/to/extracted/repo/x86_64
```

Then:

```bash
sudo pacman -Sy
sudo pacman -S photocraft
```

### Installing a specific version

`repo-add` replaces the entry for a package name when it sees a newer one, so a single database can only describe one version. Each version therefore gets its **own** database, named `photocraft-<version>-<pkgrel>.db`, while `photocraft.db` holds the newest. To pin a version, add an entry per database you want:

```ini
[photocraft-v0.8.2]
SigLevel = Optional TrustAll
Server = file:///path/to/extracted/repo/x86_64
```

```bash
sudo pacman -S photocraft-v0.8.2
```

Keep the extracted directory somewhere permanent (e.g. `/opt/photocraft-repo/x86_64`) so the `Server` paths stay valid.

## Runtime dependencies

The binaries declare only `glibc`, `libm` and `libgcc_s` as ELF `NEEDED` entries. Windowing and GPU libraries are `dlopen()`ed at runtime, so they cannot be detected automatically; they are declared as `optdepends`:

- **Wayland**: `wayland`, `libxkbcommon`
- **X11**: `libx11`, `libxcb`, `libx11-xcb`, `libxcursor`, `libxi`, `libxkbcommon`, `libxkbcommon-x11`
- **GPU**: `vulkan-icd-loader` + `mesa` (or `libglvnd` + EGL drivers)

winit loads `libxkbcommon-x11` on X11 and panics without it, so install that one if you run an X11 session.

## Notes

- Builds are verified against the tag's commit sha, not a tarball checksum: upstream publishes `SHA256SUMS.txt` for its release assets only, and GitHub's auto-generated source archives are not guaranteed byte-stable. `prepare()` clones the tag and checks the commit.
- `v0.1.1-rc.N` tags become `pkgver=0.1.1rc.N`; Arch forbids hyphens in `pkgver`, and this form still sorts before the final release.
- The supported range is **v0.9.0 and newer**. Older tags do build, but their `Cargo.toml` versions and license-file layout predate current upstream conventions (the rc tags still declare `0.1.0`, and pre-v0.2.0 ships no root license files), so they are not in the default set.
- A release build takes roughly 35 minutes per tag. Re-running a failed *index* job is cheap (`gh run rerun --failed`), since the build artifacts are reused.
- The container image is rolling (`archlinux:base-devel`); pin both `container:` entries to a dated tag if you need bit-reproducible output.
- The package bundles `photocraft-cli`, the headless converter, as `/usr/bin/photocraft-cli` alongside the GUI.
- `riscv64` and `aarch64` are selectable via the `arches` input, but run under QEMU and are far slower.