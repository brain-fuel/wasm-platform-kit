//! Second-language contract guest and hostile negative controls.
//! No application compiler is part of this fixture. ref:DEC-host-sdk-direct-haskell
wit_bindgen::generate!({ path: "../test/wit", world: "contract", generate_all });
use exports::host::contract::application::{
    Guest, GuestSnapshot, LargeRequest, Payload, Reply, ScalarPayload, Snapshot, SnapshotBorrow,
};
use host::sdk::host::{Error, Provider, Request, acquire, perform};

struct ContractGuest;
struct SnapshotState(Vec<String>);
static DESTROYED: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
impl Drop for SnapshotState
{
    fn drop(&mut self)
    {
        DESTROYED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    }
}
impl GuestSnapshot for SnapshotState
{
    fn new(value: Vec<String>) -> Self
    {
        Self(value)
    }
    fn from_one(value: String) -> Snapshot
    {
        Snapshot::new(SnapshotState(vec![value]))
    }
    fn read(&self, start: u32, count: u32) -> Vec<String>
    {
        self.0
            .iter()
            .skip(start as usize)
            .take(count as usize)
            .cloned()
            .collect()
    }
    fn size(&self) -> u32
    {
        self.0.len() as u32
    }
}
impl Guest for ContractGuest
{
    type Snapshot = SnapshotState;
    // Safe Rust cannot retain the borrowed reference beyond this method.
    fn reject(message: String) -> Result<(), String>
    {
        Err(message)
    }
    fn remember(_value: SnapshotBorrow<'_>) {}
    fn remembered_size() -> u32
    {
        panic!("borrow cannot escape its call")
    }
    fn consume(value: Snapshot) -> u32
    {
        value.get::<SnapshotState>().0.len() as u32
    }
    fn destroyed() -> u32
    {
        DESTROYED.load(std::sync::atomic::Ordering::Relaxed)
    }
    fn reply_value(value: Reply) -> Reply
    {
        value
    }
    fn answer(value: u64) -> Result<u64, Error>
    {
        Ok(value)
    }
    fn large(value: LargeRequest) -> Result<LargeRequest, Error>
    {
        Ok(value)
    }
    fn scalars(value: ScalarPayload) -> Result<ScalarPayload, Error>
    {
        Ok(value)
    }
    fn scalar(value: u64) -> u64
    {
        value
    }
    fn nothing() {}
    fn round_trip(value: Payload) -> Result<Payload, Error>
    {
        Ok(value)
    }
    fn echo(value: String) -> Result<String, Error>
    {
        match value.as_str()
        {
            "__export-handle" => Ok(acquire("env")?.take_handle().to_string()),
            "__loop" => loop
            {
                std::hint::spin_loop();
            },
            "__allocate" =>
            {
                let mut allocations = Vec::new();
                loop
                {
                    allocations.push(vec![1u8; 1024 * 1024]);
                    std::hint::black_box(&allocations);
                }
            }
            "__panic" => panic!("deliberate guest exception"),
            "__wasi-file" =>
            {
                Ok(std::fs::read_to_string("/etc/passwd").unwrap_or_else(|_| "denied".into()))
            }
            "__wasi-env" =>
            {
                Ok(std::env::var("HOST_SDK_SECRET").unwrap_or_else(|_| "denied".into()))
            }
            _ => Ok(value),
        }
    }
    fn exercise(name: String, request: Request) -> Result<String, Error>
    {
        if let Some(raw) = name.strip_prefix("__import-handle:")
        {
            // A numeric handle copied from another instance conveys no authority.
            let handle = raw
                .parse::<u32>()
                .expect("fixture requires a numeric handle");
            let provider = unsafe { Provider::from_handle(handle) };
            return perform(&provider, &request);
        }
        if name == "__forge"
        {
            // Intentionally violate generated ownership rules. Wasmtime/jco must
            // reject this fabricated resource before any provider is entered.
            let provider = unsafe { Provider::from_handle(u32::MAX - 1) };
            return perform(&provider, &request);
        }
        let provider = acquire(&name)?;
        perform(&provider, &request)
    }
}
export!(ContractGuest);
