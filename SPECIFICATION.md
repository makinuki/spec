# Project MakiNuki (巻抜き)
## Core Technical Specification
**Version:** `1.0.0`  
**Status:** `Approved / Frozen (ABI 1)`  
**Namespace:** `makinuki`  
**Target Runtimes:** Web (Browser), Android, Desktop, Headless CLI  

---

## 1. Architectural Principles

1. **Host-Sandboxed Execution:** Scrapers run as compiled WebAssembly (`.wasm`) modules managed by the **Extism runtime**. Scrapers have zero direct access to OS sockets, file systems, or DOM APIs.
2. **Inverted I/O (Host-Driven Networking):** All HTTP requests, cookie storage, and environment bridges are delegated to the host runtime via host imports.
3. **Language-Agnostic Source Development:** Scrapers can be written in any language supported by Extism PDKs (TypeScript, Go, Rust, Python, C, Zig) as long as they compile to standard `.wasm` exporting the MakiNuki ABI.
4. **Declarative UI Filtering:** Filter systems are emitted as schema arrays; host applications dynamically generate native UI components (dropdowns, tri-state checkboxes, search fields) without hardcoding source specifics.
5. **Two-Tier Image Delivery:** Standard image streams bypass WASM memory via direct CDN URLs; scrambled/sliced images are routed through an optional WASM unscrambler hook only when necessary.

---

## 2. The WASM ABI Contract

Every MakiNuki source must compile to a single `.wasm` binary that interfaces with the host environment using JSON strings passed over the Extism memory boundary.

```
┌────────────────────────────────────────────────────────┐
│                      Host Runtime                      │
│                                                        │
│  Host Imports (Namespace: "makinuki"):                 │
│    • makinuki_fetch(request_json) -> response_json     │
│    • makinuki_storage_get(key_string) -> value_string  │
│    • makinuki_storage_set(kv_json) -> void             │
│    • makinuki_log(log_json) -> void                    │
└───────────────────────────┬────────────────────────────┘
                            │ Memory Buffer (JSON)
┌───────────────────────────▼────────────────────────────┐
│                  MakiNuki Plugin (.wasm)               │
│                                                        │
│  Plugin Exports:                                       │
│    • get_metadata() -> SourceMetadata                  │
│    • get_filters() -> FilterSchema[]                   │
│    • search(query_json) -> PageResult<MangaItem>       │
│    • get_details(manga_id_string) -> MangaDetails      │
│    • get_pages(chapter_id_string) -> PageItem[]        │
│    • [Optional] unscramble_image(raw_bytes) -> bytes   │
└────────────────────────────────────────────────────────┘
```

---

### 2.1 Host Imports (Provided by Host Application)

Host functions reside under the module namespace `"makinuki"`.

#### `makinuki_fetch(request_json: string) -> string`
Executes an HTTP request using the host environment's network stack (OkHttp, Browser fetch, Companion Extension, or Worker Proxy).

* **Input (`HttpRequest`):**
```json
{
  "url": "https://api.example.com/manga/123",
  "method": "GET",
  "headers": {
    "User-Agent": "MakiNuki/1.0",
    "Referer": "https://example.com"
  },
  "body": null
}
```

* **Output (`HttpResponse`):**
```json
{
  "status": 200,
  "headers": {
    "content-type": "application/json; charset=utf-8"
  },
  "body": "{\"id\":\"123\",\"title\":\"Example Manga\"}"
}
```

* **Error Response on Challenge/Block (`HttpError`):**
```json
{
  "error": "CLOUDFLARE_BLOCKED",
  "status": 403,
  "url": "https://example.com/challenge",
  "message": "Cloudflare Turnstile challenge detected"
}
```

#### `makinuki_storage_get(key: string) -> string | null`
Reads a string value from host storage, scoped to the current source ID (per-source namespace; keys never collide across sources).

* **Missing keys:** Returns `null`. An empty string (`""`) is a legitimate stored value; only a missing key yields `null`.
* **Value cap:** 64 KB per value. Writes exceeding the cap are rejected by the host at the Extism call boundary (PDKs surface this as an exception); reads of over-cap values stored by older runtimes are truncated.

