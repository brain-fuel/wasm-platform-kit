//! Upstream WIT resolution and canonical layout for the Haskell emitter.
//! ref:DEC-host-sdk-direct-haskell
mod budget;
use anyhow::{Result, bail, ensure};
use serde_json::{Value, json};
use std::{env, fs};
use wasm_encoder::reencode::{Error, Reencode};
use wit_parser::abi::{AbiVariant, FlatTypes, WasmType};
use wit_parser::{FunctionKind, Int, Resolve, SizeAlign, Type, TypeDefKind, WorldItem};

fn flat(resolve: &Resolve, ty: &Type) -> Result<Vec<WasmType>>
{
    let mut storage = [WasmType::I32; 256];
    let mut types = FlatTypes::new(&mut storage);
    ensure!(
        resolve.push_flat(ty, &mut types),
        "unsupported: more than 256 flat fields"
    );
    let result = types.to_vec();
    ensure!(
        result.iter().all(|t| matches!(
            t,
            WasmType::I32
                | WasmType::I64
                | WasmType::PointerOrI64
                | WasmType::Pointer
                | WasmType::Length
        )),
        "unsupported: Haskell backend currently accepts integer lanes only"
    );
    Ok(result)
}

fn describe(path: &str, world: &str) -> Result<Value>
{
    let mut resolve = Resolve::default();
    let (package, _) = resolve.push_path(path)?;
    let world = resolve.select_world(&[package], Some(world))?;
    let mut sizes = SizeAlign::default();
    sizes.fill(&resolve)?;
    let mut layouts = Vec::new();
    for (id, def) in resolve.types.iter()
    {
        let ty = Type::Id(id);
        let mut layout = json!({"size": sizes.size(&ty).size_wasm32(), "align": sizes.align(&ty).align_wasm32()});
        match &def.kind
        {
            TypeDefKind::Resource =>
            {
                layout = json!({"size": sizes.size(&Type::U32).size_wasm32(), "align": sizes.align(&Type::U32).align_wasm32(), "flat": 1});
            }
            TypeDefKind::Record(record) =>
            {
                layout["offsets"] = json!(
                    sizes
                        .field_offsets(record.fields.iter().map(|f| &f.ty))
                        .iter()
                        .map(|(off, _)| off.size_wasm32())
                        .collect::<Vec<_>>()
                );
                layout["flat"] = json!(flat(&resolve, &ty)?.len());
            }
            TypeDefKind::Variant(variant) =>
            {
                ensure!(
                    variant.cases.len() <= 256,
                    "unsupported: variant with more than 256 cases"
                );
                layout["payload"] = json!(
                    sizes
                        .payload_offset(variant.tag(), variant.cases.iter().map(|c| c.ty.as_ref()))
                        .size_wasm32()
                );
                layout["flat"] = json!(flat(&resolve, &ty)?.len());
            }
            TypeDefKind::Result(result) =>
            {
                layout["payload"] = json!(
                    sizes
                        .payload_offset(Int::U8, [result.ok.as_ref(), result.err.as_ref()])
                        .size_wasm32()
                );
                layout["flat"] = json!(flat(&resolve, &ty)?.len());
            }
            TypeDefKind::Option(value) =>
            {
                layout["payload"] =
                    json!(sizes.payload_offset(Int::U8, [Some(value)]).size_wasm32());
                layout["flat"] = json!(flat(&resolve, &ty)?.len());
            }
            TypeDefKind::Enum(value) =>
            {
                ensure!(
                    value.cases.len() <= 256,
                    "unsupported: enum with more than 256 cases"
                );
                layout["flat"] = json!(1);
            }
            TypeDefKind::List(_) | TypeDefKind::Type(_) | TypeDefKind::Handle(_) =>
            {
                layout["flat"] = json!(flat(&resolve, &ty)?.len());
            }
            _ => bail!("unsupported WIT type in Haskell backend: {:?}", def.kind),
        }
        layouts.push(layout);
    }
    let mut functions = Vec::new();
    let mut resources = Vec::new();
    for (export, items) in [
        (false, &resolve.worlds[world].imports),
        (true, &resolve.worlds[world].exports),
    ]
    {
        for (key, item) in items
        {
            let WorldItem::Interface { id, .. } = item
            else
            {
                bail!("unsupported: use interface imports and exports");
            };
            let module = resolve.name_world_key(key);
            let interface = &resolve.interfaces[*id];
            for (_, tid) in &interface.types
            {
                if matches!(resolve.types[*tid].kind, TypeDefKind::Resource)
                {
                    resources.push(json!({"id": tid.index(), "export": export, "module": module, "name": resolve.types[*tid].name}));
                }
            }
            for (_, function) in &interface.functions
            {
                ensure!(
                    matches!(
                        function.kind,
                        FunctionKind::Freestanding
                            | FunctionKind::Method(_)
                            | FunctionKind::Static(_)
                            | FunctionKind::Constructor(_)
                    ),
                    "unsupported: asynchronous WIT functions and property accessors"
                );
                for param in &function.params
                {
                    flat(&resolve, &param.ty)?;
                }
                if let Some(ty) = function.result
                {
                    flat(&resolve, &ty)?;
                }
                let sig = resolve.wasm_signature(
                    if export
                    {
                        AbiVariant::GuestExport
                    }
                    else
                    {
                        AbiVariant::GuestImport
                    },
                    function,
                );
                functions.push(json!({"interface": id.index(), "module": module, "export": export, "function": function, "params": sig.params.len(), "results": sig.results.len(), "paramLanes": sig.params.iter().map(|t| format!("{t:?}")).collect::<Vec<_>>(), "resultLanes": sig.results.iter().map(|t| format!("{t:?}")).collect::<Vec<_>>(), "retptr": sig.retptr, "indirectParams": sig.indirect_params, "paramSize": sizes.record(function.params.iter().map(|p| &p.ty)).size.size_wasm32(), "paramOffsets": sizes.field_offsets(function.params.iter().map(|p| &p.ty)).iter().map(|(offset,_)| offset.size_wasm32()).collect::<Vec<_>>()}));
            }
        }
    }
    Ok(
        json!({"resolve": resolve, "layouts": layouts, "functions": functions, "resources": resources}),
    )
}

