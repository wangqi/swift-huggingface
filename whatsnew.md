# swift-huggingface: What's New from 0.7.0 to 0.8.1

Generated: 2026-03-15
Source: `git log tag-0.7.0..tag-0.8.1`

---

## Summary

19 commits between tag-0.7.0 and tag-0.8.1, covering one critical iOS/macOS sandbox fix, three major download subsystem rewrites, one API expansion, two bugfixes, and several infrastructure improvements.

---

## New Features and Changes

### 1. iOS and Sandboxed App Cache Path Fix (CRITICAL for iOS) [#40]

**Commit:** `9b2f377` — *Resolve HubCache paths for iOS and sandboxed apps*

Previously, `CacheLocationProvider` used a compile-time `#if os(macOS)` branch: macOS always resolved to `~/.cache/huggingface/hub` and iOS always resolved to `URL.cachesDirectory/huggingface/hub`. This was incorrect for sandboxed macOS apps (Mac Catalyst, App Sandbox), which cannot write to the user home `.cache` directory.

**New behavior:**
- Non-sandboxed macOS: `~/.cache/huggingface/hub` (unchanged)
- Sandboxed macOS / Mac Catalyst / iOS: `Library/Caches/huggingface/hub` (app container)
- Detection uses `APP_SANDBOX_CONTAINER_ID` environment variable, consistent with the Python `huggingface_hub` library.

**Impact on this project:** Direct fix for iOS and Mac Catalyst app container writes. Without this, HubCache would attempt to write outside the app sandbox and silently fail or crash.

---

### 2. Parallel LFS Snapshot Downloads with Weighted Progress [#35]

**Commit:** `95fb37a` — *Parallelize LFS snapshot downloads and weight progress by file size*

Download of snapshot files is now fully parallelized (previously sequential). Progress reporting is now weighted by file size rather than file count, so large-model downloads show accurate progress bars.

**Impact:** Significantly faster model downloads, especially for multi-file models (GGUF shards, MLX weights). No API change at the call site.

---

### 3. Cache-First Snapshot Download with Resume and Local-Only Fallback [#34]

**Commit:** `cc6ea51` — *Add cache-first snapshot download paths with resume and local-only fallback*

Rewrites the `downloadSnapshot` family to:
- Return cached paths immediately if the snapshot is already complete (no network call)
- Support resumable downloads via HTTP Range requests for partial blobs
- Support `localFilesOnly: true` to resolve from local cache only, throwing `HubCacheError.cachedPathResolutionFailed` if missing (offline mode)

New overloads are additive; existing call sites continue to work unchanged.

---

### 4. Commit-Hash Metadata Fast Path [#33]

**Commit:** `7edf91e` — *Return cache-backed snapshot paths and add commit-hash metadata fast path*

When a complete cached snapshot is found, `downloadSnapshot` now skips the commit-hash API call and returns the cached path directly. This eliminates unnecessary network round-trips for already-downloaded models.

---

### 5. API Expansion: Harmonize with Python `huggingface_hub` [#28]

**Commit:** `928f33d` — *Harmonize with huggingface_hub library*

Adds new types and query parameters aligned with the Python `huggingface_hub` library:

- `CommaSeparatedList<Value>` — generic type for Hub API expand and filter parameters
- `ModelExpandField` — expandable model response fields: `author`, `cardData`, `config`, `downloads`, `gguf`, `inference`, `inferenceProviderMapping`, `safetensors`, `siblings`, and more
- `ModelInference` — inference availability filter (`.warm`)
- `SiblingInfo` — now includes a `size` property for per-file size metadata
- `HubClient+Models`, `HubClient+Datasets`, `HubClient+Repos`, `HubClient+Spaces` — all updated with `expand:` and filter parameters

All changes are additive; no existing call sites break.

---

### 6. File Locking: Reentrant Locks and Improved Error Handling [#29]

**Commit:** `38299d3` — *Update file locking implementation to support reentrancy and improved error handling*

Rewrites `FileLock` to support:
- Reentrant locking (a task can re-acquire a lock it already holds)
- Explicit error throwing instead of silent failure
- Lock held correctly across `await` suspension points for structured concurrency

Concurrent downloads introduced in #35 depend on correct file locking. This is a correctness prerequisite for the parallel download feature.

---

### 7. Lock Hierarchy Aligned with Python Library [#36]

**Commit:** `11ae702` — *Route cache blob locks through the .locks hierarchy*

Lock files are now stored under `{cacheRoot}/.locks/` instead of alongside blob files, matching the Python `huggingface_hub` directory layout. No functional change for the app.

---

### 8. Bugfix: Files Sharing the Same Blob Copied Incorrectly [#42]

**Commit:** `de01c0a` — *Fix different files referring to the same blob being copied incorrectly in a snapshot download*

In LFS snapshots, multiple filenames can point to the same blob (same content hash). Previously, when copying from cache to the snapshot directory, only the last copy survived. Each pointer file now gets its own copy.

