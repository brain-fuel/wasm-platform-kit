// Installation prepares executable artifacts. Runtime modules never import this module.
// ref:DEC-wpk-installation-preparation
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createReadStream} from 'node:fs';
import {
  copyFile,
  mkdir,
  mkdtemp,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {promisify} from 'node:util';
import {nativeConfiguration, nativeTargets} from './native-registration.mjs';

const require = createRequire(import.meta.url);
const execute = promisify(execFile);

/** Hashes streams with the same artifact bounds as the native helper. ref:DEC-wpk-installation-preparation */
async function digest(file, limit)
{
  const hash = createHash('sha256');
  let size = 0;
  for await (const chunk of createReadStream(file))
  {
    size += chunk.length;
    if (size > limit) throw new Error('Installation artifact size exhausted');
    hash.update(chunk);
  }
  return hash.digest('hex');
}

/** Verifies a prebuilt artifact or compiles a pinned portable component during installation. ref:DEC-wpk-installation-preparation */
export async function prepareNative({
  directory,
  component,
  componentSha256,
  prebuiltArtifacts = {},
  fromSource = process.env.WASM_PLATFORM_KIT_BUILD_FROM_SOURCE === '1',
  signal,
  timeout = 15 * 60 * 1000,
})
{
  const platform = `${process.platform}-${process.arch}`;
  const target = nativeTargets[platform];
  if (
    !target ||
    (process.platform === 'linux' &&
      !process.report.getReport().header.glibcVersionRuntime)
  )
    throw new Error(
      'Native installation supports macOS and glibc Linux on x64/ARM64; use WSL on Windows',
    );
  if (!/^[a-f0-9]{64}$/.test(componentSha256))
    throw new Error('Trusted component digest required');
  if (
    !Number.isSafeInteger(timeout) ||
    timeout <= 0 ||
    timeout > 15 * 60 * 1000
  )
    throw new Error(
      'Installation timeout must be between 1 and 900000 milliseconds',
    );
  signal?.throwIfAborted();
  require.resolve(`wasm-platform-kit-${platform}/bin/host-sdk-runtime`);
  if (!fromSource)
  {
    let prebuilt;
    try
    {
      const entry = prebuiltArtifacts[platform];
      if (entry) prebuilt = {...entry, artifact: entry.artifact};
    }
    catch (error)
    {
      if (
        !['MODULE_NOT_FOUND', 'ENOENT'].includes(error.code) &&
        !['MODULE_NOT_FOUND', 'ENOENT'].includes(error.cause?.code)
      )
        throw error;
    }
    if (prebuilt)
    {
      if (
        prebuilt.componentSha256 !== componentSha256 ||
        prebuilt.configuration !== nativeConfiguration ||
        prebuilt.target !== target ||
        (await digest(prebuilt.artifact, 512 * 1024 * 1024)) !==
          prebuilt.nativeSha256
      )
        throw new Error('Prebuilt native artifact integrity mismatch');
      // A rebuild without force-source returns the installation to its packaged artifact.
      await rm(new URL(`.native/${platform}/registration.json`, directory), {
        force: true,
      });
      return {preparation: 'prebuilt', ...prebuilt};
    }
  }
  const destination = fileURLToPath(new URL(`.native/${platform}/`, directory));
  await mkdir(destination, {recursive: true, mode: 0o700});
  await writeFile(new URL('.native/.npmignore', directory), '*\n');
  const staging = await mkdtemp(path.join(destination, '.prepare-'));
  try
  {
    const source = path.join(staging, 'component.wasm');
    const output = path.join(staging, 'component.cwasm');
    await copyFile(component, source);
    if ((await digest(source, 128 * 1024 * 1024)) !== componentSha256)
      throw new Error('Portable component integrity mismatch');
    signal?.throwIfAborted();
    const binary = require.resolve(
      `wasm-platform-kit-${platform}/bin/host-sdk-source-runtime`,
    );
    const {stdout} = await execute(
      binary,
      ['--precompile', source, output, target],
      {
        encoding: 'utf8',
        maxBuffer: 1024 * 1024,
        timeout,
        signal,
        killSignal: 'SIGKILL',
        env: {},
        cwd: staging,
      },
    );
    const receipt = JSON.parse(stdout);
    if (
      receipt.componentSha256 !== componentSha256 ||
      receipt.configuration !== nativeConfiguration ||
      receipt.target !== target ||
      (await digest(output, 512 * 1024 * 1024)) !== receipt.nativeSha256
    )
      throw new Error('Compiled native artifact registration mismatch');
    signal?.throwIfAborted();
    await rename(
      output,
      path.join(destination, `${receipt.nativeSha256}.cwasm`),
    );
    await writeFile(
      path.join(staging, 'registration.json'),
      JSON.stringify(receipt) + '\n',
      {mode: 0o600},
    );
    await rename(
      path.join(staging, 'registration.json'),
      path.join(destination, 'registration.json'),
    );
    return {preparation: 'source', ...receipt};
  }
  finally
  {
    await rm(staging, {recursive: true, force: true});
  }
}