#### `makinuki_storage_set(key_value_json: string) -> void`
Persists a string value to host storage.
* **Input:** `{"key": "session_token", "value": "xyz789"}`

#### `makinuki_log(log_json: string) -> void`
Emits a log entry to the host debugger/console.
* **Input:** `{"level": "info", "message": "Fetched page 1 successfully"}` *(Levels: `"debug"` | `"info"` | `"warn"` | `"error"`)*

---

### 2.2 Plugin Exports (Implemented by Scrapers)

All exported functions accept and return string pointers containing serialized JSON, except for `unscramble_image` which accepts and returns raw byte buffers. Static exports (`get_metadata`, `get_filters`) return raw payloads; dynamic exports (`search`, `get_details`, `get_pages`) wrap their payloads in the `PluginResult<T>` envelope defined in Section 3.6.

#### 1. `get_metadata() -> string`
Returns static information identifying the source.

#### 2. `get_filters() -> string`
Returns an array of `FilterSchema` objects describing the site's search capabilities.

#### 3. `search(query_json: string) -> string`
Performs keyword searches, tag filtering, and pagination.
* **Input Parameter (`SearchQuery`):**
```json
{
  "query": "Solo",
  "page": 1,
  "filters": {
    "sort": "latest",
    "genres": {
      "Action": "+",
      "Romance": "-"
    },
    "status": "Ongoing"
  }
}
```
* **Output:** Serialized `PageResult<MangaItem>`.

#### 4. `get_details(manga_id: string) -> string`
Fetches complete metadata and chapter listings for a specific title.
* **Output:** Serialized `MangaDetails`.

#### 5. `get_pages(chapter_id: string) -> string`
Fetches the ordered list of image pages for a given chapter.
* **Output:** Serialized `PageItem[]`.

#### 6. *(Optional)* `unscramble_image(raw_bytes: bytes) -> bytes`
Takes raw image bytes of a scrambled puzzle tile, reconstructs the original layout, and returns standard clean image bytes (`image/jpeg` or `image/png`).

* **Failure convention:** If the input cannot be reconstructed, the plugin returns a **zero-length byte buffer**; the host reports `UNSCRAMBLE_FAILED` (Section 6) to the delivery pipeline and skips rendering the tile.
* **Memory constraints:** Each plugin instance is granted a **64 MB** Extism memory budget. Input buffers to `unscramble_image` are capped at **16 MB raw bytes / 8192×8192 px**; if an image exceeds these limits, the host rejects the call with `MEMORY_LIMIT_EXCEEDED` (Section 6).

---

## 3. Data Schemas (JSON Specification)

### 3.1 `SourceMetadata`
```typescript
interface SourceMetadata {
  id: string;              // Unique slug, e.g. "mangadex-en", "asura-scans"
  name: string;            // Display name, e.g. "Asura Scans"
  version: string;         // SemVer string, e.g. "1.0.4"
  abiVersion: number;      // ABI contract version this plugin was built against; must equal the host ABI version at runtime
  lang: string;            // ISO 639-1 code, e.g. "en", "ja"; or "multi" for multi-language sources
  baseUrl: string;         // Canonical website URL
  iconUrl: string;         // URL or base64 data URI of the source icon
  nsfw: boolean;           // True if the source primarily hosts 18+ content
}
```

---

### 3.2 `FilterSchema` (Declarative UI)
Host applications iterate through this schema array to build search filter menus.

```typescript
type FilterSchema = 
  | SelectFilter 
  | TriStateFilter 
  | CheckboxFilter 
  | TextFilter;

interface BaseFilter {
  id: string;              // Key passed back in SearchQuery.filters
  title: string;           // Display label in UI
}

interface SelectFilter extends BaseFilter {
  type: "select";
  options: Array<{ label: string; value: string }>;
  default: string;
}

interface TriStateFilter extends BaseFilter {
  type: "tri_state";
  // Allows Included (+), Excluded (-), Neutral (absent)
  options: Array<{ label: string; value: string }>;
  default?: Record<string, "+" | "-">;
}

interface CheckboxFilter extends BaseFilter {
  type: "checkbox";
  default: boolean;
}

interface TextFilter extends BaseFilter {
  type: "text";
  placeholder?: string;
  default?: string;
}
```

