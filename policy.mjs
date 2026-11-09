// Embedding applications own these grants. Guest declarations confer no access.
// ref:DEC-host-sdk-direct-haskell
/** Carries a stable operation outcome without collapsing refusal into ordinary failure. */
export class HostError extends Error
{
  /** Retains the broker outcome separately from its human-readable explanation. */
  constructor(code, message, payload)
  {
    super(message);
    this.name = 'HostError';
    this.code = code;
    if (payload !== undefined) this.payload = payload;
  }
}
/** Application error payloads retain their data without inventing SDK status codes. */
export const outcomeCode = code =>
  ['denied', 'unsupported', 'cancelled', 'exhausted', 'failed'].includes(code)
    ? code
    : 'failed';
/** Throws a classified outcome at a policy enforcement boundary. */
export const fail = (code, message) =>
{
  throw new HostError(code, message);
};
const encoder = new TextEncoder();
/** WIT identifiers cannot contain $, so this integer marker cannot be a record field.
 * The helper validates its decimal representation against the actual WIT width.
 * Ordinary strings stay strings, including strings that look like large numbers.
 */
export const stringifyTransport = value =>
  JSON.stringify(value, (_, item) =>
    typeof item === 'bigint'
      ? {'$host-sdk-integer': item.toString()}
      : item instanceof Uint8Array
        ? Array.from(item)
        : item,
  );
/** Restores wide integers only from the helper's reserved canonical scalar marker. */
export const parseTransport = text =>
  JSON.parse(text, (_, item) =>
  {
    if (
      item &&
      typeof item === 'object' &&
      Object.hasOwn(item, '$host-sdk-integer')
    )
    {
      if (
        Object.keys(item).length !== 1 ||
        typeof item['$host-sdk-integer'] !== 'string' ||
        !/^-?(0|[1-9][0-9]*)$/.test(item['$host-sdk-integer'])
      )
        fail('failed', 'invalid integer transport');
      return BigInt(item['$host-sdk-integer']);
    }
    return item;
  });
/** Measures UTF-8 transport bytes, including JSON structure for composite messages. */
export const byteLength = value =>
  encoder.encode(typeof value === 'string' ? value : stringifyTransport(value))
    .length;
/** Bounds each instance even when the embedding application supplies no limits. */
export const defaults = Object.freeze({
  memory: 512 * 1024 * 1024,
  bytes: 16 * 1024 * 1024,
  requests: 1000,
  fuel: 10_000_000_000,
  timeout: 30000,
});
const allowed = new Set([
  'files',
  'network',
  'storage',
  'environment',
  'ui',
  'native',
  'trusted',
]);

/** Marks an embedding-owned callback that requires the explicit trusted profile. */
export function trustedJavaScript(execute)
{
  if (typeof execute !== 'function')
    fail('failed', 'trustedJavaScript needs a function');
  return Object.freeze({kind: 'trusted', execute});
}

/** Names unrestricted DOM authority for explicit rejection in hostile mode. */
export const trustedDOM = execute =>
  Object.freeze({...trustedJavaScript(execute), escape: 'dom'});
/** Names native FFI authority for explicit rejection in hostile mode. */
export const trustedNativeFFI = execute =>
  Object.freeze({...trustedJavaScript(execute), escape: 'native-ffi'});
/** Names unsandboxed process authority for explicit rejection in hostile mode. */
export const trustedProcess = execute =>
  Object.freeze({...trustedJavaScript(execute), escape: 'process'});

/** Clones policy data so later changes cannot escalate an existing instance. */
export function configure(options = {})
{
  if (!['hostile', 'trusted'].includes(options.profile ?? 'hostile'))
    fail('unsupported', 'unknown execution profile');
  const limits = {...defaults, ...options.limits};
  for (const [key, value] of Object.entries(limits))
  {
    if (!(key in defaults) || !Number.isSafeInteger(value) || value <= 0)
      fail('failed', `invalid limit: ${key}`);
  }
  if (limits.memory > 1024 * 1024 * 1024 || limits.bytes > 64 * 1024 * 1024)
    fail('unsupported', 'limit exceeds SDK maximum');
  const grants = new Map();
  for (const [name, input] of Object.entries(options.grants ?? {}))
  {
    if (!name || !input || !allowed.has(input.kind))
      fail('unsupported', 'unknown provider kind');
    if (input.kind === 'trusted' && options.profile !== 'trusted')
      fail('denied', 'trustedJavaScript is rejected in the hostile profile');
    // Functions and browser handles stay in the broker. Clone all mutable policy data.
    const {handle, execute, validate, surface, ...data} = input;
    grants.set(
      name,
      Object.freeze({
        ...structuredClone(data),
        handle,
        execute,
        validate,
        surface,
      }),
    );
  }
  return {limits: Object.freeze(limits), grants};
}

