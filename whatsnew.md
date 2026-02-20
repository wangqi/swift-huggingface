# swift-huggingface: Changes from tag-0.3.0 to tag-0.7.0

## New Features

### HubCache — Python-Compatible Model Cache (0.4.0)
A new `HubCache` struct manages locally downloaded model files using the same directory layout as the Python `huggingface_hub` library. This allows cached files to be shared between Swift and Python clients.

- `HubCache.default` uses auto-detected cache directory (`HF_HUB_CACHE` env var → `HF_HOME/hub` → `~/.cache/huggingface/hub`)
- `cachedFilePath(repo:kind:revision:filename:)` — check if a file is already cached before downloading
- `storeFile(at:repo:kind:revision:filename:etag:ref:)` — store a downloaded file in the cache with content-addressed blobs and symlinks
- `repoDirectory`, `blobsDirectory`, `snapshotsDirectory`, `refsDirectory` — direct access to cache structure paths
- Path-traversal attack protection: validates etag, revision, and filename before writing files
- **Required by `mlx-audio-swift`**: `HubClient.cache` property is now available for MLX model download/cache workflows

### CacheLocationProvider
Determines the HubCache root directory from environment variables (`HF_HUB_CACHE`, `HF_HOME`) or platform defaults. Supports fixed paths, environment-based, and custom resolution strategies.

### FileLock
File-level locking (`FileLock`) prevents race conditions when multiple processes download the same blob concurrently.

### Xet Protocol Support — Faster Large File Downloads (0.7.0)
Downloads files ≥16 MiB via the Xet protocol instead of LFS, providing faster transfer speeds for large model files.

- New `FileDownloadTransport` enum: `.automatic` (default), `.lfs`, `.xet`
- New `FileDownloadEndpoint` enum: `.resolve` (default), `.raw`
- `downloadFile` and `downloadData` now accept `transport:` and `endpoint:` parameters
- Falls back to LFS automatically if Xet is unavailable when using `.automatic`
- Adds `swift-crypto` and `swift-xet` as new package dependencies

### Pagination Convenience API (0.6.0)
New `HubClient+Pagination.swift` provides lazy page sequences for iterating all results without manual cursor management.

- `listAllModels(search:author:filter:sort:direction:perPage:full:config:) -> Pages<Model>`
- `listAllDatasets(...)`, `listAllSpaces(...)`, `listAllOrganizations(...)`, `listAllPapers(...)`, `listAllCollections(...)`
- `Pages<T>` is an `AsyncSequence` — iterate with `for await page in pages { ... }`
- `nextPage(after:)` for manual page-by-page control

### Download Progress Tracking
`downloadSnapshot` now calls the `progressHandler` closure regularly during download (not only on completion). Affected signatures:
- `downloadFile(..., progress: Progress? = nil, ...)`
- `downloadSnapshot(..., progressHandler: (@Sendable (Progress) -> Void)? = nil)`

### TokenStorage — OAuth Token Persistence
New `TokenStorage` type for persisting OAuth tokens across app sessions, used internally by `HuggingFaceAuthenticationManager`.

### Linux Support (0.5.0)
Added `URLSession+Linux.swift` and conditional compilation guards so the package builds on Linux.

---

## Impact on This Project

### ⚠️ BREAKING: `HuggingFaceMiddleware` Protocol Removed
The `HuggingFaceMiddleware.swift` file (added as a project customization at tag-0.3.0) was deleted upstream. The `middlewares:` parameter was also removed from `HubClient` and `InferenceClient` initializers.

**Affected project files that will fail to compile:**
- `ai/huggingface/HuggingFaceInspectorMiddlewareImpl.swift` — conforms to `HuggingFaceMiddleware` (deleted protocol)
- `ai/huggingface/HuggingFaceClientBuilder.swift` — references `HuggingFaceMiddleware` type and `middlewares: [inspector]` parameters

**Required action:** The middleware protocol and its usage in `HubClient`/`InferenceClient` must be migrated to an alternative approach (e.g., a custom `URLSession` delegate or `URLProtocol` subclass for request interception).

### ✅ `HubClient.cache` Now Available
`mlx-audio-swift` uses `client.cache ?? HubCache.default` — this property now exists and the build error is resolved.

### ℹ️ New Package Dependencies
The package now requires `swift-crypto` and `swift-xet`. These will be added to `Package.resolved` automatically during the next Xcode package resolution.