**Filter defaults contract:** The defaults emitted by `get_filters()` must describe the unfiltered result set. A host or client applying exactly the defaults must receive everything the source can find. A checkbox defaulting to checked means inclusive (checked = include in the query); a filter must never silently hardcode an unrelated query dimension (for example a language restriction inside a chapter-count checkbox).

---

### 3.3 `MangaItem` & `PageResult<T>`
```typescript
interface PageResult<T> {
  page: number;
  hasNextPage: boolean;
  items: T[];
}

interface MangaItem {
  id: string;              // Unique ID scoped to this source
  title: string;
  coverUrl: string;
  latestChapter?: string;  // e.g. "Ch. 142"
  url?: string;            // Web URL to the series
}
```

**Complete results contract:** Dynamic exports (`search`, `get_details`) return everything the source can find (all languages, groups, and content ratings) unless the caller's `filters` narrow the result. In ABI 1, `get_details` takes no filter input and must not apply language, rating, or content restrictions internally. Empty results are successful results: `search` may return zero items and `get_details` may return an empty `chapters` array inside `ok: true`; hosts must not treat them as errors.

---

### 3.4 `MangaDetails` & `ChapterItem`
```typescript
interface MangaDetails {
  id: string;
  title: string;
  altTitles?: string[];
  description?: string;
  authors?: string[];
  artists?: string[];
  genres?: string[];
  status: "Ongoing" | "Completed" | "Hiatus" | "Cancelled" | "Unknown";
  coverUrl: string;
  chapters: ChapterItem[];
}

interface ChapterItem {
  id: string;              // Unique chapter ID/slug
  number: number | null;   // Float supporting decimals, e.g. 10.5; null for oneshots, extras, and unnumbered specials
  language?: string;       // ISO 639-1 with optional region, e.g. "en", "pt-br"; multi-language sources must populate it
  title?: string;          // Optional chapter name, e.g. "The Return"
  uploadedAt?: number;     // Unix timestamp in milliseconds
  scanlator?: string;      // e.g. "Flame Comics"
  url?: string;
}
```

---

### 3.5 `PageItem` (Two-Tier Delivery)
```typescript
interface PageItem {
  index: number;
  url: string;                          // Remote image URL
  headers?: Record<string, string>;     // Required headers, e.g. Referer
  isScrambled: boolean;                 // If true, host routes bytes through unscramble_image()
  metadata?: ScrambleInfo;              // Required if isScrambled; tile map (Section 3.5)
}
```

**Platform Delivery Contract:**

* **Android / Desktop:** Native HTTP pipelines (OkHttp / Reqwest) inject `headers` directly onto image requests.
* **Web:** If `headers` is non-empty, the Web runtime must fetch the image via the Worker/Extension transport, materialize it as a `Blob`, and inject `URL.createObjectURL(blob)` into the reader. If `headers` is empty, a direct `<img src="url">` is permitted.

**Scrambled-Slice Byte Path:**

1. The host delivery pipeline fetches the scrambled image bytes directly through its own transport (OkHttp / Reqwest / Worker-Blob), never through `makinuki_fetch` and never serialized as base64/JSON.
2. The bytes are copied into WASM memory and passed to `unscramble_image()`.
3. The returned clean bytes are handed back to the reader (Web: `Blob` → `URL.createObjectURL`).
4. Failure at any stage yields a zero-length buffer; the host reports `UNSCRAMBLE_FAILED` (Section 6).

```typescript
interface ScrambleInfo {
  layout: "slice" | "shift" | "custom";
  rows: number;               // Grid rows
  cols: number;               // Grid columns
  tileW: number;              // Tile width in px
  tileH: number;              // Tile height in px
  order: number[];            // order[n] = original tile index currently at position n
}
```

---

### 3.6 `PluginResult<T>` (Universal Error Envelope)

Dynamic plugin exports (`search`, `get_details`, `get_pages`) must return their payloads wrapped in this envelope; the static `get_metadata()` / `get_filters()` return raw JSON and never use it. Success and failure are discriminated on the `ok` field; hosts must never infer errors from HTTP codes or thrown exceptions.

```typescript
type PluginResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: { code: ErrorCode; message: string } };
```

