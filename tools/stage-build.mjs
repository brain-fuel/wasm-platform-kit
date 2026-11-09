import {mkdir, copyFile, cp, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** Stages portable authoring tools independently of native fixture builds. ref:DEC-wpk-installation-preparation */
export async function stageBuildPackage()
{
  const version = JSON.parse(
    await readFile(path.join(root, 'package.json'), 'utf8'),
  ).version;
  // The authoring package carries portable JS tooling, WIT and Cabal support sources.
  const build = path.join(root, 'packages/build');
  await mkdir(path.join(build, 'tools'), {recursive: true});
  for (const file of [
    'index.mjs',
    'generate.mjs',
    'component.mjs',
    'native.mjs',
    'facade.mjs',
    'paths.mjs',
  ])
    await copyFile(
      path.join(root, 'tools', file),
      path.join(build, 'tools', file),
    );
  await cp(path.join(root, 'haskell'), path.join(build, 'haskell'), {
    recursive: true,
  });
  await cp(path.join(root, 'wit'), path.join(build, 'wit'), {recursive: true});
  await copyFile(path.join(root, 'LICENSE'), path.join(build, 'LICENSE'));
  await writeFile(
    path.join(build, 'README.md'),
    '# Wasm Platform Kit build tools\nDirect WIT-to-Haskell generation and application-owned component packaging. See the SDK repository documentation.\n',
  );
  await writeFile(
    path.join(build, 'package.json'),
    JSON.stringify(
      {
        name: 'wasm-platform-kit-build',
        version,
        type: 'module',
        license: 'MIT',
        exports: {'.': './tools/index.mjs', './package.json': './package.json'},
        files: ['tools', 'haskell', 'wit', 'LICENSE', 'README.md'],
        dependencies: {
          'wasm-platform-kit': version,
          '@bytecodealliance/jco': '1.41.0',
          prettier: '3.9.10',
          'prettier-plugin-brace-style': '0.10.4',
        },
        optionalDependencies: Object.fromEntries(
          ['darwin-arm64', 'darwin-x64', 'linux-arm64', 'linux-x64'].map(
            target => [`wasm-platform-kit-${target}`, version],
          ),
        ),
      },
      null,
      2,
    ),
  );
}
if (
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url
)
  await stageBuildPackage();
