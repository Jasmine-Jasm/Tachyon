# Architecture

> **Disclaimer**
>
> This tool is intended solely for security research, reverse engineering study,
> and lawful analysis. Do not use it to crack commercial software, infringe
> copyright, or for any other illegal purpose. Users bear full legal
> responsibility for their use.

## Layering

```
             main.c                  CLI, scheduling, progress protocol
                |
   +------------+-------------+
   |                          |
 apk/                   formats/          container + pluggable format providers
   |                          |
 zip/  +  apk/axml.c    dex/ jvm/ lua/ pyc/
   |
 dex/dex.c                             DEX reader (no emission knowledge)
   |
 ir/                                   CFG, instruction decoding, bodies
   |
 emit/                                 Java text, names, stubs, platform tables
   |
 common/                               arena, buf, io, writer, thread pool
```

Each layer only calls downward. `dex/` does not know about Java; `ir/` does not
know about file paths; `emit/` does not parse DEX bytes. That split is what makes
the engine modules usable on their own — `libs/README.md` lists them.

## Data flow for `tachyon d app.apk`

```
1. apk_open
     mmap the file, detect "dex\n" vs ZIP, decompress every classes*.dex,
     dex_setup each one (validates the header, indexes caches)

2. java_build_global_defs
     one open-addressing table mapping class descriptor -> (owning dex,
     class_def index). Type indices are per-dex, so a cross-dex lookup must match
     on the string, never on the index.

3. stub_collect
     walk every referenced type (supertypes, interfaces, fields, protos); keep the
     ones the APK does not define and no platform package supplies. Runs before
     emission because references to them must be spelled the way the stub file
     will be named.

4. per dex:
     remap_init        package/class shadowing rules for this dex
     shadow table      which simple names collide with a package directory
     warm_caches       resolve every string/type/proto/class_data/code up front,
                       because the worker pool must not allocate lazily
     path precompute   java_class_path for every class + create all directories
     pool_run          N workers, each emitting whole classes

5. emit_project_files
     decode AndroidManifest.xml (binary XML) and write build.gradle,
     settings.gradle, local.properties

6. stub_write
     one placeholder per unresolved type
```

## Modules

| Path | Lines | Responsibility |
|---|---:|---|
| `src/main.c` | 1082 | CLI, per-dex loop, thread pool config, progress, project files |
| `src/dex/dex.c` | 1146 | Header validation, string/type/proto/field/method tables, class data, code, MUTF-8 |
| `src/emit/java.c` | 2594 | Class/method/field emission, covariant winner selection, name resolution |
| `src/ir/body.c` | 1443 | Method body rendering: registers, invokes, branches |
| `src/ir/emulate.c` | 782 | Dalvik interpreter used to evaluate decryption helpers |
| `src/ir/cfg.c` | 515 | Basic blocks, control-flow graph |
| `src/ir/opcode.c` | 651 | Instruction decoding and formatting |
| `src/emit/platform_ctors.c` | 475 | Optional android.jar constructor reader (class-file parser) |
| `src/apk/axml.c` | 402 | Binary XML decoder |
| `src/emit/remap.c` | 385 | Name remapping shared by declarations, paths and references |
| `src/emit/platform_builtin.c` | 327 | Framework constructor / abstract method / signature tables |
| `src/emit/stubs.c` | 279 | Placeholder types for missing dependencies |
| `src/emit/heuristic.c` | 249 | Obfuscated name recovery |
| `src/common/arena.c` | 106 | Bump allocator with a spinlock |

## Key structures

**`Arena`** (`common/arena.h`) — every long-lived allocation comes from here. It
bump-allocates 1 MB chunks and never frees until `arena_destroy`. Workers share
one arena, so allocation takes a spinlock. This is why there is no `free` on the
hot path, and why a single oversized request is dangerous: an early version asked
for `file_remaining_size` per string, which multiplied into hundreds of gigabytes
of virtual memory on a 253 000-class input.

**`Dex`** (`dex/dex.h`) — the mapped file plus lazily filled caches
(`string_cache`, `type_name_cache`, `class_data_cache`, `code_cache`,
`proto_params_cache`). All caches are per-dex because every index in the format
is file-local.

**`Insn`** (`ir/opcode.h`) — one decoded instruction: `opcode`, `fmt`, the
register operands in `a` / `b` / `aa` / `regs[]`, `literal`, `idx`, `target`. The
field that holds a register depends on `fmt`; mixing them up is a recurring bug
(see `DELIVERY.md`).

**`ClassFacts`** (`emit/java.c`) — everything the emitter needs about one class:
interface/enum flags, constructor presence and signature, parent resolution
(`parent_known`, `parent_dex`, `parent_has_noarg_ctor`, `parent_ctor_proto`), and
the platform constructor parameters.

## Threading model

`pool_run` hands whole classes to workers. Invariants the pool depends on:

1. **Nothing lazy may allocate during emission.** `warm_caches`,
   `java_prepare_missing_bitmap` and `java_build_package_dirs` must run on the
   main thread first, or workers race on the same cache slots.
2. **Directory creation happens before the pool starts.** `io_mkdirs` walks path
   components; doing it per class cost thousands of redundant syscalls.
3. **Per-task scratch space is thread-local**, including the body arena, the
   writer's directory cache, and the "last owner dex" pointer used during parent
   resolution.
4. **Buffers are per-task.** Each worker builds a `Buf` and hands it to the
   writer, so no output ordering is required.

## Name resolution

A class's name appears in three independent places, and all three must agree or
the output does not compile:

| Site | Function |
|---|---|
| file path | `java_class_path` → `java_class_fqname` |
| declaration | `facts.name` in `java_emit_class` |
| every reference | `remap_java_type` |

The rules applied are: relocate default-package classes into `defpkg`, suffix a
class that shadows a package (`cn` → `cn_`), fold `$` to `_` **only for types the
APK defines**, append `_` to Java keywords, and substitute the inferred name for
obfuscated ones. Any rule added to one site must be added to the other two.

## Extension points

**Format providers** (`src/formats/provider.h`) — implement `probe`, and any of
`describe` / `disassemble` / `decompile` / `extract`. `dispatch.c` picks the
highest-scoring probe. A new format needs no changes elsewhere:

```c
static int my_probe(const uint8_t *d, size_t n) { return magic_ok ? 80 : 0; }
static int my_disassemble(FormatCtx *c) { /* write to c->out */ }

const Formatter g_my_formatter = {
    "myfmt", "My format", my_probe, NULL, my_disassemble, NULL, NULL
};
```

**Platform knowledge** (`emit/platform_builtin.c`) — three tables: constructors,
abstract methods, and methods that conflict with app overrides. Adding an entry
is how a new framework class gets correct `super(...)` calls without an
android.jar.

**Dependency stubs** (`emit/stubs.c`) — a package allow-list decides what is
assumed present. Anything else the APK references but does not contain gets a
placeholder.

## Deliberate limitations

- **Method bodies are opt-in** (`--bodies`). Exception edges and `finally`
  structure cannot be recovered exactly, so the default emits stubs; the flag
  exists for reading, not for producing a buildable copy of the original.
- **`--merge` changes the output shape.** One file per package means only one
  public type, so the rest are demoted. It compiles, but the tree is no longer a
  one-class-per-file layout.
- **Names are inferred, never recovered.** `heuristic.c` produces a description
  of what a class does; the original identifier is gone. Classes with no evidence
  keep their obfuscated name.
