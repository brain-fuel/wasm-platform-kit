// Installation receipts are trusted package-local state, never guest authority.
// ref:DEC-wpk-installation-preparation
import {readFileSync} from 'node:fs';

export const nativeConfiguration = 'host-sdk-0.2.0/wasmtime-50.0.1/fuel-v1';
export const nativeTargets = Object.freeze({
  'darwin-arm64': 'aarch64-apple-darwin',
  'darwin-x64': 'x86_64-apple-darwin',
  'linux-arm64': 'aarch64-unknown-linux-gnu',
  'linux-x64': 'x86_64-unknown-linux-gnu',
});

/** Reads only receipts approved by the embedding package's generated registration. ref:DEC-wpk-installation-preparation */
export function installedNativeArtifacts({
  directory,
  componentSha256,
  prebuiltArtifacts = {},
})
{
  return Object.freeze(
    Object.defineProperties(
      {},
      Object.fromEntries(
        Object.entries(nativeTargets).map(([platform, target]) => [
          platform,
          {
            enumerable: true,
            get()
            {
              let receipt;
              try
              {
                receipt = JSON.parse(
                  readFileSync(
                    new URL(`.native/${platform}/registration.json`, directory),
                    'utf8',
                  ),
                );
              }
              catch (error)
              {
                if (error.code === 'ENOENT') return prebuiltArtifacts[platform];
                throw error;
              }
              if (
                receipt.componentSha256 !== componentSha256 ||
                receipt.configuration !== nativeConfiguration ||
                receipt.target !== target ||
                !/^[a-f0-9]{64}$/.test(receipt.nativeSha256)
              )
                throw new Error(
                  'Installed native registration mismatch; reinstall the application',
                );
              return Object.freeze({
                componentSha256,
                configuration: nativeConfiguration,
                target,
                nativeSha256: receipt.nativeSha256,
                artifact: new URL(
                  `.native/${platform}/${receipt.nativeSha256}.cwasm`,
                  directory,
                ),
              });
            },
          },
        ]),
      ),
    ),
  );
}
