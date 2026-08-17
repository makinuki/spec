# Changelog

All notable changes to the MakiNuki ABI specification are recorded here. This document follows the ABI versioning policy (Section 7 of SPECIFICATION.md).

## [1.0.0] - 2026-08-17

ABI 1 is declared frozen. The contract defined in this release is the baseline for all plugin and host implementations; breaking changes now require incrementing `abiVersion` (Section 7).

- Version header: `1.0.0`, status `Approved / Frozen (ABI 1)` (was `0.1.0-draft`, `Draft`).
- Ratified ABI 1 decisions recorded in the Section 7 decision log: error envelope scope (3.6); GET/HEAD-only transparent retry (4.2); memory budgets (2.2); zero-length buffer + `UNSCRAMBLE_FAILED` (3.5); `abiVersion` / `minRuntimeVersion` as independent axes; `makinuki_parse_html` excluded (deferred to ABI 2).
- JSON Schemas in `schemas/` are unchanged at this release and remain valid draft-07 with `additionalProperties: false` and `abiVersion: 1`.