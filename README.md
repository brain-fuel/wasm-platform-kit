# Wasm Platform Kit — development preview

A capability-scoped platform SDK for WebAssembly applications in Node and browsers.
Haskell bindings are generated directly from WIT using upstream `wit-parser`;
there is no authored C bridge. GHC scalar foreign declarations, its RTS and libc
remain below the typed application interface. A Rust guest tests the same host
contract. Application-specific adapters live in their consuming repositories.

## Release status

Version 0.2.0 is released to npm under the owner's 9 November 2026 decision
(`DEC-wpk-release-acceptance`). macOS and Linux ARM64 have recorded native
execution. Linux x64 is accepted on the installation lifecycle executed under
x64 emulation; native x64 hardware has not been recorded. **macOS x64 is
cross-built and unverified: no execution has been recorded on that platform.**
Existing acceptance JSON files record the runs they name; they do not certify
other platforms or later changes. Mandatory definition validation passes, while
optional law verification is not selected. Human Canon review remains pending.
See `DEC-wpk-installation-preparation` for the installation contract.

The npm lifecycle tests verify prebuilt installation, forced source preparation,
missing-prebuilt preparation, failure cleanup and execution with the compiler
removed. They do not establish full consumer application acceptance.

## Packages

- `wasm-platform-kit`: Node/browser runtime, broker and public declarations.
- `wasm-platform-kit-<platform>`: execution-only Wasmtime helper, explicit source compiler and WIT metadata tool.
- `wasm-platform-kit-build`: generation, packaging, WIT and Haskell support sources.

The runtime tarball contains no compiler application, malicious fixtures or build
tools.
Platform packages target macOS and glibc Linux on x64 and ARM64. A cross-build
alone is not execution evidence; the release status above names what has run. Native
Windows and musl are unsupported; Windows users can use WSL. Consumers need no
Haskell or Rust compiler.

## Development

Use Node 22+, Rust with wasm32-wasip2, GHC wasm32 9.14.1.20260731,
wasm-tools 1.257.1, Binaryen and Ormolu 0.9.0.0. `HOST_SDK_TOOLCHAIN` selects a
GHC Wasm toolchain directory (default ~/.ghc-wasm); `HOST_SDK_GHC_ENV` overrides
its environment file. These are build-time settings, never guest environment.

```sh
npm ci
npm run build
npm test
npm run pack:local
```

`dist/packages.json` records the local runtime, build-tool and platform tarballs.
Install the runtime, build tools and matching platform into an authoring project
with `npm install <tarballs...>`.
Builds and tests use this repository's own dependencies and generic fixtures.
No LawSpec checkout, compiler or application is required.

`npm run build:platform` rebuilds just the native helpers and WIT tool from Rust,
without a Haskell installation. Linux builds additionally use Cargo Zigbuild
0.24.0 and Zig 0.16.0 with an explicit glibc 2.28 target; these are build-only
dependencies. `node tools/platform.mjs --build linux-x64` (or `linux-arm64`)
supports cross-compilation when the Rust target is installed. Linux staging
requires `llvm-readobj` or `readelf`; `HOST_SDK_READOBJ` can select the executable.
The actual linked glibc requirement must be at most 2.28, independent of the
builder's libc. ref:DEC-host-sdk-linux-abi-baseline

To collect cross-built binaries, place
`host-sdk-runtime`, `host-sdk-source-runtime` and `wit-haskell` in
`platforms/<platform>/bin/`, then run `node tools/platform.mjs --stage <platform>`.
Staging checks executable architecture and records file hashes. `pack:local`
includes every staged platform in the `platforms` map in `dist/packages.json`.
The `platform` field remains an alias for the build host's package.

## Authoring and embedding

The build package exports `generateBindings`, `packageComponent`, `runHaskell`,
`supportDirectory` and `witDirectory`. Generate Haskell into a project-owned
output directory, implement `Application`, compile against the supplied Cabal
support library, and package the core Wasm with its WIT world. Packaging emits
Node and plain-browser entrypoints, declarations, worker and runtime assets,
an integrity manifest and deployment-header templates into the application's
output directory. It never modifies an installed SDK package.

The generated `node.mjs` and `browser.mjs` export `createApplication(options)`;
the returned instance has `invoke`, `identity`, `close` and `revoke`. Deploy the
whole generated browser directory. Each generated worker pins its approved
manifest digest before importing glue. The page entrypoint also pins registration.
The embedding build alone chooses registered components; plugin manifests cannot
register JavaScript. Application permissions remain a separate immutable `grants`
argument. Informational component `requirements` confer no permissions.

Files, approved network destinations, namespaced storage, explicit environment,
validated native callbacks and isolated text UI are mediated capabilities. Node
uses Wasmtime and cap-std; browser handles remain in the page broker. Redirects
cannot expand grants. Revocation terminates the instance and aborts cooperative
provider work. Trusted escape providers require the explicitly trusted profile.

Browsers require JSPI, secure context, workers and WebCrypto. Optional isolated
deployment requires effective COOP/COEP. WebKit file tests use a persistent
profile because its ephemeral OPFS implementation rejects handles. Missing
features fail explicitly. File-picker consent and server authorization remain
embedding-application responsibilities.

## Precompiled Node execution and source builds

`packageComponent` emits a native artifact for the build platform and a separate
`node-registration.mjs`. The generated Node entrypoint supplies this trusted
registration automatically. Consumers do not locate native files or workers.

Wire the generated `install.mjs` into the embedding package's `postinstall`
script. Installation verifies its approved prebuilt artifact or compiles the
pinned portable Wasm with the shipped compiler helper. Neither path requires
Rust or Haskell on the consumer machine.

