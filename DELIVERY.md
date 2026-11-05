# tachyon Delivery Notes

> **Disclaimer**
>
> This tool is intended solely for security research, reverse engineering study,
> and lawful analysis. Do not use it to crack commercial software, infringe
> copyright, or for any other illegal purpose. Users bear full legal
> responsibility for their use.

A pure C11 multi-format decompiler with zero third-party dependencies
(`libc + pthread + libm`) distributed as a single binary.

## Current measurements

### source.apk (22 MB / 3 DEX files / 15,216 classes)

| Metric | Value |
|---|---:|
| Decompilation | **approximately 4–6 s** with 8 threads, depending on filesystem load |
| `javac` pass rate | **100.00%** (15,235 / 15,235) |
| Failed files | **0** |
| Output | 15,216 classes + 19 stubs + 4 project files |
| Obfuscated classes renamed | 1,327 |

### WeChat 8.0.79 (285 MB / 18 DEX files / 253,230 classes)

| Metric | Value |
|---|---:|
| Decompilation + write | **47.8 s**, 0 failures |
| `--emit-only` without writing | 10.8 s |
| `--merge` by package | 253,230 → 8,608 files |
| Output size | 1.1 GB |

The physical write floor was measured separately: a bare program takes **121 s**
(2,090 files/s) to create 253,230 files on this machine. Tachyon completes the
same workload in 37 seconds (6,800 files/s), 3.4 times faster than the bare write.
Reducing the total below 20 seconds is not realistic without reducing the file
count with `--merge`, because the remaining cost is f2fs per-file metadata.

## CLI

```text
tachyon d <file> [-o <dir>] [-j N] [--mode fast|balanced|accurate|max]
                 [--bodies] [--rename map.txt] [--emit-only] [--merge] [--keep]
tachyon info  <file>
tachyon dis   <file> [-n N]
tachyon list  <file>
tachyon json  <file>
tachyon formats
```

- `-o`: defaults to `./out`; the directory is cleared before every run. Use
  `--keep` to preserve it.
- `--mode fast`: skips whole-graph analysis and is the fastest mode.
- `--mode balanced`: the default mode.
- `--mode accurate`: enables additional cross-DEX supertype traversal.
- `--mode max`: **experimental**; uses CPU count ×4 workers and is intended for
  desktop testing. Do not use it on a phone.
- `--emit-only`: decompiles without writing files.
- `--merge`: merges each package into one `_merged.java` file. Only public types
  remain public; the result is still compilable.
- `--rename`: applies a ProGuard/R8 `mapping.txt` file.

## Reconstructed project layout

One run produces a project structure that can be opened directly with Gradle:

```text
out/
├── AndroidManifest.xml     binary AXML decoded to readable text
├── build.gradle            namespace / compileSdk / minSdk / targetSdk / versionCode / versionName
├── settings.gradle         rootProject.name + include ':app'
├── local.properties        placeholder sdk.dir
└── com/...                 Java source tree
```

`AndroidManifest.xml` is decoded from the APK's binary XML by the custom decoder
in `src/apk/axml.c`. Attribute values are formatted according to their type:
strings, references, integers, booleans, and dimensions.

## Watermark

Every generated source file begins with:

```text
//TachYon An incredibly fast decompilation tool
//No dependencies
//TachYon CN AI Agent DeepSeekv4.1flash
```

## Engines and extensions

Each capability is implemented as an independent module and can be used without
depending on the other engines.

### 1. String-decryption engine (`src/ir/emulate.c`)

A lightweight Dalvik interpreter evaluates decryption helpers during
decompilation and replaces ciphertext with plaintext.

- Supported instructions include `move`, `move-result`, `const-*`, `aget` / `aput`,
  `array-length`, `new-instance`, `new-array`, `goto`, `if-*` (`22t` and `if-*z`),
  `int-to-char` / `short` / `byte`, `0xd8..0xe2` literal arithmetic, and
  `invoke-static` / `virtual` / `direct`.
- Simulated JDK methods include `String.length`, `charAt`, `toString`,
  `StringBuilder.append`, `StringBuilder.toString`, `Integer.parseInt`,
  `Integer.valueOf`, and `Character.toString`.
- Recursion depth is limited to 12 and execution steps to 20,000. Evaluation is
  abandoned when a limit is reached and the original call is retained.
- The evaluated result matches manual calculation for the XOR sample
  `8888898` → `bbbbbcb`.

**Important convention:** `append(char)` and `append(int)` are distinguished by
prototype parameter descriptors. `charAt` returns `EMU_CHAR`, not `EMU_INT`, so
that it is emitted as a character rather than a number.

### 2. Obfuscated-name recovery (`src/emit/heuristic.c`)

Single-letter class names such as `a`, `b2`, and `a0` are renamed only when there
is evidence in the class itself:

| Evidence | Generated name |
|---|---|
| Static string constant (4–20 characters) | `Impl_<constant>` / `Abstract_<constant>` |
| Non-`Object` parent | `Sub_<parent>` / `Abstract_<parent>` |
| Unique implemented interface | `Impl_<interface>` |
| No evidence | Preserve the original name (`a`, `a0`, ...)

The original short name is always appended to the generated name, for example
`Impl_Serializable_cn`, to prevent package-level collisions. Name lookup uses a
hash table and remains practical at 250,000 classes.