* **On success:** `{"ok": true, "data": { ... }}` where `data` holds the `PageResult<MangaItem>`, `MangaDetails`, or `PageItem[]` payload described in Sections 3.3-3.5.
* **On failure:** `{"ok": false, "error": {"code": "PARSING_ERROR", "message": "Failed to find #chapter-list"}}` where `code` must be one of the standardized codes in Section 6; `message` is a human-readable hint for the host debugger.

---

## 4. Multi-Platform Network & Anti-Bot Protocol

Because the WASM plugin invokes `makinuki_fetch`, the host manages environmental networking and challenge resolution.

```
                          ┌────────────────────────────┐
                          │ makinuki_fetch(HttpRequest)│
                          └──────────────┬─────────────┘
                                         │
        ┌────────────────────────────────┼───────────────────────────────┐
        ▼                                ▼                               ▼
   ┌─────────┐                      ┌─────────┐                     ┌─────────┐
   │   Web   │                      │ Android │                     │ Desktop │
   └────┬────┘                      └────┬────┘                     └────┬────┘
        │                                │                               │
  Transport Mode:                 Native OkHttp                   Native Reqwest
  1. Companion Extension          (No CORS, Native Headers)       (No CORS, Native Headers)
  2. Worker Proxy Relay                  │                               │
        │                                │                               │
        └────────────────────────────────┼───────────────────────────────┘
                                         │
                                  Response Status?
                                         │
                   ┌─────────────────────┴─────────────────────┐
                   ▼ 200 OK                                    ▼ 403 Challenge
             Return to WASM                              Trigger Resolution
                                                               │
                                                 ┌─────────────┴─────────────┐
                                                 │ Android: In-App WebView   │
                                                 │ Web: Companion / Solver   │
                                                 │ Desktop: Modal WebView    │
                                                 └─────────────┬─────────────┘
                                                               │
                                                    Extract cf_clearance & UA
                                                               │
                                                    Retry Request to 200 OK
```

### 4.1 Transport Resolution Modes (Web Client)
* **Mode 1 (Companion Extension):** `@makinuki/runtime-web` transmits requests via `window.postMessage` or `chrome.runtime.sendMessage` to the browser extension background script, executing native unrestricted `fetch()` calls.
* **Mode 2 (Worker Proxy):** If the extension is absent, `@makinuki/runtime-web` routes requests through a Cloudflare Worker relay:
  `POST https://proxy.your-domain.workers.dev` with headers payload in the request body.

### 4.2 Anti-Bot & Captcha Challenge Flow
1. If the target returns HTTP `403` or HTML with Cloudflare Turnstile markers, `makinuki_fetch` yields `{ "error": "CLOUDFLARE_BLOCKED", "url": "..." }`.
2. The Host Runtime catches this error and intercepts the execution:
   * **Android:** Launches a modal `BottomSheetDialogFragment` with an Android `WebView`.
   * **Desktop:** Opens a temporary embedded Webview window.
3. The user solves the interactive puzzle/Turnstile check.
4. The host intercepts the resulting `cf_clearance` cookie and matching `User-Agent` string and saves them directly into its persistent storage layer (which backs `makinuki_storage_get`/`set`). Retry behavior then depends on the original request method:
   * **`GET` / `HEAD`:** The host transparently replays the original request once cookies are refreshed.
   * **`POST` / `PUT`:** The host does **not** auto-retry; it returns `{ "error": "CLOUDFLARE_BLOCKED" }` to the plugin so the plugin logic decides whether it is safe to re-invoke.

---

## 5. Registry & Distribution Specification

The public registry serves as a decentralized catalog of pre-compiled sources.

### 5.1 `index.json` Manifest Format
The registry is hosted on GitHub Pages (`https://makinuki.github.io/index.json`):

```json
{
  "version": 1,
  "updatedAt": 1786888000,
  "sources": [
    {
      "id": "asura-scans",
      "name": "Asura Scans",
      "version": "1.0.4",
      "abiVersion": 1,
      "lang": "en",
      "baseUrl": "https://asuracomic.net",
      "iconUrl": "https://makinuki.github.io/icons/asura-scans.png",
      "nsfw": false,
      "wasmUrl": "https://makinuki.github.io/wasm/asura-scans-v1.0.4.wasm",
      "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "minRuntimeVersion": "1.0.0"
    }
  ]
}
```