```sh
npm install
# Explicitly compile during installation instead of selecting prebuilt code:
WASM_PLATFORM_KIT_BUILD_FROM_SOURCE=1 npm rebuild
```

```js
const app = await createApplication(); // loads prepared native code; never builds
```

Runtime `compilation: 'source'` is rejected. If lifecycle scripts were disabled
and no prebuilt artifact is available, run `npm rebuild` with scripts enabled.
Compilation has a separate 15-minute installation deadline; it does not relax
runtime guest limits. Failed preparation never publishes a partial receipt or
replaces a previously valid receipt. Local compilation products are excluded
from subsequent npm archives. ref:DEC-wpk-installation-preparation

To rebuild the SDK and its Haskell fixtures, use the development commands above.
Application development builds still use GHC followed by `packageComponent`.

Direct `createHost` callers must supply embedding-approved `nativeArtifacts`
registration for a prepared artifact. A guest manifest
cannot authorize native code even if it carries matching hashes. The registration
binds component and native digests, target and pinned engine configuration. The
helper hashes a bounded copy into a private, already-unlinked file and maps that
immutable snapshot. Input mutation after verification cannot change executable
pages. Missing, corrupt or incompatible artifacts fail without an implicit
compilation fallback. Native artifacts are trusted compiler output, not safe
inputs merely because they have a checksum. ref:DEC-host-sdk-precompiled-node

The default helper is built without Cranelift. The installation-only compiler
helper retains it. Both preserve fuel and capability enforcement. Execution
identity includes compilation mode, configuration, target and native digest;
applications must retain those distinctions in cache/evidence keys. Portable
Wasm is still included for installation compilation and browser generation. Browser
engines continue to compile portable Wasm independently.

For multi-platform distribution, the build package exports
`precompileNative({component, output, target})` and `nativeTargets`. Precompilation
returns the trusted registration receipt; write it alongside the resulting file
in the build pipeline. `packageNativeArtifacts` takes a component `directory`
and an `artifacts` array of `{platform, file, registration}`. Supplying
`packagePrefix`, `version` and `packageDirectory` emits optional platform packages;
`license` and `licenseFile` carry the application's licensing. It returns the
optional dependency map for the application package manifest. Without a prefix,
it stages inline artifacts. Both forms generate trusted Node registration and
verify every input receipt against the component and native file before writing
authority. ref:DEC-host-sdk-native-platform-packaging

An optional native package is needed for default execution, but its absence does
not prevent explicit source compilation. The generated registration resolves
native files lazily so consumers never have to provide platform paths.

## Limits and trust

The 0.2.0 generator accepts memory32 bool/string and signed and unsigned
8/16/32/64-bit integers, records, enums, variants, lists, options, results and
imported or exported resources. Byte lists use Haskell ByteString. Both scalar
and aggregate results are supported; large parameter tuples use upstream
canonical indirect layouts. Resource constructors, methods and static functions
are generated. Floats, chars, flags, tuples, WIT async/future/stream types and
variants over 256 cases remain explicitly unsupported by the Haskell emitter.
Asynchronous host operations use the existing JSPI/Wasmtime integration.

Exported resources retain typed application state in `ResourceTypes` through
StablePtr. Generated helpers allocate, read and drop them; application modules
do not manipulate pointers. Consumed-owner flags and dynamic call epochs reject
repeated transfers and retained borrows. Destructors free retained state and run
consumer cleanup, using a safe GHC FFI drop import for synchronous re-entry.
Emergency termination releases the whole process or worker; it cannot promise
that application destructors finish. Resource lifetimes use bracket and runtime
validation, not linear proof. The generator, canonical codecs, initializer, build
instrumentation, runtime and providers are trusted code.

Fuel on Node, worker deadlines, guest memory/table bounds, host resource limits,
request/output limits and storage quotas bound execution. These are not universal
limits on browser or native host heaps or trusted callback allocations. The
containment suite establishes scoped execution evidence, not certification.

Canonical decisions and reference sources are in this repository. Human review
is pending. The original implementation was extracted from the LawSpec formatting
pilot; that application's adapter and parity tests remain in LawSpec.

Canon grammar snapshots and their provenance are checked in under `.ricestax/`;
review configuration has no dependency on a neighboring checkout. Use Canon
0.2.3 with this repository. The LawSpec model can be checked by an independently
installed LawSpec CLI; it is not needed to build or test the runtime.

## Generated application façades

Generated `node.mjs` and `browser.mjs` now return a client with named asynchronous
WIT methods as well as the low-level `invoke` operation. Adjacent `.d.mts` files
contain generated input, result and opaque resource types. Every method accepts
an optional final `{signal}`. Constructors appear as `new<Resource>`, resource
methods are asynchronous, and `dispose()` releases the resource. Per-call
cancellation still revokes that instance; separate long-lived UI/job lifecycles
are not yet implemented.

Use JavaScript `bigint` for WIT `u64`/`s64`, including small values. Node's helper
protocol preserves all bits and rejects Numbers and out-of-range values. Typed
byte-list façades use `Uint8Array`. Resource objects are bound to their creating
client. Copies of serialized IDs and resources from another instance convey no
access. The Wasmtime helper and browser worker cap retained public resources at
1024 per instance.

The implementation follows WIT's resource new/rep/drop intrinsics and upstream
canonical parameter/result layouts. See the [WIT resource specification](https://github.com/WebAssembly/component-model/blob/main/design/mvp/WIT.md#item-resource)
and [canonical ABI](https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md).
The generated Haskell/backend support remains bespoke trusted implementation;
`wit-parser`, component validation, Wasmtime and jco supply the upstream machinery.
ref:DEC-host-sdk-typed-application-boundary
