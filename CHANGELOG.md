# Changelog

All notable changes to Tachyon are documented in this file.

## [0.5] - 2026-11-02

### Highlights

- Introduced the first production-safe SSA-based method-body recovery pipeline.
- Restored 100% Java compilation for the complete `source.apk` validation target.
- Added semantic execution comparison for controlled Java-to-DEX quality samples.
- Replaced unsafe best-effort body output with explicit, traceable stubs when a method cannot be safely recovered.

### Added

- SSA value construction and version tracking.
- Phi-node construction and dominator-based renaming.
- Def/use tracking and SSA validation.
- Worklist-based type inference for:
  - parameters and receivers;
  - field accesses;
  - method invocation results;
  - arrays;
  - casts;
  - returns;
  - phi values;
  - exception handlers.
- A guarded SSA body emitter supporting verified method shapes, including:
  - linear methods;
  - method calls and `move-result` values;
  - conditional branches;
  - loops;
  - packed and sparse switches;
  - simple constructors;
  - basic exception handling;
  - enums;
  - inner classes;
  - anonymous classes;
  - varargs;
  - generic casts.
- New controlled quality coverage in:
  - `tests/quality/QualitySample.java`;
  - `tests/quality/AdvancedSample.java`.
- Semantic output comparison in `bench/quality.py`.
- SSA smoke coverage integrated into `make test`.
- Additional DEX decoding coverage for `32x`, `45cc`, `4rcc`, `31t`, switch payloads, wide values, range invokes, and large instruction addresses.

### Changed

- The default `--bodies` path now emits a recovered method body only when the SSA pipeline proves that the method shape is supported.
- Methods outside the verified SSA coverage are emitted as explicit stubs instead of guessed Java code.
- `--strict` continues to replace undecoded return-value stubs with `UnsupportedOperationException`.
- The legacy best-effort body renderer is no longer part of the safe release path.
- The legacy renderer is available only for diagnostics through:

  ```sh
  TACHYON_LEGACY_BODIES=1
  ```

- The experimental SSA body pipeline can be enabled for controlled development and quality runs through:

  ```sh
  TACHYON_EXPERIMENTAL_SSA=1
  ```

- Build dependency tracking now includes generated header dependencies, reducing stale-object issues after structure changes.
- Quality fixtures now cover receiver handling, invocation results, same-register reads and writes, branches, loops, switches, try/catch, enums, nested classes, anonymous classes, varargs, and generic casts.

### Fixed

- Incorrect receiver-register rendering that could generate assignments to `this`.
- Incorrect handling of parameters reused as local registers.
- Incorrect versioning for same-register field reads and writes.
- Incorrect `null` comparisons for reference registers in zero-comparison branches.
- Lost types after `move-result` instructions.
- Missing casts for `check-cast` instructions.
- Invalid Java output for filled-array instructions.
- Missing interfaces on anonymous classes.
- Illegal Java identifiers generated from synthetic names containing `-`.
- Incorrect DEX instruction lengths and register decoding for several extended formats.
- Incorrect relative-address handling for switch payloads.
- Potential pointer truncation caused by implicit function declarations.
- Multiple SSA validation cases that could previously fail silently, including invalid registers, duplicate definitions, allocation failures, and bare `move-result` instructions.

### Validation

The `0.5` implementation was validated with:

- Controlled quality samples:
  - `javac_errors=0` in default, strict, and bodies modes;
  - `semantic_match=True` for the SSA bodies run.
- `make test`:
  - command checks passed;
  - invalid-input checks passed;
  - truncated-input checks passed;
  - concurrent-output consistency checks passed;
  - SSA smoke test passed.
- Strict compilation with `-Werror=implicit-function-declaration`.
- AddressSanitizer and UndefinedBehaviorSanitizer on the controlled body-decompilation run.
- Full `source.apk` validation:
  - 15,235 Java files generated;
  - 15,235 / 15,235 files compiled successfully in default mode;
  - 15,235 / 15,235 files compiled successfully with `--bodies`;
  - zero `javac` errors in both modes;
  - approximately 4.1 seconds wall-clock time on the validation environment.

### Limitations

- A 100% compilation rate does not mean that every method body has been semantically recovered.
- Complex or insufficiently proven methods intentionally receive an explicit `STUB` marker.
- Large obfuscated methods, complex generic overloads, platform API signatures, nested exception regions, and advanced control-flow structures remain conservative areas.
- The current release has not yet been established to outperform JADX through a same-input, per-method semantic benchmark.
- The binary version macro and build metadata should be updated separately if the release is to be branded as `0.5` at runtime.

