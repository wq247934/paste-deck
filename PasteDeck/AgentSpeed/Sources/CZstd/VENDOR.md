# Vendored zstd (decompression only)

| | |
| --- | --- |
| Upstream | https://github.com/facebook/zstd |
| Version | 1.5.7 (release `v1.5.7`) |
| Archive | `zstd-1.5.7.tar.gz` from the GitHub release |
| SHA-256 | `eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3` (matches the release's `zstd-1.5.7.tar.gz.sha256`) |
| License | BSD, see `LICENSE` (zstd is dual BSD / GPLv2; this copy is used under BSD) |

Copied unmodified from the archive:

- `lib/zstd.h`, `lib/zstd_errors.h` → `zstd.h`, `zstd_errors.h`
- `lib/common/*` → `common/`
- `lib/decompress/*.c`, `lib/decompress/*.h` → `decompress/` (`huf_decompress_amd64.S` is left out)
- `LICENSE`

Added: `module.modulemap` and this file. Build settings live in `macos/Package.swift` (`ZSTD_DISABLE_ASM=1`, no
legacy formats, no tracing, no multithreading).

To update: download the new release archive and its `.sha256`, verify the checksum, replace the files above, and
update this table.
