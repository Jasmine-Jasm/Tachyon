# Security

> **Disclaimer**
>
> This tool is intended solely for security research, reverse engineering study,
> and lawful analysis. Do not use it to crack commercial software, infringe
> copyright, or for any other illegal purpose. Users bear full legal
> responsibility for their use.

## Supported versions

Security fixes are applied to the current `main`. There are no long-term
maintenance branches. If you need a fix backported, say so when you report it.

| Version | Supported |
|---|---|
| 0.3.x | yes |
| < 0.3 | no |

## Reporting a vulnerability

Open a private security advisory on the repository, or contact the author
directly. Please include:

- the input file, or a minimised reproduction (a truncated DEX / APK is usually
  enough — most bugs reproduce from a few hundred bytes),
- the exact command line,
- what happened (crash, hang, out-of-bounds read, huge allocation) and the
  sanitizer output if you have one.

Do **not** open a public issue for a memory-safety bug until a fix is available.

## Threat model

The realistic attack is a **malicious input file**. tachyon's job is to read
attacker-controlled binaries (DEX, APK/ZIP, class files, pyc, Lua bytecode), so
every offset, count and length in those files is treated as hostile.

The tool is **not** a sandbox for the analysed app. It never runs the code it
decompiles: no DexClassLoader, no interpreter over the app's own methods, no JNI.
The only Dalvik bytecode it executes is a small subset inside a decryption-helper
evaluator (`src/ir/emulate.c`), with a step budget and a recursion depth limit
built in.

### What is defended

1. **Bounds checks on every read.** `dex.c` reads through a cursor that records a
   failure flag; a truncated file yields "cannot parse", not an overread.
   Section offsets are compared against the mapped size before use.
2. **Counts are validated before allocation.** A declared element count is only
   trusted after the corresponding table is confirmed to fit inside the file, so
   a small file cannot request a huge allocation through a forged count.
3. **Allocation is sized from content, not from the remaining file.** An earlier
   version allocated `file_size - offset` per decoded string. On a 253 000-class
   input that reserved hundreds of gigabytes of virtual memory and made every
   later allocation fail. It now sizes from the string's own uleb128 length.
4. **ZIP decompression is bounded.** Inflate refuses to write past the declared
   uncompressed size and refuses to loop forever on a stream that produces
   nothing.
5. **No network access, no external process execution** in the decompiler itself.
   It reads a file, writes files, and exits.
6. **Recursion is capped** where the input can drive it: decryption-helper calls
   (depth 12), supertype walks (guard counters), and chunk scanning.

### What is not defended

- **The parser has not been fuzzed.** The checks above are defensive coding, not
  proof. Treat a crafted file as capable of crashing the process.
- **Memory and time are not capped by the tool.** A file declaring millions of
  classes will be processed. Run it with an external limit (`ulimit -v`,
  a container, a timeout) when the input is untrusted.
- **Output is not sanitised for other tools.** Decompiled sources can contain
  strings and identifiers from the analysed app. Do not compile a decompiled
  tree on a machine you care about without reviewing it first.
- **The static binary executes whatever `main` is asked to do.** It has full
  rights of the user that runs it.

## Running on untrusted input

```sh
# Cap memory and time; the process makes no network calls.
ulimit -v 3000000
timeout 300 ./tachyon d untrusted.apk -o /tmp/out --keep
```

Recommended when processing a sample you did not build: a throwaway container, no
network, and a memory cap. `--emit-only` decompiles without writing anything,
which is the cheapest way to see whether a file parses at all.

## Running inside an Android app

`libs/arm64-v8a/libtachyon.so` is a static executable, not a shared library. If an
app places it in `jniLibs/`, Android extracts it to the native library directory,
which is one of the few locations where execution is permitted. Two consequences:

- **`extractNativeLibs="true"` is required.** Without it there is no executable.
- **SELinux may still deny `execve`.** From Android 10, the `untrusted_app` domain
  has restrictions on executing files from app data directories. If
  `ProcessBuilder` throws `IOException: error=13, Permission denied`, the system
  is blocking execution and the engine must instead be built as a JNI library
  against bionic (which needs the Android NDK).

The binary itself is statically linked with no dynamic loader dependency, so it
does not need a glibc rootfs beside it.

## Supply chain

- **Zero third-party dependencies.** Only libc, pthread and libm. Nothing is
  vendored, nothing is downloaded at build time.
- The prebuilt `libs/arm64-v8a/libtachyon.so` is built from this repository's
  source with the command in `libs/README.md`. Rebuild it yourself if you do not
  want to trust the checked-in binary.
- Release APKs, if any, must be signed with a key you control. The keystore used
  while developing the demo app was a throwaway `android`/`android` debug key and
  is not part of this repository.

## Legal and ethical use

This tool decompiles software. Whether you may do that depends on the licence of
the software, the law where you are, and the terms you agreed to.

Use it for security research, interoperability, malware analysis, and study — and
do not use it to crack commercial software, strip licence checks, redistribute
someone else's code, or otherwise infringe rights. **You are responsible for what
you do with it.**
