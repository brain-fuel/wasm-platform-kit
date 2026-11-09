# Wasm Platform Kit

This repository owns the reusable component runtime, capability providers,
direct WIT-to-Haskell generator and generic conformance fixtures. Application
interfaces and compiler behavior belong in consuming repositories.

Use Allman braces where the established formatter supports them, then Google
language conventions. Run the pinned Prettier/brace-style formatter, Ormolu
0.9.0.0 and nightly-2026-10-22 rustfmt; do not hand-format generated outputs.
Preserve explicit denied, unsupported, cancelled, exhausted and failed outcomes.
Unsupported WIT and deployment profiles must fail without a less isolated fallback.
Keep deployment registration under the embedding application's authority.
Record design changes in Canon. Automated tests are execution evidence; never
manufacture human vetting or claim a proof from a passing test suite.
