// Generated façades and declarations must agree on async methods and ownership.
// ref:DEC-host-sdk-typed-application-boundary
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
for (const fixture of ['contract', 'haskell-contract'])
{
  test(`${fixture}: generated Promise API and typed resource methods`, async t =>
  {
    const {createApplication} = await import(`../assets/${fixture}/node.mjs`);
    const app = await createApplication();
    const other = await createApplication();
    t.after(() =>
    {
      app.close();
      other.close();
    });
    const echoed = app.echo('generated 😀');
    assert.equal(typeof echoed.then, 'function');
    assert.equal(await echoed, 'generated 😀');
    assert.equal(
      await app.scalar(18446744073709551615n),
      18446744073709551615n,
    );
    assert.equal(await app.answer(9007199254740993n), 9007199254740993n);
    assert.deepEqual(
      await app.replyValue({tag: 'err', val: 'ordinary variant'}),
      {tag: 'err', val: 'ordinary variant'},
    );
    await assert.rejects(
      app.reject('ordinary rejection'),
      error =>
        error.code === 'failed' && error.payload === 'ordinary rejection',
    );
    const staticResource = await app.snapshotFromOne('static');
    assert.deepEqual(await staticResource.read(0, 1), ['static']);
    await staticResource.dispose();
    const resource = await app.newSnapshot(['zero', 'one', 'two']);
    assert.equal(await resource.size(), 3);
    assert.deepEqual(await resource.read(1, 2), ['one', 'two']);
    await assert.rejects(other.consume(resource), {code: 'denied'});
    await resource.dispose();
    assert.equal(await app.destroyed(), 2);
    const transferred = await app.newSnapshot(['owned']);
    assert.equal(await app.consume(transferred), 1);
    assert.equal(await app.destroyed(), 3);
    const abort = new AbortController();
    abort.abort();
    await assert.rejects(app.echo('cancelled', {signal: abort.signal}), {
      code: 'cancelled',
    });
    assert.equal(await other.echo('independent'), 'independent');
  });
}
test('generated TypeScript requires Promise results, bigint scalars and typed resources', () =>
{
  execFileSync(
    process.execPath,
    [
      'node_modules/typescript/bin/tsc',
      '--noEmit',
      '--strict',
      '--module',
      'nodenext',
      '--moduleResolution',
      'nodenext',
      '--target',
      'es2022',
      'test/fixtures/facade.ts',
    ],
    {stdio: 'pipe'},
  );
});
