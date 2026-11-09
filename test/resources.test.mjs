// Resource tables stay in the guest; public handles carry instance identity only.
// ref:DEC-host-sdk-typed-application-boundary
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHost} from '../node.mjs';
import {nativeArtifacts as rustNative} from '../assets/contract/node-registration.mjs';
import {nativeArtifacts as haskellNative} from '../assets/haskell-contract/node-registration.mjs';
for (const guest of ['contract', 'haskell-contract'])
{
  const create = () =>
    createHost({
      manifest: new URL(`../assets/${guest}/manifest.json`, import.meta.url),
      nativeArtifacts: guest === 'contract' ? rustNative : haskellNative,
    });
  test(`${guest}: snapshot bulk readers, ownership transfer and destructors`, async t =>
  {
    const host = await create();
    t.after(() => host.close());
    const values = [
      'zero',
      '一',
      '😀',
      ...Array.from({length: 2000}, (_, i) => String(i)),
    ];
    const resource = await host.invoke('[constructor]snapshot', [values]);
    assert.equal(
      await host.invoke('[method]snapshot.size', [resource]),
      values.length,
    );
    assert.deepEqual(
      await host.invoke('[method]snapshot.read', [resource, 1, 3]),
      values.slice(1, 4),
    );
    assert.deepEqual(
      await host.invoke('[method]snapshot.read', [resource, 3000, 10]),
      [],
    );
    assert.equal(await host.invoke('destroyed'), 0);
    await host.drop(resource);
    assert.equal(await host.invoke('destroyed'), 1);
    for (let i = 0; i < 20; i++)
    {
      const next = await host.invoke('[constructor]snapshot', [['retained']]);
      assert.equal(await host.invoke('consume', [next]), 1);
    }
    assert.equal(await host.invoke('destroyed'), 21);
  });
  test(`${guest}: rejects forged and cross-instance resources before dispatch`, async t =>
  {
    const host = await create();
    const other = await create();
    t.after(() =>
    {
      host.close();
      other.close();
    });
    const resource = await host.invoke('[constructor]snapshot', [['private']]);
    await assert.rejects(other.invoke('[method]snapshot.size', [resource]), {
      code: 'denied',
    });
    await assert.rejects(
      host.invoke('[method]snapshot.size', [{'$host-sdk-resource': '1'}]),
      {code: 'denied'},
    );
    assert.equal(await host.invoke('[method]snapshot.size', [resource]), 1);
    await host.drop(resource);
    await assert.rejects(host.invoke('[method]snapshot.size', [resource]), {
      code: 'failed',
    });
  });
}

test('Haskell: a retained borrow expires even while its owned resource remains live', async t =>
{
  const host = await createHost({
    nativeArtifacts: haskellNative,
    manifest: new URL(
      '../assets/haskell-contract/manifest.json',
      import.meta.url,
    ),
  });
  t.after(() => host.close());
  const resource = await host.invoke('[constructor]snapshot', [['private']]);
  await host.invoke('remember', [resource]);
  assert.equal(await host.invoke('[method]snapshot.size', [resource]), 1);
  await assert.rejects(host.invoke('remembered-size'), {code: 'failed'});
});
