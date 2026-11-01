# tachyon

A multi-format decompiler written in pure C11. No third-party dependencies, a
single binary, embeddable.

```
source.apk      15216 classes      3.5 s     javac pass rate 100.00%
WeChat 8.0.79   253230 classes    47.8 s     0 failures
```

> **Disclaimer**
>
> This tool is intended solely for security research, reverse engineering study,
> and lawful analysis. Do not use it to crack commercial software, infringe
> copyright, or for any other illegal purpose. Users bear full legal
> responsibility for their use.

## Quick start

```sh
# Build. The workspace is mounted noexec, so the binary lands in /tmp.
make run

# Decompile into ./out (the directory is cleared before each run)
/tmp/tbuild/tachyon d app.apk

# With machine-readable progress (see "Interface")
/tmp/tbuild/tachyon d app.apk --progress

# Many classes: merge per package (one file per package, still compiles)
/tmp/tbuild/tachyon d app.apk --merge
```

The output is a project Gradle can open directly:

```
out/
├── AndroidManifest.xml     binary AXML decoded to text
├── build.gradle            namespace / compileSdk / minSdk / targetSdk / version
├── settings.gradle
├── local.properties
├── <package path>/<Class>.java
└── <missing dependency>/...  stub declarations for libraries the APK referenced
                              but did not bundle
```

## Embedding in another project

`libs/arm64-v8a/libtachyon.so` is a prebuilt AArch64 **static** executable
(1.4 MB, zero dynamic dependencies). Drop it into `jniLibs/` and it works.
The complete interface — command line, `#PROGRESS` protocol, exit codes, Java /
Python / C examples, and the Android SELinux caveat — is in
[libs/README.md](libs/README.md).

Individual engine modules can also be compiled into other programs. The headers
are the interface, and the modules do not depend on each other.

## CLI

```
tachyon d <file> [-o <dir>] [-j N] [--progress]
                 [--mode fast|balanced|accurate|max]
                 [--bodies] [--merge] [--keep] [--emit-only] [--rename map.txt]
tachyon info  <file>     dex count and table sizes
tachyon dis   <file>     disassemble
tachyon list  <file>     list archive entries
tachyon json  <file>     export structure as JSON
tachyon formats          supported formats
```

`--mode max` is **experimental**: it oversubscribes every core (CPU count ×4)
and has only been validated on a desktop. Do not run it on a phone.

## Supported formats

| Format | Capability | Ground truth |
|---|---|---|
| DEX / APK | Full decompilation to Java | instruction-by-instruction match with `dexdump -d` (65695 instructions) |
| JVM class | Disassembly + structure | match with `javap -c -p` |
| CPython pyc | Disassembly + structure | match with Python `dis` |
| Lua 5.1–5.4 | Disassembly | match with `luac -l` |

## Engines

Each module is self-contained and can be used on its own.

| Module | Purpose |
|---|---|
| `src/dex/dex.c` | DEX parsing: string pool (MUTF-8), types, prototypes, class data, bytecode |
| `src/ir/emulate.c` | Dalvik interpreter; evaluates string-decryption helpers at decompile time and replaces ciphertext with plaintext |
| `src/emit/heuristic.c` | Obfuscated name recovery: derives names for `a`/`b2` from class contents, keeps the original when there is no evidence |
| `src/emit/platform_builtin.c` | Built-in framework constructor / abstract-method / method-signature tables; no android.jar required |
| `src/emit/stubs.c` | Stub declarations for types the APK references but does not carry |
| `src/apk/axml.c` | Binary XML decoder (AndroidManifest) |
| `src/formats/` | Pluggable format providers (dex / jvm / pyc / lua) |
| `bench/report.py` | Full-tree compile verification and error classification; compiles twice so a syntax error cannot hide semantic errors |

Design decisions and the bugs behind them are recorded in
[DELIVERY.md](DELIVERY.md) and [PERFORMANCE.md](PERFORMANCE.md).

## Layout

```
src/apk/        APK container, binary XML
src/common/     arena / buf / io / thread pool / writer
src/dex/        DEX parsing
src/emit/       Java emission, remapping, obfuscated names, platform tables, stubs
src/formats/    multi-format providers
src/ir/         CFG, instruction decoding, body emission, interpreter
bench/          benchmark and verification scripts
libs/           prebuilt engine and its calling interface
tests/          regression cases
```

## Building

```sh
make run                        # native, output /tmp/tbuild/tachyon
make run OUT=/your/path         # different output location

# Cross-compile to a static binary Android can execute directly
aarch64-linux-gnu-gcc -O2 -std=c11 -D_GNU_SOURCE -Isrc \
    -DTACHYON_VERSION='"0.3.0"' -static \
    -o libs/arm64-v8a/libtachyon.so \
    src/*.c src/*/*.c src/*/*/*.c -lpthread -lm
```

The workspace is mounted `noexec`, so the binary must live somewhere executable
(`/tmp`, or a copy of `libs/` placed elsewhere).

## Verifying

```sh
/tmp/tbuild/tachyon d app.apk -o /tmp/out
python3 bench/report.py /tmp/out      # compiles everything, writes /tmp/report/
```

## Documentation

| File | Contents |
|---|---|
| [USAGE.md](USAGE.md) | every command with examples, output layout, modes, progress protocol, troubleshooting |
| [ARCHITECTURE.md](ARCHITECTURE.md) | layering, data flow, key structures, threading model, extension points |
| [SECURITY.md](SECURITY.md) | threat model, defensive measures, resource limits, Android exec caveat, supply chain |
| [DELIVERY.md](DELIVERY.md) | capability list and the root cause of every significant bug fixed |
| [PERFORMANCE.md](PERFORMANCE.md) | measured timings, the write-cost floor, and nine performance traps |
| [libs/README.md](libs/README.md) | calling interface for the embedded engine |

## License

Unspecified. Contact the author before use.
