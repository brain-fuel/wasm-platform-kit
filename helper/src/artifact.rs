//! Trusted native artifacts and explicit source compilation.
//! ref:DEC-host-sdk-precompiled-node
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs::File;
#[cfg(feature = "compiler")]
use std::fs::OpenOptions;
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::path::Path;
#[cfg(not(feature = "compiler"))]
use wasmtime::bail;
use wasmtime::component::Component;
#[cfg(feature = "compiler")]
use wasmtime::error::Context;
use wasmtime::{Config, Engine, Result, ensure};

pub const CONFIGURATION: &str = "host-sdk-0.2.0/wasmtime-50.0.1/fuel-v1";
pub const TARGET: &str = env!("HOST_SDK_TARGET");
#[cfg(feature = "compiler")]
const MAX_WASM: u64 = 128 * 1024 * 1024;
const MAX_NATIVE: u64 = 512 * 1024 * 1024;

/// Embedding-approved compiler output identity; guest manifests cannot confer this authority. ref:DEC-host-sdk-precompiled-node
#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Registration
{
    pub component_sha256: String,
    pub native_sha256: String,
    pub configuration: String,
    pub target: String,
}

/// Reuses explicit target and fuel settings across compilation and execution. ref:DEC-host-sdk-precompiled-node
pub fn engine() -> Result<Engine>
{
    engine_for(TARGET)
}

/// Uses explicit baseline CPU settings for a supported native artifact target. ref:DEC-host-sdk-native-platform-packaging
fn engine_for(target: &str) -> Result<Engine>
{
    ensure!(
        [
            "aarch64-apple-darwin",
            "x86_64-apple-darwin",
            "aarch64-unknown-linux-gnu",
            "x86_64-unknown-linux-gnu"
        ]
        .contains(&target),
        "unsupported native target"
    );
    let mut config = Config::new();
    config.consume_fuel(true);
    // An explicit target disables host-inferred CPU extensions when compiling.
    config.target(target)?;
    Engine::new(&config)
}

fn valid_digest(value: &str) -> bool
{
    value.len() == 64
        && value
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

#[cfg(feature = "compiler")]
fn read_wasm(path: &Path, expected: Option<&str>) -> Result<Vec<u8>>
{
    let mut bytes = Vec::new();
    File::open(path)?
        .take(MAX_WASM + 1)
        .read_to_end(&mut bytes)?;
    ensure!(bytes.len() as u64 <= MAX_WASM, "component size exhausted");
    if let Some(expected) = expected
    {
        ensure!(valid_digest(expected), "invalid component digest");
        ensure!(
            format!("{:x}", Sha256::digest(&bytes)) == expected,
            "component integrity mismatch"
        );
    }
    Ok(bytes)
}

/// Verifies and maps a private immutable snapshot of registered compiler output. ref:DEC-host-sdk-precompiled-node
pub fn load_native(
    engine: &Engine,
    path: &Path,
    registration: &Registration,
    component: &str,
) -> Result<Component>
{
    ensure!(
        registration.configuration == CONFIGURATION && registration.target == TARGET,
        "native configuration or target mismatch"
    );
    ensure!(
        valid_digest(component) && registration.component_sha256 == component,
        "native component identity mismatch"
    );
    ensure!(
        valid_digest(&registration.native_sha256),
        "invalid native digest"
    );
    // Copy once into a private, already-unlinked file. Hash exactly the bytes that
    // will be mapped; replacing or modifying the input can never change that map.
    // Guest WASI has no filesystem access to this descriptor or its former name.
    let mut snapshot = tempfile::tempfile()?;
    let mut source = File::open(path)?.take(MAX_NATIVE + 1);
    let mut hash = Sha256::new();
    let mut total = 0_u64;
    let mut buffer = [0_u8; 64 * 1024];
    loop
    {
        let count = source.read(&mut buffer)?;
        if count == 0
        {
            break;
        }
        total += count as u64;
        ensure!(total <= MAX_NATIVE, "native artifact size exhausted");
        hash.update(&buffer[..count]);
        snapshot.write_all(&buffer[..count])?;
    }
    ensure!(
        format!("{:x}", hash.finalize()) == registration.native_sha256,
        "native artifact integrity mismatch"
    );
    let descriptor = snapshot.as_raw_fd();
    #[cfg(target_os = "linux")]
    let private_path = format!("/proc/self/fd/{descriptor}");
    #[cfg(target_os = "macos")]
    let private_path = format!("/dev/fd/{descriptor}");
    // SAFETY: registration is supplied by trusted embedding code, never the
    // guest manifest. It pins output of our trusted compiler and its settings.
    // The verified snapshot has no pathname and is never mutated again. Wasmtime
    // owns its mmap after the descriptors close; no guest can mutate the backing.
    unsafe { Component::deserialize_file(engine, private_path) }
}

/// Compiles portable Wasm only in the explicitly selected compiler-enabled helper. ref:DEC-host-sdk-precompiled-node
pub fn load_source(engine: &Engine, path: &Path, digest: &str) -> Result<Component>
{
    #[cfg(feature = "compiler")]
    {
        Component::new(engine, read_wasm(path, Some(digest))?)
    }
    #[cfg(not(feature = "compiler"))]
    {
        let _ = (engine, path, digest);
        bail!("source compilation unavailable in execution-only runtime")
    }
}

/// Emits bounded native code and its registration for the trusted build. ref:DEC-host-sdk-precompiled-node
pub fn command() -> Result<bool>
{
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.is_empty()
    {
        return Ok(false);
    }
    ensure!(
        (args.len() == 3 || args.len() == 4) && args[0] == "--precompile",
        "expected --precompile INPUT OUTPUT [TARGET]"
    );
    #[cfg(feature = "compiler")]
    {
        let bytes = read_wasm(Path::new(&args[1]), None)?;
        let target = args
            .get(3)
            .map(|value| value.to_str().context("invalid target encoding"))
            .transpose()?
            .unwrap_or(TARGET);
        let compiled = engine_for(target)?.precompile_component(&bytes)?;
        ensure!(
            compiled.len() as u64 <= MAX_NATIVE,
            "native artifact size exhausted"
        );
        let registration = Registration {
            component_sha256: format!("{:x}", Sha256::digest(&bytes)),
            native_sha256: format!("{:x}", Sha256::digest(&compiled)),
            configuration: CONFIGURATION.to_owned(),
            target: target.to_owned(),
        };
        let mut output = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&args[2])
            .context("native output must be new")?;
        output.write_all(&compiled)?;
        println!("{}", serde_json::to_string(&registration)?);
        Ok(true)
    }
    #[cfg(not(feature = "compiler"))]
    bail!("precompilation unavailable in execution-only runtime")
}
