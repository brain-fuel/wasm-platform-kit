// Cross-language ABI tests include values that JSON Numbers cannot represent.
// ref:DEC-host-sdk-typed-application-boundary
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHost} from '../node.mjs';
import {nativeArtifacts as rustNative} from '../assets/contract/node-registration.mjs';
import {nativeArtifacts as haskellNative} from '../assets/haskell-contract/node-registration.mjs';

for (const guest of ['contract', 'haskell-contract'])
{
  test(`${guest}: integer widths, variants, bulk bytes and scalar/void exports`, async t =>
  {
    const host = await createHost({
      manifest: new URL(`../assets/${guest}/manifest.json`, import.meta.url),
      nativeArtifacts: guest === 'contract' ? rustNative : haskellNative,
    });
    t.after(() => host.close());
    const payload = {
      integers: {
        a: 255,
        b: -128,
        c: 65535,
        d: -32768,
        e: 4294967295,
        f: -2147483648,
        g: 18446744073709551615n,
        h: -9223372036854775808n,
      },
      numbers: [
        {tag: 'small', val: 4294967295},
        {tag: 'large', val: 9007199254740993n},
        {tag: 'negative', val: -9223372036854775808n},
      ],
      bytes: Array.from({length: 65536}, (_, i) => i % 256),
      optional: -9007199254740993n,
    };
    assert.deepEqual(await host.invoke('scalars', [payload]), payload);
    const large = {
      first: payload,
      second: {...payload, optional: null},
      note: 'indirect 😀',
    };
    assert.deepEqual(await host.invoke('large', [large]), large);
    assert.deepEqual(
      await host.invoke('scalars', [
        {...payload, bytes: new Uint8Array([0, 128, 255]), optional: null},
      ]),
      {...payload, bytes: [0, 128, 255], optional: null},
    );
    for (const value of [0n, 9007199254740993n, 18446744073709551615n])
      assert.equal(await host.invoke('scalar', [value]), value);
    assert.equal(await host.invoke('nothing'), undefined);
    assert.equal(
      await host.invoke('echo', ['18446744073709551615']),
      '18446744073709551615',
    );
  });
  for (const value of [
    9007199254740992,
    '18446744073709551615',
    -1n,
    18446744073709551616n,
  ])
    test(`${guest}: rejects invalid u64 ${typeof value} ${value}`, async t =>
    {
      const host = await createHost({
        manifest: new URL(`../assets/${guest}/manifest.json`, import.meta.url),
        nativeArtifacts: guest === 'contract' ? rustNative : haskellNative,
      });
      t.after(() => host.close());
      await assert.rejects(
        host.invoke('scalar', [value]),
        error => error.code === 'failed',
      );
    });
}