/** Rejects traversal, absolute paths and ambiguous path segments before handle lookup. */
export function relativePath(path)
{
  if (
    typeof path !== 'string' ||
    !path ||
    path.includes('\\') ||
    path.includes('\0') ||
    path.split('/').some(x => !x || x === '.' || x === '..')
  )
    fail('denied', 'path outside grant');
  return path.split('/');
}

/** Mediates each operation against immutable grants and the instance cancellation signal. */
export function createBroker(
  configuration,
  {signal, storage = new Map()} = {},
)
{
  const {grants, limits} = configuration;
  const frames = new Map();
  let requests = 0;
  const check = () =>
  {
    if (signal?.aborted) fail('cancelled', 'instance revoked');
  };
  async function perform(name, request)
  {
    check();
    if (++requests > limits.requests) fail('exhausted', 'request limit');
    if (byteLength(request) > limits.bytes)
      fail('exhausted', 'request byte limit');
    const grant = grants.get(name);
    if (!grant) fail('denied', 'provider not granted');
    const {tag, val} = request;
    let result;
    switch (grant.kind)
    {
      case 'files':
      {
        const reading = tag === 'read-text';
        if (
          (!reading && tag !== 'write-text') ||
          !(reading ? grant.read : grant.write)
        )
          fail('denied', 'file operation not granted');
        if (!grant.handle) fail('unsupported', 'browser file handle required');
        const parts = relativePath(reading ? val : val.key);
        let directory = grant.handle;
        for (const part of parts.slice(0, -1))
          directory = await directory.getDirectoryHandle(part, {
            create: !reading,
          });
        check();
        const file = await directory.getFileHandle(parts.at(-1), {
          create: !reading,
        });
        if (reading)
        {
          const data = await file.getFile();
          if (data.size > limits.bytes) fail('exhausted', 'file byte limit');
          result = await data.text();
        }
        else
        {
          if (byteLength(val.value) > limits.bytes)
            fail('exhausted', 'write byte limit');
          const writer = await file.createWritable();
          try
          {
            check();
            await writer.write(val.value);
            check();
            await writer.close();
          }
          catch (error)
          {
            await writer.abort().catch(() =>
            {});
            throw error;
          }
          result = '';
        }
        break;
      }
      case 'network':
      {
        if (tag !== 'fetch') fail('denied', 'network operation not granted');
        const url = new URL(val.url);
        if (
          url.protocol !== 'https:' &&
          !(grant.allowHttp && url.protocol === 'http:')
        )
          fail('denied', 'network protocol not granted');
        if (url.username || url.password || url.hash)
          fail('denied', 'URL credentials and fragments are forbidden');
        const method = val.method.toUpperCase();
        const match = grant.destinations?.some(
          d =>
            url.origin === d.origin &&
            (url.pathname === (d.path ?? '/') ||
              (d.subpaths === true &&
                url.pathname.startsWith(
                  (d.path ?? '/').replace(/\/$/, '') + '/',
                ))) &&
            d.methods?.includes(method),
        );
        if (!match)
          fail('denied', 'network destination or operation not granted');
        const response = await fetch(url, {
          method,
          body: method === 'GET' ? undefined : val.body,
          credentials: 'omit',
          redirect: 'manual',
          signal,
          headers: grant.headers ?? {},
        });
        if (
          response.type === 'opaqueredirect' ||
          (response.status >= 300 && response.status < 400)
        )
          fail('denied', 'redirect requires a separate authorized request');
        if (!response.ok) fail('failed', `HTTP ${response.status}`);
        const reader = response.body?.getReader();
        let count = 0;
        const chunks = [];
        try
        {
          if (reader)
            for (;;)
            {
              const {value, done} = await reader.read();
              if (done) break;
              count += value.byteLength;
              if (count > limits.bytes)
                fail('exhausted', 'network response limit');
              chunks.push(value);
            }
        }
        finally
        {
          await reader?.cancel().catch(() =>
          {});
        }
        const bytes = new Uint8Array(count);
        let offset = 0;
        for (const chunk of chunks)
        {
          bytes.set(chunk, offset);
          offset += chunk.length;
        }
        result = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
        break;
      }
      case 'storage':
      {
        if (
          !grant.namespace ||
          !Number.isSafeInteger(grant.quota) ||
          grant.quota < 0
        )
          fail('failed', 'storage namespace and quota required');
        let values = storage.get(grant.namespace);
        if (!values)
        {
          values = new Map();
          storage.set(grant.namespace, values);
        }
        if (tag === 'get-value' && grant.read) result = values.get(val) ?? '';
        else if (tag === 'put-value' && grant.write)
        {
          let size = 0;
          for (const [key, value] of values)
            if (key !== val.key) size += byteLength(key) + byteLength(value);
          if (size + byteLength(val.key) + byteLength(val.value) > grant.quota)
            fail('exhausted', 'storage quota');
          values.set(val.key, val.value);
          result = '';
        }
        else fail('denied', 'storage operation not granted');
        break;
      }
      case 'environment':
        if (tag !== 'get-value' || !Object.hasOwn(grant.values ?? {}, val))
          fail('denied', 'environment value not granted');
        result = grant.values[val];
        break;
      case 'ui':
      {
        if (tag !== 'render') fail('denied', 'UI operation not granted');
        if (typeof document === 'undefined' || !grant.surface)
          fail('unsupported', 'UI requires an embedding surface');
        const frame = document.createElement('iframe');
        frame.setAttribute('sandbox', '');
        // The baseline surface renders text; richer UI needs a separately reviewed protocol.
        const text = val
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
        frame.srcdoc = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'"><pre>${text}</pre>`;
        frames.get(name)?.remove();
        grant.surface.replaceChildren(frame);
        frames.set(name, frame);
        result = '';
        break;
      }
      case 'native':
        if (tag !== 'invoke') fail('denied', 'native operation not granted');
        if (
          typeof grant.validate !== 'function' ||
          grant.validate(val) !== true
        )
          fail('denied', 'native input rejected');
        if (typeof grant.execute !== 'function')
          fail('unsupported', 'native provider unavailable');
        result = await grant.execute(val, {signal});
        break;
      case 'trusted':
        result = await grant.execute(request, {signal});
        break;
      default:
        fail('unsupported', 'provider unavailable');
    }
    check();
    if (typeof result !== 'string') fail('failed', 'provider must return text');
    if (byteLength(result) > limits.bytes)
      fail('exhausted', 'response byte limit');
    return result;
  }
  return {
    async perform(name, request)
    {
      try
      {
        return await perform(name, request);
      }
      catch (error)
      {
        if (error instanceof HostError) throw error;
        const code = signal?.aborted
          ? 'cancelled'
          : ({
              NotAllowedError: 'denied',
              SecurityError: 'denied',
              NotSupportedError: 'unsupported',
              QuotaExceededError: 'exhausted',
              AbortError: 'cancelled',
            }[error?.name] ?? 'failed');
        throw new HostError(code, error?.message ?? String(error));
      }
    },
    dispose: () =>
    {
      for (const frame of frames.values()) frame.remove();
      frames.clear();
    },
  };
}

