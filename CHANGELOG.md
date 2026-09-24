# Changelog

All notable changes to the MakiNuki ABI specification are recorded here. This document follows the ABI versioning policy (Section 7 of SPECIFICATION.md).

## [Unreleased]

- Added optional static export `get_settings()` (Section 2.2) and the `SettingSchema` contract (Section 3.7, `settings.schema.json`): sources declare user-configurable options (`checkbox`, `select`, `text` with optional `sensitive`); hosts persist values under the setting id in the plugin storage namespace; plugins read them at call time with `makinuki_storage_get`. A `text` setting with id `base_url` is the well-known domain-override convention.
- Added optional `tags: string[]` to `MangaDetails` (Section 3.4) for sources that distinguish secondary descriptors from their primary `genres` classification.
- Added optional `locked: boolean` to `ChapterItem` (Section 3.4) marking chapters that require payment or entitlement at the source site; `url` on such chapters may point at an external official portal that hosts may open in a browser.
- Added optional `rateLimit` and `retry` hint objects to `SourceMetadata` (Section 3.1) and registry entries (Section 5.1), letting sources suggest politeness and retry policies to hosts.
- Required absolute http(s) URIs for every URL field in dynamic-export payloads (Sections 3.3-3.5).
- `page.schema.json` now requires `metadata` whenever `isScrambled` is true, matching the Section 3.5 text.

## [1.2.0] - 2026-08-23

- Made `coverUrl` optional on `MangaItem` and `MangaDetails` (Section 3.3, Section 3.4): plugins omit it when a title has no usable artwork instead of fabricating placeholder URLs; hosts treat absence as no cover available. Payload schemas drop `coverUrl` from their required lists and now enforce that `covers` may appear only alongside `coverUrl`.
- Added optional `volume: number` to `ChapterItem` (Section 3.4) with a matching `chapter.schema.json` addition, letting clients group chapters by volume without title heuristics.

## [1.1.2] - 2026-08-23

- Added optional `covers: CoverVariant[]` to `MangaItem` and `MangaDetails` (Section 3.3, Section 3.4) with matching schema additions, enabling sources to expose additional cover renditions.

## [1.1.0] - 2026-08-19

- Added optional `allowedHosts: string[]` to `SourceMetadata` (Section 3.1) and to registry entries in `index.json` (Section 5.1), with matching additions to `metadata.schema.json` and `index.schema.json`.

## [1.0.0] - 2026-08-17

ABI 1 is declared frozen. The contract defined in this release is the baseline for all plugin and host implementations; breaking changes now require incrementing `abiVersion` (Section 7).

- Version header: `1.0.0`, status `Approved / Frozen (ABI 1)` (was `0.1.0-draft`, `Draft`).
- Ratified ABI 1 decisions recorded in the Section 7 decision log: error envelope scope (3.6); GET/HEAD-only transparent retry (4.2); memory budgets (2.2); zero-length buffer + `UNSCRAMBLE_FAILED` (3.5); `abiVersion` / `minRuntimeVersion` as independent axes; `makinuki_parse_html` excluded (deferred to ABI 2).
- JSON Schemas in `schemas/` are unchanged at this release and remain valid draft-07 with `additionalProperties: false` and `abiVersion: 1`.