**Impact:** Affects repos where multiple files share identical content — for example, tokenizer configs bundled alongside multiple model variants.

---

### 9. Bugfix: Download Destinations Treated as File Paths Consistently [#43]

**Commit:** `9ca2e54` — *Treat HubClient download destinations as file paths consistently*

Fixes an edge case where the download destination URL was treated as a directory in some code paths and a file path in others. Affected behavior when specifying a custom download destination.

---

### 10. Dataset API: URL-Only Parquet Responses [#39]

**Commit:** `7b09cef` — *Handle URL-only dataset parquet responses in Hub API*

The Hub API can return parquet file entries as bare URLs. `Dataset.swift` now handles this case; previously it failed to decode such responses.

---

### 11. Dependency: swift-xet Moved to huggingface Org [#44]

**Commit:** `f724f92` — *Update location of swift-xet dependency*

`swift-xet` moved from `github.com/mattt/swift-xet` to `github.com/huggingface/swift-xet`. Same version (`from: "0.2.0"`), only the URL changed. `Package.resolved` will update automatically on next resolve.

---

### 12. Xet CDN: Capture Metadata Before CDN Redirect [#31]

**Commit:** `b0f2286` — *Capture Xet metadata before potential cross-host CDN redirect*

Xet metadata headers must be read before the HTTP client follows a cross-host CDN redirect, which strips headers. Previously, redirected Xet downloads could silently fall back to LFS. Correctness fix for Xet-hosted repos.

---

## Platform Minimum Version Change

| Version | iOS Minimum | macOS Minimum |
|---------|-------------|---------------|
| 0.7.0   | iOS 16      | macOS 13      |
| 0.8.0+  | **iOS 17**  | macOS 14      |

The iOS minimum bumped from 16 to 17 in `Package.swift`. This is the root cause of the
`"HuggingFace requires minimum platform version 17.0"` build error seen in this project.
Any package that depends on the `HuggingFace` product (directly or transitively) must
declare `.iOS(.v17)` or higher.

**Packages fixed in this project on 2026-03-15:**
- `thirdparty/WhisperKit` — upgraded to iOS 17
- `thirdparty/mlx-swift-examples` — upgraded to iOS 17

---

## Risk Assessment

### Low Risk

| Change | Risk | Reason |
|--------|------|--------|
| Parallel downloads (#35) | Low | Additive performance optimization; API call sites unchanged |
| Model/dataset API expansion (#28) | Low | Purely additive new enums and properties; no existing types changed |
| Dataset parquet fix (#39) | Low | Only affects dataset repos with URL-only parquet entries; no behavior change for model repos |
| Xet CDN metadata fix (#31) | Low | Only affects Xet-hosted repos; LFS repos are unaffected |
| CI infrastructure (#32) | Low | Build system only; no code change |

### Medium Risk

| Change | Risk | Reason |
|--------|------|--------|
| Cache-first snapshot with resume (#34) | Medium | New `localFilesOnly` parameter changes error semantics; the cache-first path could skip a re-download if the caller intended a fresh fetch |
| Lock hierarchy change (#36) | Medium | Stale lock files at old paths (beside blobs) will not be cleaned up automatically after upgrade |
| swift-xet URL change (#44) | Medium | `Package.resolved` requires re-resolution; any Xcode package override pointing to the old URL needs updating |

### High Risk (iOS-specific)

| Change | Risk | Reason |
|--------|------|--------|
| Cache path refactor (#40) | High | Behavior change for sandboxed macOS/Mac Catalyst: cache path switches from `~/.cache/` to app container `Library/Caches/`. Existing users upgrading on Mac Catalyst will lose access to their cache at `~/.cache/huggingface/hub` and must re-download models. On iOS the behavior is unchanged. |
| Platform minimum iOS 17 | High | Any package declaring iOS 16 that consumes the `HuggingFace` product fails to build. Full audit of transitive consumers required. |
| Reentrant file lock rewrite (#29) | High | Full rewrite of `FileLock`. Concurrent tasks that previously serialized through non-reentrant locking now behave differently under structured concurrency. Regression risk for any code path that holds a file lock across an `await` and also calls `downloadSnapshot` internally. Unlikely in typical usage but requires integration testing. |

---

## Migration Checklist

- [ ] Verify all packages in the project that use `HuggingFace` declare `.iOS(.v17)` or higher
- [ ] For Mac Catalyst users: note that model caches at `~/.cache/huggingface/hub` will no longer be used after upgrade — models will re-download to the app container
- [ ] Review any call sites using `downloadSnapshot` with a custom destination URL — destination path handling changed in #43
- [ ] If `HF_HUB_CACHE` is set to a custom path, verify it still resolves correctly under the new `defaultCacheDirectory()` logic
- [ ] Check for stale `.lock` files at old locations after upgrading (moved to `.locks/` subdirectory in #36)
- [ ] Run `File > Packages > Update to Latest Package Versions` in Xcode after the swift-xet URL change in #44
