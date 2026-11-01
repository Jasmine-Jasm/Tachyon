# Usage

> **Disclaimer**
>
> This tool is intended solely for security research, reverse engineering study,
> and lawful analysis. Do not use it to crack commercial software, infringe
> copyright, or for any other illegal purpose. Users bear full legal
> responsibility for their use.

## Build

```sh
make run                     # -> /tmp/tbuild/tachyon
make run OUT=/tmp/mytachyon  # different location
```

The workspace is mounted `noexec`, so the binary has to end up somewhere
executable. `make run` puts it in `/tmp` for that reason.

Cross-compile to a static AArch64 binary that Android can execute directly:

```sh
aarch64-linux-gnu-gcc -O2 -std=c11 -D_GNU_SOURCE -Isrc \
    -DTACHYON_VERSION='"0.3.0"' -static \
    -o libs/arm64-v8a/libtachyon.so \
    src/*.c src/*/*.c src/*/*/*.c -lpthread -lm
```

## Commands

### `d` — decompile

```sh
tachyon d app.apk                     # output to ./out, cleared first
tachyon d app.apk -o /tmp/out         # explicit directory, also cleared first
tachyon d app.apk -o /tmp/out --keep  # do not clear
tachyon d app.apk -j 8                # 8 workers
tachyon d app.apk --bodies            # real method bodies instead of stubs
tachyon d app.apk --merge             # one file per package
tachyon d app.apk --emit-only         # decompile but write nothing (timing)
tachyon d app.apk --progress          # machine-readable progress on stdout
tachyon d app.apk --rename mapping.txt  # apply a ProGuard/R8 mapping
```

A bare `.dex` works too; there is just no manifest or Gradle output.

### `info` / `dis` / `list` / `json` / `formats`

```sh
tachyon info app.apk                  # dex count, per-dex table sizes
tachyon dis  app.apk                  # disassemble
tachyon dis  app.apk -n 200           # first 200 methods only
tachyon list app.apk                  # archive entries
tachyon json app.apk                  # structure as JSON
tachyon formats                       # which formats are built in
```

## Reading the output

```
out/
├── AndroidManifest.xml
├── build.gradle
├── settings.gradle
├── local.properties
├── AndroidManifest.xml
├── com/example/...  .java
└── androidx/window/...  .java      <- stubs for libraries the APK did not bundle
```

- **`AndroidManifest.xml`** is decoded from the platform's binary XML. Attributes
  are printed as text; a value that was a resource reference appears as
  `@ref/0x7f0e0001` because the resource table is not resolved.
- **`build.gradle`** reflects how the app was built (`compileSdk` comes from
  `android:compileSdkVersion`, not `targetSdk`). It describes the APK, not the
  original source layout.
- **`local.properties`** contains a placeholder `sdk.dir`; point it at your SDK.
- **Stub files** are empty declarations for types the APK referenced but did not
  carry. If something calls a method on a stub, that call will not compile — the
  stub only asserts that the type exists.
- Every file starts with a three-line comment header.

## Modes

| Mode | What changes |
|---|---|
| `fast` | skips whole-graph analyses; fastest, may leave rare shape errors |
| `balanced` | default |
| `accurate` | adds cross-dex supertype walks that catch rare override shapes |
| `max` | **experimental**: workers = CPU count × 4. Desktop only, do not run on a phone |

## Progress protocol

`--progress` writes one line per step to **stdout**; logs stay on **stderr**:

```
#PROGRESS 10 APK opened, dex parsed
#PROGRESS 15 global index built
#PROGRESS 20 dependency analysis done
#PROGRESS 25 decompiling dex 1/3
#PROGRESS 45 decompiling dex 2/3
#PROGRESS 65 decompiling dex 3/3
#PROGRESS 90 decompilation finished
#PROGRESS 95 project files written
#PROGRESS 100 done
```

Exit codes: `0` all classes written, `1` some class failed (details on stderr),
`2` bad arguments.

## Verifying the result

```sh
tachyon d app.apk -o /tmp/out
python3 bench/report.py /tmp/out
```

`report.py` compiles the whole tree with `javac` against `android-34` and writes
a classified error report to `/tmp/report/`. It compiles **twice** on purpose: a
single syntax error makes `javac` skip semantic analysis entirely, so a naive
one-pass count reports a misleadingly high pass rate. The first pass finds
unparsable files, the second recompiles without them to expose what they hid.

Edit `ANDROID_JAR` at the top of the script if your platform jar lives elsewhere.

## Choosing a strategy for large apps

Measured on a 285 MB app with 253 230 classes:

| Approach | Files | Wall clock |
|---|---:|---:|
| default | 253 376 | 47.8 s |
| `--merge` | 8 608 | ~14 s |
| `--emit-only` (no writes) | 0 | 10.8 s |

Writing files dominates. Creating 253 230 files takes 121 s with a naive
`open/write/close` loop on this hardware; tachyon does it in 37 s because it
writes in package order. If you need the tree quickly and only want to read it,
`--merge` is the lever; if you need one class per file, the write cost is
unavoidable.

## Embedding

`libs/arm64-v8a/libtachyon.so` is a static AArch64 executable. Put it in
`jniLibs/arm64-v8a/`, set `extractNativeLibs="true"`, and run it with
`ProcessBuilder`. Full interface, examples in Java / Python / C, and the SELinux
caveat are in [libs/README.md](libs/README.md).

## Troubleshooting

**`Permission denied` when running the binary**
The directory it sits in is mounted `noexec`. Copy it to `/tmp` or another
executable location. On Android, only certain directories allow execution.

**Nothing is written, exit code 1**
Read stderr — per-class failures are reported there. `bench/report.py` turns
those into a classified list.

**Output looks empty after a rerun**
The output directory is cleared before each run by design. Pass `--keep` to
append to an existing tree instead.

**A class is missing and another has an unexpected name**
Two classes may share a simple name in different packages, or an obfuscated class
was renamed. Renaming appends the original short name (`Impl_Serializable_cn`),
so a collision would show up as a distinct file, not an overwrite.

**`javac` reports a type that does not exist**
The APK referenced a library it did not bundle and the package was on the
allow-list, so no stub was generated. Either add a stub by hand or remove the
package from `kPlatformPkgs` in `src/emit/stubs.c`.