### 5.2 Source Validation & Security Rules
* **SHA-256 Verification:** Host runtimes must compute the SHA-256 hash of any downloaded `.wasm` file and verify it against `index.json` prior to execution.
* **Sandboxed Permissions:** Plugins are restricted to calling only declared host functions (`makinuki_fetch`, `makinuki_storage_get`, `makinuki_storage_set`, `makinuki_log`).
* **ABI Version Enforcement:** Host runtimes must reject any plugin whose `abiVersion` does not match the runtime's supported ABI version.
* **Version Axes:** `abiVersion` is the ABI contract version (Section 7); `minRuntimeVersion` is the minimum runtime *package* semver that may execute the plugin. They are independent; a plugin may target ABI 1 while requiring a newer runtime package.

---

## 6. Standard Error Codes

All errors across the WASM boundary must use standardized codes:

| Error Code | Category (Ref HTTP) | Description |
| :--- | :--- | :--- |
| `CLOUDFLARE_BLOCKED` | Network / WAF (403 / 503) | Anti-bot or Turnstile challenge encountered. |
| `RATE_LIMITED` | Network / Upstream (429) | Source IP has been throttled by the provider. |
| `NETWORK_TIMEOUT` | Network / Upstream (none) | Request took too long or the connection dropped. |
| `SESSION_REQUIRED` | Auth (401) | Source requires user login or authentication token. |
| `AUTH_EXPIRED` | Auth (none) | Session token is no longer valid; re-login required. |
| `NOT_FOUND` | Network / Upstream (404) | Manga/chapter deleted or URL changed. |
| `SOURCE_OFFLINE` | Network / Upstream (500 / 502 / 504) | Upstream manga site is currently unreachable. |
| `PARSING_ERROR` | Plugin / Parser (none) | HTML markup changed; DOM selectors failed to extract data. |
| `UNSUPPORTED_MEDIA` | Plugin / Parser (none) | Target media format cannot be parsed by this source. |
| `MEMORY_LIMIT_EXCEEDED` | Plugin / Runtime (none) | Plugin exceeded the 16 MB image / 64 MB instance memory budget (Section 2.2). |
| `UNSCRAMBLE_FAILED` | Plugin / Delivery (none) | `unscramble_image` returned a zero-length buffer; tile skipped. |

---

## 7. ABI Versioning Policy

The `abiVersion` integer is the single source of truth for contract compatibility between plugins and host runtimes; `minRuntimeVersion` (registry, Section 5.1) is the runtime *package* semver floor and is **not** a contract axis.

* **Bump Rules:** Any change to exported function signatures, host imports, envelope semantics, or required schemas is a **breaking change** and MUST increment `abiVersion` by 1.
* **Non-Breaking Additions:** New optional fields, optional exports, or new standardized error codes MUST NOT bump `abiVersion`; they must be marked optional and remain backward compatible.
* **Coexistence:** The registry may serve multiple `abiVersion` values simultaneously (`wasmUrl` may encode the source version, e.g. `asura-scans-v1.0.4.wasm`). Hosts select entries whose `abiVersion === runtime.abiVersion` and then apply the Section 5.2 validation rules.
* **Freeze & Changelog:** This document's `1.0.0` release declares **ABI 1 frozen**. Every repository shipping ABI artifacts (`spec`, `pdk-ts`, `sources`) must document contract changes under a `CHANGELOG` heading per release.
* **Explicitly out of ABI 1:** A host-side HTML parsing import (`makinuki_parse_html`) is deferred; if ever introduced, it ships as ABI 2.
* **Decision Log (1.0.0 ratification):** The following decisions are recorded as ratified for ABI 1: plugin error envelope scope (Section 3.6); GET/HEAD-only transparent retry (Section 4.2); 64 MB instance / 16 MB input memory budgets (Section 2.2); zero-length buffer + `UNSCRAMBLE_FAILED` unscramble failure convention (Section 3.5); `abiVersion` / `minRuntimeVersion` as two independent axes; `makinuki_parse_html` excluded from ABI 1.