// Local fixture measurements are execution observations, not application acceptance.
// ref:DEC-host-sdk-typed-application-boundary
import {createHost} from '../node.mjs';
import {readFile, readdir, stat} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';
import {gzipSync} from 'node:zlib';
const rows = [];
const percentile = (values, probability) =>
  [...values].sort((a, b) => a - b)[Math.ceil(values.length * probability) - 1];
for (const fixture of ['haskell-contract', 'contract'])
{
  const directory = new URL(`../assets/${fixture}/`, import.meta.url);
  const manifest = new URL('manifest.json', directory);
  const startup = [],
    calls = [];
  let identity, helperRssKiB;
  for (let i = 0; i < 5; i++)
  {
    const start = performance.now();
    const host = await createHost({manifest});
    startup.push(performance.now() - start);
    try
    {
      for (let j = 0; j < 20; j++)
      {
        const before = performance.now();
        await host.invoke('echo', ['interactive 😀']);
        calls.push(performance.now() - before);
      }
      const processes = execFileSync('ps', ['-axo', 'ppid,pid,rss,comm'], {
        encoding: 'utf8',
      }).split('\n');
      const helper = processes
        .map(line => line.trim().split(/\s+/))
        .find(
          fields =>
            Number(fields[0]) === process.pid &&
            fields.slice(3).join(' ').includes('host-sdk-runtime'),
        );
      helperRssKiB = helper ? Number(helper[2]) : null;
      identity = {...host.identity};
      delete identity.instance;
    }
    finally
    {
      host.close();
    }
  }
  let browserBytes = 0,
    gzipBytes = 0;
  async function sizes(url)
  {
    for (const entry of await readdir(url, {withFileTypes: true}))
    {
      const file = new URL(entry.name + (entry.isDirectory() ? '/' : ''), url);
      if (entry.isDirectory()) await sizes(file);
      else if (
        /\.(js|mjs|wasm)$/.test(entry.name) &&
        entry.name !== 'component.wasm' &&
        entry.name !== 'node.mjs'
      )
      {
        const bytes = await readFile(file);
        browserBytes += bytes.length;
        gzipBytes += gzipSync(bytes).length;
      }
    }
  }
  await sizes(directory);
  rows.push({
    fixture,
    identity,
    startupMs: {samples: startup, median: percentile(startup, 0.5)},
    interactiveMs: {
      samples: calls.length,
      median: percentile(calls, 0.5),
      p95: percentile(calls, 0.95),
    },
    helperRssKiB,
    componentBytes: (await stat(new URL('component.wasm', directory))).size,
    browserRawBytes: browserBytes,
    browserGzipBytes: gzipBytes,
  });
}
console.log(
  JSON.stringify(
    {
      recordedAt: new Date().toISOString(),
      platform: process.platform,
      arch: process.arch,
      node: process.version,
      scope:
        'generic contract fixtures, not full LawSpec performance acceptance',
      rows,
    },
    null,
    2,
  ),
);
