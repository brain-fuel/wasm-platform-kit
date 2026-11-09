import {
  createApplication,
  type Snapshot,
} from '../../assets/haskell-contract/node.mjs';
async function typedBoundary()
{
  const client = await createApplication();
  const scalar: Promise<bigint> = client.scalar(9007199254740993n);
  const snapshot: Snapshot = await client.newSnapshot(['one']);
  const rows: Promise<string[]> = snapshot.read(0, 1);
  const size: Promise<number> = snapshot.size();
  await client.consume(snapshot);
  // @ts-expect-error u64 accepts bigint, never a rounded Number
  client.scalar(9007199254740992);
  // @ts-expect-error exported resources are nominal and cannot be forged
  client.consume({});
  // @ts-expect-error every generated operation is asynchronous
  const sync: string = client.echo('text');
  client.close();
  return {scalar, rows, size, sync};
}
void typedBoundary;