// Schema metadata uses upstream resolution without imposing Haskell ABI restrictions
// on unrelated WASI imports. It is embedded in the trusted build manifest.
fn schema(path: &str, world: &str) -> Result<Value>
{
    let mut resolve = Resolve::default();
    let (package, _) = resolve.push_path(path)?;
    let world = resolve.select_world(&[package], Some(world))?;
    let mut interfaces = serde_json::Map::new();
    for (key, item) in &resolve.worlds[world].exports
    {
        let WorldItem::Interface { id, .. } = item
        else
        {
            bail!("unsupported: interface exports required")
        };
        interfaces.insert(
            resolve.name_world_key(key),
            serde_json::to_value(&resolve.interfaces[*id].functions)?,
        );
    }
    Ok(
        json!({"types": resolve.types.iter().map(|(_, ty)| ty).collect::<Vec<_>>(), "interfaces": interfaces}),
    )
}

struct Remap(Value);
impl Reencode for Remap
{
    type Error = anyhow::Error;
    fn memory_type(
        &mut self,
        value: wasmparser::MemoryType,
    ) -> Result<wasm_encoder::MemoryType, Error<Self::Error>>
    {
        let mut ty = wasm_encoder::reencode::utils::memory_type(self, value);
        if let Some(bytes) = self.0["memoryBytes"].as_u64()
        {
            let maximum = bytes / 65536;
            if ty.memory64 || ty.shared || ty.page_size_log2.is_some() || ty.minimum > maximum
            {
                return Err(Error::UserError(anyhow::anyhow!(
                    "unsupported browser memory"
                )));
            }
            ty.maximum = Some(ty.maximum.unwrap_or(maximum).min(maximum));
        }
        Ok(ty)
    }
    fn table_type(
        &mut self,
        value: wasmparser::TableType,
    ) -> Result<wasm_encoder::TableType, Error<Self::Error>>
    {
        let mut ty = wasm_encoder::reencode::utils::table_type(self, value)?;
        if self.0["memoryBytes"].is_u64()
        {
            if ty.minimum > 1000000
            {
                return Err(Error::UserError(anyhow::anyhow!(
                    "unsupported browser table"
                )));
            }
            ty.maximum = Some(ty.maximum.unwrap_or(1000000).min(1000000));
        }
        Ok(ty)
    }
    fn parse_import_section(
        &mut self,
        section: &mut wasm_encoder::ImportSection,
        reader: wasmparser::ImportSectionReader<'_>,
    ) -> Result<(), Error<Self::Error>>
    {
        for import in reader.into_imports()
        {
            let import = import?;
            let mapping = self.0["imports"][import.name].clone();
            let (module, name) = if import.module == "env" && mapping.is_array()
            {
                (
                    mapping[0].as_str().ok_or_else(|| {
                        Error::UserError(anyhow::anyhow!("invalid import module mapping"))
                    })?,
                    mapping[1].as_str().ok_or_else(|| {
                        Error::UserError(anyhow::anyhow!("invalid import name mapping"))
                    })?,
                )
            }
            else
            {
                (import.module, import.name)
            };
            section.import(module, name, self.entity_type(import.ty)?);
        }
        Ok(())
    }
    fn parse_export(
        &mut self,
        section: &mut wasm_encoder::ExportSection,
        export: wasmparser::Export<'_>,
    ) -> Result<(), Error<Self::Error>>
    {
        let name = self.0["exports"][export.name]
            .as_str()
            .unwrap_or(export.name)
            .to_owned();
        section.export(&name, self.export_kind(export.kind)?, export.index);
        Ok(())
    }
}

fn main() -> Result<()>
{
    let args: Vec<_> = env::args().collect();
    match args.get(1).map(String::as_str)
    {
        Some("describe") if args.len() == 4 => println!(
            "{}",
            serde_json::to_string_pretty(&describe(&args[2], &args[3])?)?
        ),
        Some("schema") if args.len() == 4 => println!("{}", schema(&args[2], &args[3])?),
        Some("remap") if args.len() == 5 =>
        {
            let bytes = fs::read(&args[2])?;
            let mut module = wasm_encoder::Module::new();
            let mut remap = Remap(serde_json::from_slice(&fs::read(&args[4])?)?);
            remap
                .parse_core_module(&mut module, wasmparser::Parser::new(0), &bytes)
                .map_err(|e| anyhow::anyhow!("remapping core symbols: {e:?}"))?;
            let bytes = module.finish();
            if remap.0["memoryBytes"].is_u64()
            {
                let (bytes, memory) = budget::instrument(&bytes)?;
                fs::write(&args[3], bytes)?;
                println!("{}", json!({"memory":memory}));
            }
            else
            {
                fs::write(&args[3], bytes)?;
            }
        }
        _ => bail!("usage: wit-haskell describe WIT WORLD | remap INPUT OUTPUT MAPPING"),
    }
    Ok(())
}
