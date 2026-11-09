// Owner Allman preference using the pinned upstream formatter.
import {format} from 'prettier';
import braceStyle from 'prettier-plugin-brace-style';
import {readFile, writeFile} from 'node:fs/promises';
for (const file of process.argv.slice(2))
{
  const result = await format(await readFile(file, 'utf8'), {
    filepath: file,
    printWidth: 80,
    tabWidth: 2,
    singleQuote: true,
    bracketSpacing: false,
    trailingComma: 'all',
    arrowParens: 'avoid',
    plugins: [braceStyle],
    braceStyle: 'allman',
  });
  await writeFile(file, result);
}
