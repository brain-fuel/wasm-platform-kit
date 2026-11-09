// Native distribution inspection uses upstream LLVM/binutils, not a private ELF parser.
// ref:DEC-host-sdk-linux-abi-baseline
import {execFileSync} from 'node:child_process';

/** Compares numeric ABI versions without lexical ordering mistakes. ref:DEC-host-sdk-linux-abi-baseline */
function compareVersions(left, right)
{
  /** Numeric left-hand ABI components. ref:DEC-host-sdk-linux-abi-baseline */
  const a = left.split('.').map(Number);
  /** Numeric right-hand ABI components. ref:DEC-host-sdk-linux-abi-baseline */
  const b = right.split('.').map(Number);
  /** Compares every version component, including patch levels. ref:DEC-host-sdk-linux-abi-baseline */
  for (let i = 0; i < Math.max(a.length, b.length); i++)
  {
    /** Missing trailing components are zero. ref:DEC-host-sdk-linux-abi-baseline */
    const difference = (a[i] ?? 0) - (b[i] ?? 0);
    if (difference) return difference;
  }
  return 0;
}

/** Rejects binaries that exceed Node's Linux ABI baseline before distribution. ref:DEC-host-sdk-linux-abi-baseline */
export function inspectLinuxAbi(file)
{
  /** Allows an explicit upstream inspector executable. ref:DEC-host-sdk-linux-abi-baseline */
  const override = process.env.HOST_SDK_READOBJ;
  /** Uses LLVM or GNU binutils without a private ELF parser. ref:DEC-host-sdk-linux-abi-baseline */
  const candidates = override ? [override] : ['llvm-readobj', 'readelf'];
  /** Holds only a successfully inspected version table. ref:DEC-host-sdk-linux-abi-baseline */
  let output;
  /** Falls back only when the inspector executable is absent. ref:DEC-host-sdk-linux-abi-baseline */
  for (const command of candidates)
  {
    try
    {
      output = execFileSync(command, ['--version-info', file], {
        encoding: 'utf8',
        maxBuffer: 8 * 1024 * 1024,
        env: {...process.env, LC_ALL: 'C'},
      });
      break;
    }
    catch (error)
    {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  if (output === undefined)
    throw new Error(
      'Native ABI inspection needs llvm-readobj or readelf; HOST_SDK_READOBJ can select an executable',
    );
  /** Collects requirements from the upstream version table. ref:DEC-host-sdk-linux-abi-baseline */
  const versions = [...output.matchAll(/\bName:\s+(GLIBC_[^\s]+)/g)].map(
    match => match[1],
  );
  if (
    !versions.length ||
    versions.some(version => !/^GLIBC_\d+\.\d+(?:\.\d+)?$/.test(version))
  )
    throw new Error(`unsupported glibc ABI metadata: ${file}`);
  /** The newest required symbol version sets the minimum runtime. ref:DEC-host-sdk-linux-abi-baseline */
  const minimumGlibc = versions
    .map(version => version.slice(6))
    .sort(compareVersions)
    .at(-1);
  if (compareVersions(minimumGlibc, '2.28') > 0)
    throw new Error(
      `native ABI exceeds glibc 2.28 baseline: ${file} requires ${minimumGlibc}`,
    );
  return minimumGlibc;
}
