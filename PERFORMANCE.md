# Performance Measurements

> **Disclaimer**
>
> This tool is intended solely for security research, reverse engineering study,
> and lawful analysis. Do not use it to crack commercial software, infringe
> copyright, or for any other illegal purpose. Users bear full legal
> responsibility for their use.

Hardware: 8-core Cortex-A55, f2fs, 5.7 GB RAM.

## source.apk (22 MB, 3 DEX files, 15,216 classes)

| Measurement | Value |
|---|---:|
| Internal timing (`pool_run`) | **3.0 s** |
| Process wall clock including writes | **3.5 s** |
| `--merge` | 2.7 s (15,216 → 259 files) |

## WeChat 8.0.79 (285 MB, 18 DEX files, 253,230 classes)

| Measurement | Value |
|---|---:|
| `--emit-only` without writes | **10.8 s** |
| Process wall clock including 253,376 writes | **47.8 s** |
| `apk_open` (decompress and parse 18 DEX files) | 1.2 s |

### Physical write floor

A bare program that only performs `open/write/close` was measured separately. Creating
253,230 files across 11,311 directories with 8 threads requires **121 seconds** on
this machine, or 2,090 files/s.

Tachyon completes the same workload in 37 seconds (**6,800 files/s**), 3.4 times
faster than the bare writer, because it writes in package order and benefits from
directory locality.

**Conclusion: approximately 37 seconds of the 47.8-second total is unavoidable
per-file filesystem metadata overhead.** Reaching 20 seconds would require reducing
the file count with `--merge`.

## Phase breakdown (source.apk)

| Phase | Time |
|---|---:|
| `apk_open` | 0.6 s |
| `remap+shadow` | 0.03 s |
| `warm_caches` | 0.5 s |
| `stub_collect` | 0.05 s |
| `pool_run` (DEX1 / DEX2 / DEX3) | 2.4 / 0.03 / 0.6 s |

## Thread count (source.apk)

| Threads | Wall clock |
|---:|---:|
| 1 | 8.3 s |
| 4 | 3.9 s |
| 8 | **3.0 s** |
| 16 | 4.0 s |

Eight threads are the turning point on this hardware. `--mode max` (CPU count ×4)
is a desktop testing feature; **do not enable it on a phone**.

## Comparison with JADX (2026-11-01)

Same `source.apk` input with 15,216 classes on the same machine:

| Tool | Result |
|---|---|
| tachyon 0.3.0 | **3.5 s for all 15,216 classes**, 0 failures |
| JADX 1.5.6 | More than 30 minutes produced only 1,817 files (12%), then stalled and was manually terminated |

Controlled sample quality comparison (4 classes / 31 methods with known source):

| Metric | tachyon default | tachyon `--bodies` | JADX 1.5.6 |
|---|---:|---:|---:|
| `javac` errors | 0, but method bodies are stubs | **2** | **0** |
| Semantic comparison (8 outputs) | 0/8, silently returned 0 | Much higher body compilation coverage | **8/8 correct** |

The honest conclusion from this benchmark is that JADX remains the reference for
method-body quality. Tachyon's default mode is faster but provides skeletons;
`--bodies` improves controlled-sample compilation coverage, but its semantic result
still trails JADX. `--strict` converts silent default stubs into explicit exceptions.

## Performance pitfalls already fixed

1. **`dex_string` allocated the remaining file size:** each decoded string requested
   `d->size - off` bytes. A 12 MB DEX could survive through virtual memory, but the
   8.6 MB × 250,000-class workload exhausted the address space. Allocation now uses
   ULEB128 character count ×3.
2. **Linear cross-DEX scans:** every parent lookup scanned every type in every DEX;
   45 seconds became 3 seconds after adding a hash index.
3. **O(n²) shadow table:** 11,565² string comparisons and 68 seconds became a sort
   plus binary search taking 0.03 seconds.
4. **Unlocked arena:** concurrent races were fixed by adding a spinlock.
5. **`io_mkdirs` per file:** complete path traversal for every file was replaced by
   directory precreation at startup.
6. **BFS `memmove` dequeue and linear `seen`:** replaced with a ring buffer and
   bitmap.
7. **Linear `stub_collect` deduplication:** replaced O(n²) behavior with a hash table
   sized from the class count.
8. **O(n⁴) `iface_conflicts`:** signature hash tables replaced repeated full-chain and
   full-method scans, reducing the operation to linear behavior.
9. **`openat` directory-FD cache:** tested and reverted because it was slower on this
   machine: 57.5 seconds versus 47.8 seconds. With 8 threads and 512 slots against
   11,311 directories, cache misses caused extra open/close overhead.

## Measurement notes

- Measure **process wall clock**, not only `pool_run`; otherwise all I/O costs are
  omitted.
- Background applications can severely distort results. The same input changed
  from 3.0 seconds to 7–9 seconds while QQ was running.
- The output directory is fixed at `./out` and cleared before every run, preventing
  accumulated output from consuming disk space.
