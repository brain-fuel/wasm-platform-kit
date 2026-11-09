/** Stable refusal and failure classifications shared with WIT. ref:DEC-host-sdk-direct-haskell */
export type Status =
  'denied' | 'unsupported' | 'cancelled' | 'exhausted' | 'failed';
/** Reports an operation outcome separately from an exception message. */
export class HostError extends Error
{
  /** Classifies the outcome for programmatic handling. */
  readonly code: Status;
  /** Original typed error value when a component returns result::err. */
  readonly payload?: unknown;
}
/** Immutable resource budgets for one runtime instance. */
export interface Limits
{
  /** Aggregate guest linear-memory budget in bytes; excludes trusted host heaps. */
  memory: number;
  /** Maximum request or response bytes, with bounded transport overhead. */
  bytes: number;
  /** Maximum imported capability calls during the instance lifetime. */
  requests: number;
  /** Wasmtime instruction fuel per invocation; browsers use the execution deadline. */
  fuel: number;
  /** Startup or invocation deadline in milliseconds; expiration terminates the instance. */
  timeout: number;
}
/** Lets trusted provider implementations cooperate with revocation. */
export interface ExecutionContext
{
  /** Aborts when the instance is revoked or an invocation is cancelled. */
  signal: AbortSignal;
}
/** Authority supplied by the embedding application, never by guest declarations. */
export type Grant =
  | {
      /** Selects the provider whose operations and scope are authorized. */
      kind: 'files';
      /** Node directory opened as a capability; never exposed as an ambient WASI preopen. */
      root?: string;
      /** Browser-owned directory handle; consent remains the embedding application responsibility. */
      handle?: FileSystemDirectoryHandle;
      /** Allows reads within this provider scope. */
      read?: boolean;
      /** Allows writes within this provider scope. */
      write?: boolean;
    }
  | {
      /** Selects the provider whose operations and scope are authorized. */
      kind: 'network';
      /** Explicitly permits HTTP in addition to the HTTPS default. */
      allowHttp?: boolean;
      /** Approved origin, path and operation combinations; redirects cannot widen them. */
      destinations: {
        /** Exact normalized URL origin, including an explicit non-default port. */
        origin: string;
        /** Exact URL pathname; defaults to the origin root. */
        path?: string;
        /** Also permits descendants under the path segment boundary. */
        subpaths?: boolean;
        /** Allowed HTTP methods for this destination. */
        methods: ('GET' | 'POST')[];
      }[];
      /** Explicit application-supplied headers, including any mediated credentials. */
      headers?: Record<string, string>;
    }
  | {
      /** Selects the provider whose operations and scope are authorized. */
      kind: 'storage';
      /** Application/plugin storage namespace; no ambient storage lookup. */
      namespace: string;
      /** Maximum UTF-8 bytes of keys and values in the namespace. */
      quota: number;
      /** Allows reads within this provider scope. */
      read?: boolean;
      /** Allows writes within this provider scope. */
      write?: boolean;
    }
  | {
      /** Selects the provider whose operations and scope are authorized. */
      kind: 'environment';
      /** Explicit environment values; process and page environment are never inherited. */
      values: Record<string, string>;
    }
  | {
      /** Selects the provider whose operations and scope are authorized. */
      kind: 'ui';
      /** Embedding-selected element hosting an isolated text-rendering frame. */
      surface: HTMLElement;
    }
  | {
      /** Selects the provider whose operations and scope are authorized. */
      kind: 'native';
      /** Must return true before this native provider executes an input. */
      validate(input: string): boolean;
      /** Trusted application implementation; should cooperate with the cancellation signal. */
      execute(
        input: string,
        context: ExecutionContext,
      ): string | Promise<string>;
    }
  | TrustedGrant;
