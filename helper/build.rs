// ref:DEC-host-sdk-precompiled-node
fn main()
{
    println!(
        "cargo:rustc-env=HOST_SDK_TARGET={}",
        std::env::var("TARGET").unwrap()
    );
}
