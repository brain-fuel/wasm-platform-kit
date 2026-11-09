//! Wasmtime integration and capability handles only; no application behavior.
//! ref:DEC-host-sdk-direct-haskell
use cap_std::ambient_authority;
use cap_std::fs::{Dir, OpenOptions};
use serde::Deserialize;
use serde_json::{Value, json};
mod artifact;
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::path::Component as PathComponent;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, Stdin, Stdout};
use wasmtime::component::{
    Linker, Resource, ResourceAny, ResourceTable, ResourceTableError, Type, Val,
};
use wasmtime::error::Context;
use wasmtime::{ResourceLimiter, Result, Store, Trap, bail, ensure};
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder, WasiCtxView, WasiView};

wasmtime::component::bindgen!({
    path: "../wit",
    world: "embedding",
    imports: { default: async | trappable },
    with: { "host:sdk/host.provider": Provider },
});
use host::sdk::host::{Error as HostError, Host, HostProvider, Method, Request, Status};

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Grant
{
    kind: String,
    #[serde(default)]
    root: Option<String>,
    #[serde(default)]
    read: bool,
    #[serde(default)]
    write: bool,
}
/// Names a grant within this store; the component resource table controls handle validity.
pub struct Provider
{
    name: String,
}
struct Limits
{
    memory: usize,
    used: usize,
    exhausted: bool,
}
impl ResourceLimiter for Limits
{
    fn memory_growing(
        &mut self,
        current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> Result<bool>
    {
        let increase = desired.saturating_sub(current);
        if increase > self.memory.saturating_sub(self.used)
            || maximum.is_some_and(|max| desired > max)
        {
            self.exhausted = true;
            bail!("memory budget exhausted");
        }
        self.used += increase;
        Ok(true)
    }
    fn memory_grow_failed(&mut self, error: wasmtime::Error) -> Result<()>
    {
        self.exhausted = true;
        Err(error)
    }
    fn table_growing(
        &mut self,
        _current: usize,
        desired: usize,
        maximum: Option<usize>,
    ) -> Result<bool>
    {
        if desired > 1_000_000 || maximum.is_some_and(|max| desired > max)
        {
            self.exhausted = true;
            bail!("table budget exhausted");
        }
        Ok(true)
    }
    fn instances(&self) -> usize
    {
        32
    }
    fn memories(&self) -> usize
    {
        8
    }
    fn tables(&self) -> usize
    {
        8
    }
}
struct State
{
    wasi: WasiCtx,
    table: ResourceTable,
    limits: Limits,
    grants: BTreeMap<String, Grant>,
    directories: BTreeMap<String, Dir>,
    input: BufReader<Stdin>,
    output: Stdout,
    remaining: u64,
    bytes: usize,
}
impl WasiView for State
{
    fn ctx(&mut self) -> WasiCtxView<'_>
    {
        WasiCtxView {
            ctx: &mut self.wasi,
            table: &mut self.table,
        }
    }
}
// Write within the directory capability and rename only a complete file.
fn write_atomic(directory: &Dir, path: &str, text: &str) -> std::io::Result<()>
{
    use std::sync::atomic::{AtomicU64, Ordering};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let parent = std::path::Path::new(path)
        .parent()
        .unwrap_or(std::path::Path::new(""));
    if !parent.as_os_str().is_empty()
    {
        directory.create_dir_all(parent)?;
    }
    let temporary = parent.join(format!(
        ".host-sdk-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let mut file =
        directory.open_with(&temporary, OpenOptions::new().write(true).create_new(true))?;
    let outcome = (|| {
        file.write_all(text.as_bytes())?;
        drop(file);
        directory.rename(&temporary, directory, path)
    })();
    if outcome.is_err()
    {
        let _ = directory.remove_file(&temporary);
    }
    outcome
}

fn problem(code: Status, message: impl Into<String>) -> HostError
{
    HostError {
        code,
        message: message.into(),
    }
}
fn denied(message: impl Into<String>) -> HostError
{
    problem(Status::Denied, message)
}
async fn read_message(input: &mut BufReader<Stdin>, max: usize) -> Result<Value>
{
    let mut bytes = Vec::new();
    loop
    {
        let chunk = input.fill_buf().await?;
        ensure!(!chunk.is_empty(), "host channel closed");
        let count = chunk
            .iter()
            .position(|b| *b == b'\n')
            .map_or(chunk.len(), |i| i + 1);
        ensure!(bytes.len() + count <= max, "request exhausted");
        let complete = chunk[count - 1] == b'\n';
        bytes.extend_from_slice(&chunk[..count]);
        input.consume(count);
        if complete
        {
            return Ok(serde_json::from_slice(&bytes)?);
        }
    }
}
async fn send(output: &mut Stdout, value: Value) -> Result<()>
{
    let mut bytes = serde_json::to_vec(&value)?;
    bytes.push(b'\n');
    output.write_all(&bytes).await?;
    output.flush().await?;
    Ok(())
}
impl HostProvider for State
{
    async fn drop(&mut self, resource: Resource<Provider>) -> Result<()>
    {
        self.table.delete(resource)?;
        Ok(())
    }
}
impl Host for State
{
    async fn acquire(&mut self, name: String) -> Result<Result<Resource<Provider>, HostError>>
    {
        if self.remaining == 0
        {
            return Ok(Err(problem(Status::Exhausted, "request limit")));
        }
        self.remaining -= 1;
        if !self.grants.contains_key(&name)
        {
            return Ok(Err(denied("provider not granted")));
        }
        Ok(Ok(self.table.push(Provider { name })?))
    }
    async fn perform(
        &mut self,
        resource: Resource<Provider>,
        request: Request,
    ) -> Result<Result<String, HostError>>
    {
        if self.remaining == 0
        {
            return Ok(Err(problem(Status::Exhausted, "request limit")));
        }
        self.remaining -= 1;
        let name = self.table.get(&resource)?.name.clone();
        let grant = self
            .grants
            .get(&name)
            .context("missing immutable grant")?
            .clone();
        if grant.kind == "files"
        {
            let (path, content, allowed) = match &request
            {
                Request::ReadText(path) => (path.as_str(), None, grant.read),
                Request::WriteText(write) =>
                {
                    (write.key.as_str(), Some(write.value.as_str()), grant.write)
                }
                _ => return Ok(Err(denied("operation outside file grant"))),
            };
            if !allowed
                || path.is_empty()
                || std::path::Path::new(path)
                    .components()
                    .any(|p| !matches!(p, PathComponent::Normal(_)))
            {
                return Ok(Err(denied("file access outside grant")));
            }
            let directory = self
                .directories
                .get(&name)
                .context("missing directory capability")?;
            let result = if let Some(text) = content
            {
                if text.len() > self.bytes
                {
                    return Ok(Err(problem(Status::Exhausted, "write limit")));
                }
                write_atomic(directory, path, text).map(|_| String::new())
            }
            else
            {
                directory.open(path).and_then(|file| {
                    let mut bytes = Vec::new();
                    file.take(self.bytes as u64 + 1).read_to_end(&mut bytes)?;
                    if bytes.len() > self.bytes
                    {
                        return Err(std::io::Error::other("response exhausted"));
                    }
                    String::from_utf8(bytes).map_err(std::io::Error::other)
                })
            };
            return Ok(result.map_err(|error| {
                let code = if error.kind() == std::io::ErrorKind::PermissionDenied
                {
                    Status::Denied
                }
                else if error.to_string() == "response exhausted"
                {
                    Status::Exhausted
                }
                else
                {
                    Status::Failed
                };
                problem(code, error.to_string())
            }));
        }
        let request = match request
        {
            Request::ReadText(value) => json!({"tag":"read-text", "val":value}),
            Request::WriteText(value) =>
            {
                json!({"tag":"write-text", "val":{"key":value.key,"value":value.value}})
            }
            Request::Fetch(value) =>
            {
                json!({"tag":"fetch", "val":{"url":value.url,"method":match value.method {Method::Get=>"get",Method::Post=>"post"},"body":value.body}})
            }
            Request::GetValue(value) => json!({"tag":"get-value", "val":value}),
            Request::PutValue(value) =>
            {
                json!({"tag":"put-value", "val":{"key":value.key,"value":value.value}})
            }
            Request::Render(value) => json!({"tag":"render", "val":value}),
            Request::Invoke(value) => json!({"tag":"invoke", "val":value}),
        };
        if serde_json::to_vec(&request)?.len() > self.bytes
        {
            return Ok(Err(problem(Status::Exhausted, "request bytes")));
        }
        send(
            &mut self.output,
            json!({"hostRequest": {"provider":name,"request":request}}),
        )
        .await?;
        let response = read_message(&mut self.input, self.bytes * 6 + 4096).await?;
        if let Some(error) = response.get("error")
        {
            let status = match error["code"].as_str()
            {
                Some("denied") => Status::Denied,
                Some("unsupported") => Status::Unsupported,
                Some("cancelled") => Status::Cancelled,
                Some("exhausted") => Status::Exhausted,
                _ => Status::Failed,
            };
            return Ok(Err(problem(
                status,
                error["message"].as_str().unwrap_or("provider failed"),
            )));
        }
        let text = response["value"]
            .as_str()
            .context("host result must be text")?;
        if text.len() > self.bytes
        {
            return Ok(Err(problem(Status::Exhausted, "response bytes")));
        }
        Ok(Ok(text.to_owned()))
    }
}

// Tokens are scoped to this helper; the public SDK additionally checks object identity.
// Monotonic IDs prevent a stale token from aliasing a newly allocated resource.
#[derive(Default)]
struct GuestResources
{
    next: u64,
    live: BTreeMap<String, ResourceAny>,
}
impl GuestResources
{
    fn insert(&mut self, resource: ResourceAny) -> Result<Value>
    {
        ensure!(resource.owned(), "unsupported: borrowed public result");
        ensure!(self.live.len() < 1024, "resource allocation exhausted");
        self.next = self
            .next
            .checked_add(1)
            .context("resource identity exhausted")?;
        let key = self.next.to_string();
        self.live.insert(key.clone(), resource);
        Ok(json!({"$host-sdk-resource": key}))
    }
    fn key(value: &Value) -> Result<&str>
    {
        ensure!(
            value.as_object().map(|o| o.len()) == Some(1),
            "invalid resource token"
        );
        value["$host-sdk-resource"]
            .as_str()
            .context("expected resource token")
    }
}

// JavaScript Numbers cannot carry the complete WIT u64/s64 domains. Never accept
// a rounded JSON number here; only the SDK's explicit decimal integer marker.
fn wide_integer(value: &Value) -> Result<&str>
{
    let object = value.as_object().context("expected bigint")?;
    ensure!(object.len() == 1, "invalid bigint marker");
    let text = object
        .get("$host-sdk-integer")
        .and_then(Value::as_str)
        .context("expected bigint")?;
    let digits = text.strip_prefix('-').unwrap_or(text);
    ensure!(
        !digits.is_empty()
            && digits.bytes().all(|c| c.is_ascii_digit())
            && (digits.len() == 1 || !digits.starts_with('0')),
        "invalid bigint digits"
    );
    Ok(text)
}

fn from_json(ty: Type, value: &Value, resources: &mut GuestResources) -> Result<Val>
{
    Ok(match ty
    {
        Type::Own(expected) | Type::Borrow(expected) =>
        {
            let key = GuestResources::key(value)?;
            let resource = *resources
                .live
                .get(key)
                .context("invalid or released resource")?;
            ensure!(resource.ty() == expected, "wrong resource type");
            if matches!(ty, Type::Own(_))
            {
                resources.live.remove(key);
            }
            Val::Resource(resource)
        }
        Type::String => Val::String(value.as_str().context("expected string")?.to_owned()),
        Type::Bool => Val::Bool(value.as_bool().context("expected bool")?),
        Type::U64 => Val::U64(wide_integer(value)?.parse()?),
        Type::S64 => Val::S64(wide_integer(value)?.parse()?),
        Type::S8 => Val::S8(value.as_i64().context("expected s8")?.try_into()?),
        Type::S16 => Val::S16(value.as_i64().context("expected s16")?.try_into()?),
        Type::S32 => Val::S32(value.as_i64().context("expected s32")?.try_into()?),
        Type::U16 => Val::U16(value.as_u64().context("expected u16")?.try_into()?),
        Type::U32 => Val::U32(value.as_u64().context("expected u32")?.try_into()?),
        Type::U8 => Val::U8(value.as_u64().context("expected u8")?.try_into()?),
        Type::List(list) => Val::List(
            value
                .as_array()
                .context("expected list")?
                .iter()
                .map(|v| from_json(list.ty(), v, resources))
                .collect::<Result<_>>()?,
        ),
        Type::Record(record) => Val::Record(
            record
                .fields()
                .map(|field| {
                    Ok((
                        field.name.to_owned(),
                        from_json(field.ty, &value[field.name], resources)?,
                    ))
                })
                .collect::<Result<_>>()?,
        ),
        Type::Enum(_) => Val::Enum(value.as_str().context("expected enum")?.to_owned()),
        Type::Variant(variant) =>
        {
            let tag = value["tag"].as_str().context("expected variant tag")?;
            let case = variant
                .cases()
                .find(|c| c.name == tag)
                .context("unknown variant")?;
            Val::Variant(
                tag.to_owned(),
                case.ty
                    .map(|ty| from_json(ty, &value["val"], resources).map(Box::new))
                    .transpose()?,
            )
        }
        Type::Result(result) =>
        {
            let tag = value["tag"].as_str().context("expected result tag")?;
            let mut payload = |ty: Option<Type>| {
                ty.map(|ty| from_json(ty, &value["val"], resources).map(Box::new))
                    .transpose()
            };
            Val::Result(match tag
            {
                "ok" => Ok(payload(result.ok())?),
                "err" => Err(payload(result.err())?),
                _ => bail!("invalid result tag"),
            })
        }
        Type::Option(option) => Val::Option(
            if value.is_null()
            {
                None
            }
            else
            {
                Some(Box::new(from_json(option.ty(), value, resources)?))
            },
        ),
        _ => bail!("unsupported public argument type"),
    })
}
fn to_json(value: &Val, resources: &mut GuestResources) -> Result<Value>
{
    Ok(match value
    {
        Val::Resource(resource) => resources.insert(*resource)?,
        Val::String(v) | Val::Enum(v) => json!(v),
        Val::Bool(v) => json!(v),
        Val::U64(v) => json!({"$host-sdk-integer": v.to_string()}),
        Val::S64(v) => json!({"$host-sdk-integer": v.to_string()}),
        Val::S8(v) => json!(v),
        Val::S16(v) => json!(v),
        Val::S32(v) => json!(v),
        Val::U16(v) => json!(v),
        Val::U32(v) => json!(v),
        Val::U8(v) => json!(v),
        Val::Record(fields) => Value::Object(
            fields
                .iter()
                .map(|(k, v)| Ok((k.clone(), to_json(v, resources)?)))
                .collect::<Result<_>>()?,
        ),
        Val::List(values) => Value::Array(
            values
                .iter()
                .map(|v| to_json(v, resources))
                .collect::<Result<_>>()?,
        ),
        Val::Option(value) => value
            .as_ref()
            .map(|v| to_json(v, resources))
            .transpose()?
            .unwrap_or(Value::Null),
        Val::Variant(tag, value) =>
        {
            json!({"tag":tag,"val":value.as_ref().map(|v|to_json(v, resources)).transpose()?})
        }
        Val::Result(result) => match result
        {
            Ok(value) =>
            {
                json!({"tag":"ok","val":value.as_ref().map(|v|to_json(v, resources)).transpose()?})
            }
            Err(value) =>
            {
                json!({"tag":"err","val":value.as_ref().map(|v|to_json(v, resources)).transpose()?})
            }
        },
        _ => bail!("unsupported public result type"),
    })
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()>
{
    if artifact::command()?
    {
        return Ok(());
    }
    let mut input = BufReader::new(tokio::io::stdin());
    let init = read_message(&mut input, 1024 * 1024).await?;
    let bytes = init["limits"]["bytes"]
        .as_u64()
        .context("bytes limit required")? as usize;
    let memory = init["limits"]["memory"]
        .as_u64()
        .context("memory limit required")? as usize;
    let fuel = init["limits"]["fuel"].as_u64().context("fuel required")?;
    let requests = init["limits"]["requests"]
        .as_u64()
        .context("request limit required")?;
    ensure!(
        bytes <= 64 * 1024 * 1024 && memory <= 1024 * 1024 * 1024 && fuel > 0,
        "invalid limits"
    );
    let grants: BTreeMap<String, Grant> = serde_json::from_value(init["grants"].clone())?;
    let mut directories = BTreeMap::new();
    for (name, grant) in &grants
    {
        if grant.kind == "files"
        {
            directories.insert(
                name.clone(),
                Dir::open_ambient_dir(
                    grant.root.as_ref().context("file root required")?,
                    ambient_authority(),
                )?,
            );
        }
    }
    let engine = artifact::engine()?;
    let hash = init["sha256"]
        .as_str()
        .context("component identity required")?;
    let mode = init["compilation"]
        .as_str()
        .context("compilation mode required")?;
    let component = match mode
    {
        "precompiled" =>
        {
            let registration: artifact::Registration =
                serde_json::from_value(init["nativeRegistration"].clone())?;
            artifact::load_native(
                &engine,
                std::path::Path::new(
                    init["nativeArtifact"]
                        .as_str()
                        .context("native artifact required")?,
                ),
                &registration,
                hash,
            )?
        }
        "source" => artifact::load_source(
            &engine,
            std::path::Path::new(init["component"].as_str().context("component required")?),
            hash,
        )?,
        _ => bail!("unsupported compilation mode"),
    };
    let mut builder = WasiCtxBuilder::new();
    builder
        .allow_tcp(false)
        .allow_udp(false)
        .allow_ip_name_lookup(false);
    // No inherited environment, arguments, stdio, filesystem or sockets.
    let mut table = ResourceTable::new();
    table.set_max_capacity(1024);
    let state = State {
        wasi: builder.build(),
        table,
        limits: Limits {
            memory,
            used: 0,
            exhausted: false,
        },
        grants,
        directories,
        input,
        output: tokio::io::stdout(),
        remaining: requests,
        bytes,
    };
    let mut store = Store::new(&engine, state);
    store.limiter(|state| &mut state.limits);
    store.set_fuel(fuel)?;
    store.fuel_async_yield_interval(Some(100000))?;
    let mut linker = Linker::new(&engine);
    wasmtime_wasi::p2::add_to_linker_async(&mut linker)?;
    host::sdk::host::add_to_linker::<_, wasmtime::component::HasSelf<State>>(
        &mut linker,
        |state: &mut State| state,
    )?;
    let instance = linker.instantiate_async(&mut store, &component).await?;
    send(
        &mut store.data_mut().output,
        json!({"ready":true,"runtime":"wasmtime-50.0.1","artifact":hash,"compilation":mode,"configuration":artifact::CONFIGURATION,"target":artifact::TARGET,"nativeArtifact":init["nativeRegistration"]["nativeSha256"]}),
    )
    .await?;
    let mut resources = GuestResources::default();
    loop
    {
        let message = read_message(&mut store.data_mut().input, bytes * 6 + 4096).await?;
        if message["close"] == true
        {
            break;
        }
        let outcome: Result<Value> = async {
            store.set_fuel(fuel)?;
            let interface = message["interface"]
                .as_str()
                .context("interface required")?;
            let name = message["method"].as_str().context("method required")?;
            if name == "[resource-drop]"
            {
                let key = GuestResources::key(&message["args"][0])?;
                let resource = resources
                    .live
                    .remove(key)
                    .context("invalid or released resource")?;
                resource.resource_drop_async(&mut store).await?;
                return Ok(json!({"value": []}));
            }
            let iface = instance
                .get_export_index(&mut store, None, interface)
                .context("unknown interface")?;
            let index = instance
                .get_export_index(&mut store, Some(&iface), name)
                .context("unknown method")?;
            let function = instance
                .get_func(&mut store, index)
                .context("not a function")?;
            let ty = function.ty(&store);
            let args = message["args"].as_array().context("arguments required")?;
            ensure!(args.len() == ty.params().len(), "argument count mismatch");
            let params = ty
                .params()
                .zip(args)
                .map(|((_, ty), value)| from_json(ty, value, &mut resources))
                .collect::<Result<Vec<_>>>()?;
            let mut results = vec![Val::Bool(false); ty.results().len()];
            function
                .call_async(&mut store, &params, &mut results)
                .await?;
            let values = results
                .iter()
                .map(|v| to_json(v, &mut resources))
                .collect::<Result<Vec<_>>>()?;
            let response = json!({"value":values});
            ensure!(
                serde_json::to_vec(&response)?.len() <= bytes,
                "output exhausted"
            );
            Ok(response)
        }
        .await;
        match outcome
        {
            Ok(value) => send(&mut store.data_mut().output, value).await?,
            Err(error) =>
            {
                let code = if store.data().limits.exhausted
                    || matches!(error.downcast_ref::<Trap>(), Some(Trap::OutOfFuel))
                    || matches!(
                        error.downcast_ref::<ResourceTableError>(),
                        Some(ResourceTableError::Full)
                    )
                    || error.to_string().contains("exhausted")
                {
                    "exhausted"
                }
                else
                {
                    "failed"
                };
                send(
                    &mut store.data_mut().output,
                    json!({"error":{"code":code,"message":format!("{error:#}")}}),
                )
                .await?;
                // Traps poison an instance; termination also releases every resource.
                break;
            }
        }
    }
    Ok(())
}