/** Embedding-owned escape callback, rejected in the hostile profile. */
export interface TrustedGrant
{
  /** Selects the provider whose operations and scope are authorized. */
  readonly kind: 'trusted';
  /** Trusted application implementation; should cooperate with the cancellation signal. */
  readonly execute: (
    request: unknown,
    context: ExecutionContext,
  ) => string | Promise<string>;
}
/** Wraps arbitrary JavaScript execution for the explicit trusted profile. */
export function trustedJavaScript(
  execute: TrustedGrant['execute'],
): TrustedGrant;
/** Wraps unrestricted DOM execution for the explicit trusted profile. */
export function trustedDOM(execute: TrustedGrant['execute']): TrustedGrant;
/** Wraps native FFI execution for the explicit trusted profile. */
export function trustedNativeFFI(
  execute: TrustedGrant['execute'],
): TrustedGrant;
/** Wraps unsandboxed process execution for the explicit trusted profile. */
export function trustedProcess(execute: TrustedGrant['execute']): TrustedGrant;
/** Trusted build output; never construct this authority from a guest manifest. */
export interface NativeArtifactRegistration
{
  readonly artifact: URL | string;
  readonly componentSha256: string;
  readonly nativeSha256: string;
  readonly configuration: string;
  readonly target: string;
}
/** Selects an application-approved artifact and immutable per-instance grants. */
export interface HostOptions
{
  /** Node loads trusted native code prepared during installation; runtime compilation is unavailable. */
  compilation?: 'precompiled';
  /** Node authority supplied by trusted embedding code, independent of guest declarations. */
  nativeArtifacts?: Readonly<Record<string, NativeArtifactRegistration>>;
  /** Node only: false allows an idle embedding process to exit and releases its helper. */
  keepAlive?: boolean;
  /** Required by browser callers; generated by the embedding application's build. */
  registration?: {
    readonly manifests: readonly string[];
    readonly workerURL: URL | string;
  };
  /** Host-built component manifest URL; browsers additionally require registry membership. */
  manifest: URL | string;
  /** Defaults to hostile; trusted explicitly permits escape callbacks. */
  profile?: 'hostile' | 'trusted';
  /** Browser deployment requirements, separate from capability grants. */
  deployment?: 'standard' | 'isolated';
  /** Named providers granted by the embedding application. */
  grants?: Record<string, Grant>;
  /** Overrides to bounded runtime defaults. */
  limits?: Partial<Limits>;
  /** Optional application-owned store shared only through authorized namespaces. */
  storage?: Map<string, Map<string, string>>;
}
/** Records exact artifact and runtime identity without implying proof or cache validity. */
export interface Identity
{
  readonly compilation?: 'precompiled';
  readonly configuration?: string;
  readonly target?: string;
  readonly nativeArtifact?: string | null;
  /** Unique instance identifier; opaque callbacks and handles prevent general cache equivalence. */
  readonly instance: string;
  /** Runtime version and, on Node, the helper binary digest. */
  readonly runtime: string;
  /** SHA-256 digest of the original component. */
  readonly artifact: string;
  /** Build digest of the SDK provider and loader implementation. */
  readonly provider: string;
  /** Digest of serializable grants and limits; opaque callback identity is instance-scoped. */
  readonly policy: string;
  /** Versioned exported WIT interface. */
  readonly interface: string;
}
/** Serializes component calls while keeping separate instances independent. */
export interface HostInstance
{
  /** Integrity and policy identifiers for this invocation context. */
  readonly identity: Identity;
  /** Calls an exported method; aborting cancels and revokes the whole instance. */
  invoke(
    method: string,
    args?: unknown[],
    controls?: {signal?: AbortSignal},
  ): Promise<unknown>;
  /** Releases an owned exported resource; handles cannot cross instances. */
  drop(resource: object, controls?: {signal?: AbortSignal}): Promise<void>;
  /** Terminates the runtime and disposes broker resources. */
  close(): void;
  /** Terminates the runtime, rejecting pending and subsequent work as cancelled. */
  revoke(): void;
}
/** Creates an instance or reports unsupported deployment without downgrading isolation. */
export function createHost(options: HostOptions): Promise<HostInstance>;