The name must be changed consistently in all three locations:
`java_class_fqname` for paths, `facts.name` for declarations, and
`remap_java_type` for references. Array descriptors such as `[La;` are unwrapped
before lookup.

### 3. Built-in dependency layer (`src/emit/platform_builtin.c`, `src/emit/stubs.c`)

Tachyon does not require `android.jar`. It uses three built-in tables plus stub
generation:

- **Platform constructors:** more than 80 framework constructor signatures,
  including `View(Context)`, `GZIPOutputStream(OutputStream)`, and
  `ThreadPoolExecutor(...)`. If a parent exposes only parameterized constructors,
  synthesized constructors pass typed default values.
- **Platform abstract methods:** entries such as `Service.onBind`,
  `ContentProvider.query`, and `BaseAdapter.getView`, allowing missing child
  implementations to receive compilable stubs instead of making Android
  components abstract.
- **Platform method signatures and parent chains:** conflicts such as
  `ViewParent.getLayoutDirection():int` and `AdapterView.setAdapter` are detected;
  conflicting members or interfaces are dropped instead of leaving compile errors.
- **Stub generation:** referenced but unpackaged types such as
  `androidx.window.*`, `android.view.RenderNode`, and `org.conscrypt.*` receive
  placeholder declarations. Their class/interface kind is inferred from usage.

### 4. Binary XML decoding (`src/apk/axml.c`)

The binary XML decoder handles string pools in UTF-8 and UTF-16, namespaces,
elements, attributes, and CDATA. It also exposes name-based attribute lookup for
fields such as `package` and `android:versionCode`, which drives project-file
generation.

### 5. Multi-format providers (`src/formats/`)

| Format | Capability | Ground truth |
|---|---|---|
| DEX / APK | Full Java decompilation | Instruction-by-instruction match with `dexdump -d` (65,695 instructions) |
| JVM class | Disassembly + structure | Instruction-by-instruction match with `javap -c -p` |
| CPython pyc | Disassembly + structure | Match with Python `dis` |
| Lua 5.1–5.4 | Disassembly | Match with `luac -l` |

### 6. Method-body decompilation (`--bodies`)

The current release includes three recovery rounds: guarded SSA emission, type-boundary and performance improvements, and supported explicit throw/catch recovery. The GUI is documented separately in `USAGE.md` and launched with `make gui`.

The first stage of method-body reconstruction now includes:

- `src/ir/ssa.c` / `src/ir/ssa.h`: normalized instruction streams on top of the
  existing CFG;
- binding adjacent `invoke-*` and `move-result*` instructions into one logical
  instruction with explicit def/use information;
- register modeling for normal moves, wide values, field and array access, range
  invokes, and filled-new-array instructions;
- `src/ir/type_infer.c` / `src/ir/type_infer.h`: worklist-based propagation for
  parameters, receivers, fields, invoke results, arrays, casts, returns, phis, and
  handlers;
- `src/ir/body_emit.c` / `src/ir/body_emit.h`: guarded SSA body emission for
  supported method shapes.

The current controlled quality baseline reports `javac_errors=0` in default,
strict, and bodies modes, with `semantic_match=True` for the SSA body run. The
complete `source.apk` target compiles 15,235/15,235 files in both default and
release `--bodies` modes.

The release path emits a real body only when the SSA emitter can prove that the
shape is supported. Otherwise it emits a marked `STUB`. The old best-effort
renderer is diagnostic-only and requires `TACHYON_LEGACY_BODIES=1`.

The next stage is to expand structured regions, complex exception handling,
platform signatures, and large obfuscated methods. A comprehensive claim of
outperforming JADX has not been established.

## Major bugs and root causes fixed in this cycle

1. **`dex_string` memory bomb:** each string used to allocate the remaining file
   size. A WeChat DEX could request 8 MB per string and exhaust virtual memory.
   Allocation now follows the ULEB128 character count ×3.
2. **Implicit function declaration pointer truncation:** `body.c` lacked the
   required declaration for `java_body_arena()`, causing a 64-bit pointer to be
   treated as an `int`. The build now supports `-Werror=implicit-function-declaration`.
3. **Winner check after deduplication:** covariant methods were marked in the
   signature set before the real method was checked, so the real method was
   discarded. The order is now reversed.
4. **Cross-DEX index mixing:** `class_def_of_type` returns an index in the owning
   DEX, not necessarily the current DEX. Flags and class data now use the owning
   DEX.
5. **Synthesized-constructor condition gap:** when all parent constructors were
   parameterized, neither previous condition generated a constructor. The
   fallback now emits a typed parent call.
6. **Lost stub classification:** a type first seen as a parameter and later used in
   `implements` was not rewritten as an interface. Hash-table entries now update
   their classification.
7. **`javac` syntax errors hiding semantic errors:** `bench/report.py` compiles
   twice and explicitly reports parse failures before recompiling without those
   files.

## Build

```sh
cd ~/workspace/tachyon && make run   # output: /tmp/tbuild/tachyon
```

The workspace is mounted `noexec`; binaries must be placed under `/tmp` or another
executable location.

## Verification

```sh
python3 bench/report.py ./out     # full error report in /tmp/report/
sh bench/run_tests.sh             # functional regression suite
make quality                      # controlled Java -> DEX -> compile/semantic check
```

## Not implemented

- CIL (.NET), EVM, Go binaries, and x86-64 / ARM64 disassemblers
- Control-flow flattening recovery and anti-debug detection
- C, Go, or Kotlin source output; these were explicitly deferred
