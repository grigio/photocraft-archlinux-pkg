# photocraft-archlinux-pkg

Local pacman packages for [PhotoCraft](https://github.com/storytold/photocraft), built automatically by GitHub Actions for **every upstream tag release**.

Upstream is not on Arch Linux and ships no Arch package, so this repo repackages its official Linux release tarballs into `.pkg.tar.zst` files and assembles them into a pacman repository you can install from.

## How it works

- `.github/workflows/build.yml` triggers on `release: published` upstream, so a new `vX.Y.Z` release produces packages with no changes needed here.
- `workflow_dispatch` backfills existing tags and lets you pick architectures.
- One job per (tag × architecture) in an official `archlinux:base-devel` container; `aarch64`/`riscv64` run under QEMU.
- The tarball's sha256 is read from upstream's own `SHA256SUMS.txt` at build time, so every package is checksum-verified and any future tag works unchanged.
- Each architecture's packages are indexed with `repo-add` into a downloadable repository artifact.

### Repackaging, not building from source

Upstream publishes prebuilt `photocraft-<ver>-linux-<arch>.tar.gz` for every tag (x86_64 and aarch64 since v0.1.0, riscv64 since v0.7.0), so CI repackages them instead of compiling the Rust workspace. This keeps runs fast and reproducible. The consequence is the usual one for binary repackaging: **the packages are tied to the glibc the binaries were compiled against**, which upstream currently pins at 2.35. Fine on any rolling Arch install.

Layout of the upstream tarball already matches Arch's prefix tree, so `package()` is a straight `install`.

## Installing

Download the `photocraft-arch-repo` artifact from a workflow run and unzip it. It contains one directory per architecture:

```
repo/x86_64/photocraft-0.9.0-1-x86_64.pkg.tar.zst
repo/x86_64/photocraft.db
repo/x86_64/photocraft.db.tar.gz
repo/x86_64/photocraft.files
repo/aarch64/...
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

To keep the repository across runs, put the extracted directory somewhere permanent (e.g. `/opt/photocraft-repo/x86_64`) and point `Server` at that path.

## Runtime dependencies

The binaries declare only `glibc`, `libm` and `libgcc_s` as ELF `NEEDED` entries. Windowing and GPU libraries are `dlopen()`ed at runtime, so they cannot be detected automatically; they are declared as `optdepends`:

- **Wayland**: `wayland`, `libxkbcommon`
- **X11**: `libx11`, `libxcb`, `libx11-xcb`, `libxcursor`, `libxi`, `libxkbcommon`, `libxkbcommon-x11`
- **GPU**: `vulkan-icd-loader` + `mesa` (or `libglvnd` + EGL drivers)

winit loads `libxkbcommon-x11` on X11 and panics without it, so install that one if you run an X11 session.

## Notes

- `v0.1.1-rc.N` tags become `pkgver=0.1.1rc.N`; Arch forbids hyphens in `pkgver`, and this form still sorts before the final release.
- The package bundles `photocraft-cli`, the headless converter, as `/usr/bin/photocraft-cli` alongside the GUI.
- `riscv64` builds are skipped automatically for tags older than `v0.7.0`, where upstream has no riscv64 asset.