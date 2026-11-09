// Build-time tool resolution; no dependency on any consuming application's checkout.
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {existsSync} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const toolchainRoot =
  process.env.HOST_SDK_TOOLCHAIN ?? path.join(os.homedir(), '.ghc-wasm');
export function generatorPath()
{
  if (process.env.HOST_SDK_GENERATOR) return process.env.HOST_SDK_GENERATOR;
  const local = path.join(root, 'target/debug/wit-haskell');
  return existsSync(local)
    ? local
    : require.resolve(
        `wasm-platform-kit-${process.platform}-${process.arch}/bin/wit-haskell`,
      );
}
export const runtimeRoot = () =>
  path.dirname(require.resolve('wasm-platform-kit/package.json'));
export const jcoRoot = () =>
  path.resolve(path.dirname(require.resolve('@bytecodealliance/jco')), '..');
export const supportDirectory = () => path.join(root, 'haskell');
export const witDirectory = () => path.join(root, 'wit');
export function runHaskell(command, args, options = {})
{
  const env = process.env.HOST_SDK_GHC_ENV ?? path.join(toolchainRoot, 'env');
  if (!existsSync(env)) return execFileSync(command, args, options);
  return execFileSync(
    'bash',
    ['-c', 'source "$1"; shift; exec "$@"', 'host-sdk', env, command, ...args],
    options,
  );
}

/** Resolves the separately selected compiler-enabled build helper. ref:DEC-host-sdk-precompiled-node */
export const compilerPath = () =>
  require.resolve(
    `wasm-platform-kit-${process.platform}-${process.arch}/bin/host-sdk-source-runtime`,
  );
