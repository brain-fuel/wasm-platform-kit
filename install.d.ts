import type {HostOptions} from './index.js';

/** Trusted embedding package installation settings; guest manifests grant no authority. */
export interface InstallationOptions
{
  directory: URL;
  component: URL;
  componentSha256: string;
  prebuiltArtifacts?: HostOptions['nativeArtifacts'];
  /** Defaults to WASM_PLATFORM_KIT_BUILD_FROM_SOURCE=1. */
  fromSource?: boolean;
  signal?: AbortSignal;
  /** Installation-only deadline, at most 900000ms; guest execution limits are independent. */
  timeout?: number;
}
export function prepareNative(options: InstallationOptions): Promise<{
  preparation: 'prebuilt' | 'source';
  componentSha256: string;
  nativeSha256: string;
  configuration: string;
  target: string;
}>;
