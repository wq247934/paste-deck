# Vendored zstd compression sources

| | |
| --- | --- |
| Upstream | https://github.com/facebook/zstd |
| Version | 1.5.7 (tag `v1.5.7`，与 PasteDeck/AgentSpeed/Sources/CZstd 为同一版本) |
| License | BSD, see `LICENSE` (zstd is dual BSD / GPLv2; this copy is used under BSD) |
| Purpose | PasteDeck Codex 模型路由的原生 GPT 请求体再压缩（`ZSTD_compress`） |

Copied from the tag archive (`zstd-1.5.7.tar.gz`, `lib/`):

- `lib/common/*` → `common/`
- `lib/compress/*` → `compress/`
- `lib/zstd.h`, `lib/zstd_errors.h`

Added: `module.modulemap`（导出 zstd.h）。Build settings 见根 Package.swift
（`ZSTD_DISABLE_ASM=1`、关闭 legacy 与 trace）。