// Resource identity never comes from caller-supplied fields or JSON. This module
// has one WeakMap for all instances so cross-instance use is rejected locally.
const resourceOwners = new WeakMap();
/** Translates opaque, instance-bound application resources at the transport edge. */
export function createResourceScope()
{
  const scope = {};
  const visit = (value, decode) =>
  {
    if (!value || typeof value !== 'object' || value instanceof Uint8Array)
      return value;
    const owner = resourceOwners.get(value);
    if (owner)
    {
      if (decode || owner.scope !== scope)
        fail('denied', 'resource belongs to another instance');
      return {'$host-sdk-resource': owner.id};
    }
    if (Object.hasOwn(value, '$host-sdk-resource'))
    {
      if (!decode) fail('denied', 'forged resource token');
      if (
        Object.keys(value).length !== 1 ||
        typeof value['$host-sdk-resource'] !== 'string'
      )
        fail('failed', 'invalid resource response');
      const resource = Object.freeze(Object.create(null));
      resourceOwners.set(resource, {scope, id: value['$host-sdk-resource']});
      return resource;
    }
    if (Array.isArray(value)) return value.map(item => visit(item, decode));
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, visit(item, decode)]),
    );
  };
  return {
    encode: value => visit(value, false),
    decode: value => visit(value, true),
  };
}
