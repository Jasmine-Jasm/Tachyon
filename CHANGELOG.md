# Changelog

All notable changes to Tachyon are documented in this file.

## [0.5] - 2026-11-05

Tachyon v0.5 consolidates three compressed development rounds focused on safe SSA body recovery, type correctness, exception handling, performance, and a bilingual local GUI.

### Round 1 — SSA and Safe Body Recovery

- Added the guarded SSA-based method-body recovery pipeline.
- Added SSA values, phi nodes, def/use tracking, dominator-based renaming, and worklist type inference.
- Added verified emission for linear methods, calls, `move-result`, branches, loops, switches, constructors, arrays, `instanceof`, numeric conversions, enums, inner classes, anonymous classes, varargs, and generic casts.
- Fixed multi-dimensional array Java generation.
- Added safe `STUB` fallback when a method cannot be proven recoverable.
- Added controlled semantic comparison in `bench/quality.py` and extended quality fixtures.

### Round 2 — Type Boundaries and Performance

- Fixed DEX parameter-register mapping, including wide `long` and `double` parameters.
- Added type-aware conversion at method-call, return, field-write, and array-write boundaries.
- Added Def/Use indexing to avoid repeated full-instruction scans during type propagation.
- Added early size checks before expensive SSA work on methods that cannot be emitted safely.
- Improved writer directory handling with cached directory file descriptors.
- Preserved the safe release path while restoring full APK processing to the approximately 4–6 second range on the validation machine.

### Round 3 — Exception and Region Recovery

- Added explicit `throw` emission for supported SSA methods.
- Added `move-exception` handling in supported catch handlers.
- Added `Throwable` and concrete-exception compatibility during type inference.
- Added controlled throw/catch semantic coverage.
- Complex `finally`, `synchronized`, multi-region, and unsupported exception structures continue to fall back safely.

### Bilingual GUI

- Added a zero-dependency local browser GUI under `gui/`.
- Added English and Chinese language switching without changing the CLI or engine.
- Added browser-local configuration persistence.
- Added APK/DEX input, output directory, worker count, mode, `--bodies`, `--strict`, and `--merge` controls.
- Added Fast, Balanced, and Accurate presets.
- Added command preview, example configuration, live progress, stdout/stderr logs, clear-log, reset-configuration, and stop controls.
- Added `make gui` as the standard launcher.

### Validation

- Controlled quality samples:
  - default, strict, and bodies modes: `javac_errors=0`;
  - SSA bodies semantic comparison: `semantic_match=True`.
- `make test` passed.
- SSA smoke tests passed.
- Strict compilation with `-Werror=implicit-function-declaration` passed.
- ASAN and UBSAN controlled runs passed.
- Full `source.apk` validation:
  - 15,235 Java files generated;
  - 15,235 / 15,235 compiled successfully in default mode;
  - 15,235 / 15,235 compiled successfully with `--bodies`;
  - zero `javac` errors in both modes;
  - current validation wall-clock range: approximately 4–6 seconds depending on filesystem load.
- GUI smoke validation passed:
  - Python syntax compilation;
  - local page serving;
  - status API;
  - invalid-input validation;
  - language switching;
  - preset command preview;
  - core CLI regression after GUI integration.

### License

MIT License © 2024. See [LICENSE](LICENSE).

### Limitations

- A 100% compilation rate does not mean every method body has been semantically recovered.
- Complex or insufficiently proven methods intentionally receive an explicit `STUB` marker.
- Large obfuscated methods, complex generic overloads, platform API gaps, nested exception regions, and advanced control-flow structures remain conservative areas.
- A same-input, per-method semantic benchmark has not yet established full parity with or superiority over JADX.
- The runtime version macro remains a separate release-configuration decision and should be changed to `0.5.0` before publishing a binary branded with that version.
