//! Tag failed memory.grow operations without guessing from trap messages.
//! This is host-owned instrumentation; original modules cannot reference the
//! newly appended global. Upstream parsers/encoders validate both binaries.
//! ref:DEC-host-sdk-direct-haskell
use anyhow::{Result, ensure};
use wasm_encoder::reencode::{Error, Reencode};
use wasm_encoder::{
    CodeSection, ConstExpr, ExportKind, ExportSection, Function, GlobalSection, GlobalType,
    Instruction, Module, SectionId, ValType,
};
use wasmparser::{Parser, Payload, TypeRef};

const FLAG: &str = "host-sdk:memory-exhausted";
struct Instrument
{
    parameter_counts: Vec<u32>,
    function_types: Vec<u32>,
    body: usize,
    globals: u32,
    has_globals: bool,
    has_exports: bool,
    inserted_globals: bool,
    inserted_exports: bool,
}
impl Instrument
{
    fn global(&self, section: &mut GlobalSection)
    {
        section.global(
            GlobalType {
                val_type: ValType::I32,
                mutable: true,
                shared: false,
            },
            &ConstExpr::i32_const(0),
        );
    }
    fn export(&self, section: &mut ExportSection)
    {
        section.export(FLAG, ExportKind::Global, self.globals);
    }
}
impl Reencode for Instrument
{
    type Error = anyhow::Error;
    fn parse_global_section(
        &mut self,
        section: &mut GlobalSection,
        reader: wasmparser::GlobalSectionReader<'_>,
    ) -> Result<(), Error<Self::Error>>
    {
        wasm_encoder::reencode::utils::parse_global_section(self, section, reader)?;
        self.global(section);
        Ok(())
    }
    fn parse_export_section(
        &mut self,
        section: &mut ExportSection,
        reader: wasmparser::ExportSectionReader<'_>,
    ) -> Result<(), Error<Self::Error>>
    {
        wasm_encoder::reencode::utils::parse_export_section(self, section, reader)?;
        self.export(section);
        Ok(())
    }
    fn intersperse_section_hook(
        &mut self,
        module: &mut Module,
        _after: Option<SectionId>,
        before: Option<SectionId>,
    ) -> Result<(), Error<Self::Error>>
    {
        if matches!(before, Some(SectionId::Custom | SectionId::Tag))
        {
            return Ok(());
        }
        let before = before.map_or(u8::MAX, |id| id as u8);
        if !self.has_globals && !self.inserted_globals && before > SectionId::Global as u8
        {
            let mut section = GlobalSection::new();
            self.global(&mut section);
            module.section(&section);
            self.inserted_globals = true;
        }
        if !self.has_exports && !self.inserted_exports && before > SectionId::Export as u8
        {
            let mut section = ExportSection::new();
            self.export(&mut section);
            module.section(&section);
            self.inserted_exports = true;
        }
        Ok(())
    }
    fn parse_function_body(
        &mut self,
        code: &mut CodeSection,
        body: wasmparser::FunctionBody<'_>,
    ) -> Result<(), Error<Self::Error>>
    {
        let mut locals = Vec::new();
        let mut scratch = self.parameter_counts[self.function_types[self.body] as usize];
        self.body += 1;
        for local in body.get_locals_reader()?
        {
            let (count, ty) = local?;
            scratch += count;
            locals.push((count, self.val_type(ty)?));
        }
        locals.push((1, ValType::I32));
        let mut function = Function::new(locals);
        let mut reader = body.get_operators_reader()?;
        while !reader.eof()
        {
            let op = reader.read()?;
            let growth = matches!(op, wasmparser::Operator::MemoryGrow { .. });
            function.instruction(&self.instruction(op)?);
            if growth
            {
                function.instruction(&Instruction::LocalTee(scratch));
                function.instruction(&Instruction::I32Const(-1));
                function.instruction(&Instruction::I32Eq);
                function.instruction(&Instruction::If(wasm_encoder::BlockType::Empty));
                function.instruction(&Instruction::I32Const(1));
                function.instruction(&Instruction::GlobalSet(self.globals));
                function.instruction(&Instruction::End);
                function.instruction(&Instruction::LocalGet(scratch));
            }
        }
        code.function(&function);
        Ok(())
    }
}
/// Preserves memory.grow results while making allocation failure observable to the worker.
pub fn instrument(bytes: &[u8]) -> Result<(Vec<u8>, u64)>
{
    wasmparser::Validator::new().validate_all(bytes)?;
    let mut encoder = Instrument {
        parameter_counts: Vec::new(),
        function_types: Vec::new(),
        body: 0,
        globals: 0,
        has_globals: false,
        has_exports: false,
        inserted_globals: false,
        inserted_exports: false,
    };
    let mut memory = 0;
    for payload in Parser::new(0).parse_all(bytes)
    {
        match payload?
        {
            Payload::TypeSection(reader) =>
            {
                for ty in reader.into_iter_err_on_gc_types()
                {
                    encoder.parameter_counts.push(ty?.params().len() as u32);
                }
            }
            Payload::ImportSection(reader) =>
            {
                for import in reader.into_imports()
                {
                    if matches!(import?.ty, TypeRef::Global(_))
                    {
                        encoder.globals += 1;
                    }
                }
            }
            Payload::FunctionSection(reader) =>
            {
                for ty in reader
                {
                    encoder.function_types.push(ty?);
                }
            }
            Payload::GlobalSection(reader) =>
            {
                encoder.has_globals = true;
                encoder.globals += reader.count();
            }
            Payload::ExportSection(reader) =>
            {
                encoder.has_exports = true;
                for export in reader
                {
                    ensure!(export?.name != FLAG, "reserved budget export");
                }
            }
            Payload::MemorySection(reader) =>
            {
                for ty in reader
                {
                    let ty = ty?;
                    ensure!(!ty.memory64 && !ty.shared, "unsupported browser memory");
                    memory += ty
                        .maximum
                        .ok_or_else(|| anyhow::anyhow!("unbounded browser memory"))?
                        * 65536;
                }
            }
            _ =>
            {}
        }
    }
    let mut output = Module::new();
    encoder
        .parse_core_module(&mut output, Parser::new(0), bytes)
        .map_err(|e| anyhow::anyhow!("budget instrumentation: {e:?}"))?;
    let bytes = output.finish();
    wasmparser::Validator::new().validate_all(&bytes)?;
    Ok((bytes, memory))
}
