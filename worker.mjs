// Only this host-generated worker and validated jco output execute JavaScript.
// ref:DEC-host-sdk-direct-haskell

import * as wasi from './assets/wasi/index.js';
import {HostError, byteLength, outcomeCode} from './policy.mjs';
/** Installs one worker using the embedding build's immutable artifact allowlist. */
export function startWorker(manifestDigests)
{
  const trustedManifests = new Set(manifestDigests);
  let guest,
    limits,
    manifest,
    remaining,
    nextRequest = 0;
  const pending = new Map();
  const handles = new WeakMap();
  const budgetFlags = [];
  const fail = (code, message) =>
  {
    throw new HostError(code, message);
  };
  const camel = name =>
    name.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
  const hex = bytes =>
    [...new Uint8Array(bytes)]
      .map(x => x.toString(16).padStart(2, '0'))
      .join('');
  const resources = new Map();
  let nextResource = 0;
  const className = name =>
  {
    const value = camel(name);
    return value[0].toUpperCase() + value.slice(1);
  };
  // Conversion follows trusted WIT metadata, including ownership and field spelling.
  // jco's resource objects never leave this worker.
  function resultType(type)
  {
    if (typeof type !== 'number') return undefined;
    const kind = manifest.contract.types[type].kind;
    return kind.type !== undefined ? resultType(kind.type) : kind.result;
  }
  function convert(type, value, output)
  {
    if (type == null) return undefined;
    if (typeof type === 'string')
    {
      if (/^[us]64$/.test(type))
      {
        const low = type === 's64' ? -(1n << 63n) : 0n;
        const high = type === 's64' ? (1n << 63n) - 1n : (1n << 64n) - 1n;
        if (typeof value !== 'bigint' || value < low || value > high)
          fail('failed', 'expected ' + type + ' bigint');
      }
      else if (/^[us](8|16|32)$/.test(type))
      {
        const bits = Number(type.slice(1)),
          signed = type[0] === 's';
        if (
          !Number.isInteger(value) ||
          value < (signed ? -(2 ** (bits - 1)) : 0) ||
          value > 2 ** (bits - (signed ? 1 : 0)) - 1
        )
          fail('failed', 'expected ' + type);
      }
      else if (
        type === 'bool'
          ? typeof value !== 'boolean'
          : type === 'string'
            ? typeof value !== 'string'
            : true
      )
        fail('failed', 'unsupported or invalid scalar ' + type);
      return value;
    }
    const definition = manifest.contract.types[type];
    const kind = definition.kind;
    if (kind.type !== undefined) return convert(kind.type, value, output);
    if (kind.handle)
    {
      const target = kind.handle.own ?? kind.handle.borrow;
      if (output)
      {
        if (kind.handle.own === undefined)
          fail('unsupported', 'borrowed public result');
        if (resources.size >= 1024)
          fail('exhausted', 'resource allocation exhausted');
        const id = String(++nextResource);
        resources.set(id, {value, type: target});
        return {'$host-sdk-resource': id};
      }
      const id = value?.['$host-sdk-resource'];
      const entry = resources.get(id);
      if (!entry || entry.type !== target)
        fail('failed', 'invalid or released resource');
      if (kind.handle.own !== undefined) resources.delete(id);
      return entry.value;
    }
    if (kind.list !== undefined)
    {
      if (!Array.isArray(value) && !(value instanceof Uint8Array))
        fail('failed', 'expected list');
      return Array.from(value, item => convert(kind.list, item, output));
    }
    if (kind.record)
      return Object.fromEntries(
        kind.record.fields.map(field => [
          output ? field.name : camel(field.name),
          convert(
            field.type,
            value[output ? camel(field.name) : field.name],
            output,
          ),
        ]),
      );
    if (kind.option !== undefined)
      return value == null
        ? output
          ? null
          : undefined
        : convert(kind.option, value, output);
    if (kind.variant)
    {
      const variant = kind.variant.cases.find(item => item.name === value?.tag);
      if (!variant) fail('failed', 'invalid variant');
      return {
        tag: value.tag,
        ...(variant.type == null
          ? {}
          : {val: convert(variant.type, value.val, output)}),
      };
    }
    if (kind.enum)
    {
      if (!kind.enum.cases.some(item => item.name === value))
        fail('failed', 'invalid enum');
      return value;
    }
    if (kind.result)
    {
      if (value?.tag !== 'ok' && value?.tag !== 'err')
        fail('failed', 'invalid result');
      return {
        tag: value.tag,
        val: convert(kind.result[value.tag], value.val, output),
      };
    }
    fail('unsupported', 'unsupported public type');
  }
  async function validated(url, expected)
  {
    const response = await fetch(url, {credentials: 'omit', redirect: 'error'});
    if (!response.ok) fail('failed', 'asset unavailable');
    const bytes = await response.arrayBuffer();
    if (hex(await crypto.subtle.digest('SHA-256', bytes)) !== expected)
      fail('failed', 'asset integrity mismatch');
    return bytes;
  }
  function count()
  {
    if (--remaining < 0) fail('exhausted', 'request limit');
  }
  class Provider
  {
    [Symbol.dispose ?? Symbol.for('dispose')]()
    {
      handles.delete(this);
    }
  }
  self.onmessage = async event =>
  {
    const message = event.data;
    if (message.hostResponse)
    {
      const active = pending.get(message.id);
      pending.delete(message.id);
      if (!active) return;
      if (message.error) active.reject(message.error);
      else active.resolve(message.value);
      return;
    }
    try
    {
      if (message.init)
      {
        ({limits, manifest} = message);
        remaining = limits.requests;
        const manifestDigest = hex(
          await crypto.subtle.digest(
            'SHA-256',
            new TextEncoder().encode(JSON.stringify(manifest)),
          ),
        );
        if (!trustedManifests.has(manifestDigest))
          fail('denied', 'unregistered component glue');
        if (
          typeof WebAssembly.Suspending !== 'function' ||
          typeof WebAssembly.promising !== 'function'
        )
          fail('unsupported', 'WebAssembly JSPI required');
        const allowed = new Set(message.providers);
        const imports = {};
        for (const group of ['cli', 'clocks', 'filesystem', 'io', 'random'])
        {
          for (const [name, value] of Object.entries(wasi[group]))
            imports[
              `wasi:${group}/${name.replace(/[A-Z]/g, c => '-' + c.toLowerCase())}`
            ] = value;
        }
        imports['wasi:cli/environment'] = {
          getEnvironment: () => [],
          getArguments: () => [],
          initialCwd: () => undefined,
        };
        imports['wasi:filesystem/preopens'] = {getDirectories: () => []};
        let output = 0;
        const consume = bytes =>
        {
          output += bytes.byteLength;
          if (output > limits.bytes) fail('exhausted', 'stdio output limit');
        };
        wasi.cli._setStdout({write: consume, flush()
        {}});
        wasi.cli._setStderr({write: consume, flush()
        {}});
        imports['host:sdk/host'] = {
          Provider,
          acquire(name)
          {
            try
            {
              count();
              if (!allowed.has(name)) fail('denied', 'provider not granted');
              const provider = new Provider();
              handles.set(provider, name);
              return {tag: 'ok', val: provider};
            }
            catch (error)
            {
              return {
                tag: 'err',
                val: {code: error.code ?? 'failed', message: error.message},
              };
            }
          },
          async perform(provider, request)
          {
            try
            {
              count();
              const name = handles.get(provider);
              if (!name) fail('denied', 'invalid or cross-instance provider');
              if (byteLength(request) > limits.bytes)
                fail('exhausted', 'request bytes');
              const id = ++nextRequest;
              const value = await new Promise((resolve, reject) =>
              {
                pending.set(id, {resolve, reject});
                self.postMessage({hostRequest: {provider: name, request}, id});
              });
              return {tag: 'ok', val: value};
            }
            catch (error)
            {
              return {
                tag: 'err',
                val: {code: error.code ?? 'failed', message: error.message},
              };
            }
          },
        };
        const code = await validated(
          new URL('guest.js', message.manifestURL),
          manifest.assets['guest.js'],
        );
        const blob = URL.createObjectURL(
          new Blob([code], {type: 'text/javascript'}),
        );
        try
        {
          const {instantiate} = await import(blob);
          guest = await instantiate(
            async name =>
            {
              if (
                !Object.hasOwn(manifest.assets, name) ||
                name.includes('/') ||
                name.includes('\\')
              )
                fail('denied', 'unregistered core asset');
              return WebAssembly.compile(
                await validated(
                  new URL(name, message.manifestURL),
                  manifest.assets[name],
                ),
              );
            },
            imports,
            async (module, coreImports) =>
            {
              const instance = await WebAssembly.instantiate(
                module,
                coreImports,
              );
              const flag = instance.exports['host-sdk:memory-exhausted'];
              if (flag) budgetFlags.push(flag);
              return instance;
            },
          );
        }
        finally
        {
          URL.revokeObjectURL(blob);
        }
        self.postMessage({ready: true});
        return;
      }
      if (!guest) fail('failed', 'instance not initialized');
      if (byteLength(message.args) > limits.bytes)
        fail('exhausted', 'input bytes');
      const exported =
        guest[manifest.interface] ?? guest[manifest.interface.split('@')[0]];
      for (const flag of budgetFlags) flag.value = 0;
      if (message.method === '[resource-drop]')
      {
        const id = message.args[0]?.['$host-sdk-resource'];
        const entry = resources.get(id);
        if (!entry) fail('failed', 'invalid or released resource');
        resources.delete(id);
        const dispose = Symbol.dispose ?? Symbol.for('dispose');
        await entry.value[dispose]();
        self.postMessage({value: undefined});
        return;
      }
      const fn =
        manifest.contract?.interfaces[manifest.interface]?.[message.method];
      if (!fn) fail('unsupported', 'unknown guest method');
      if (message.args.length !== fn.params.length)
        fail('failed', 'argument count mismatch');
      const args = fn.params.map((param, index) =>
        convert(param.type, message.args[index], false),
      );
      let raw;
      if (message.method.startsWith('[constructor]'))
        raw = await new exported[className(message.method.slice(13))](...args);
      else if (message.method.startsWith('[method]'))
      {
        const [, method] = message.method.slice(8).split('.');
        raw = await args[0][camel(method)](...args.slice(1));
      }
      else if (message.method.startsWith('[static]'))
      {
        const [resource, method] = message.method.slice(8).split('.');
        raw = await exported[className(resource)][camel(method)](...args);
      }
      else raw = await exported[camel(message.method)](...args);
      const result = resultType(fn.result);
      const value = convert(result ? result.ok : fn.result, raw, true);
      if (byteLength(value) > limits.bytes) fail('exhausted', 'output bytes');
      self.postMessage({value});
    }
    catch (error)
    {
      const componentError = error != null && Object.hasOwn(error, 'payload');
      const schema = resultType(
        manifest?.contract?.interfaces[manifest.interface]?.[message.method]
          ?.result,
      );
      const payload =
        componentError && schema
          ? convert(schema.err, error.payload, true)
          : error;

      self.postMessage({
        fatal: !componentError || budgetFlags.some(flag => flag.value !== 0),
        error: {
          code: budgetFlags.some(flag => flag.value !== 0)
            ? 'exhausted'
            : outcomeCode(payload?.code),
          message:
            typeof payload === 'string'
              ? payload
              : (payload?.message ?? String(error)),
          ...(componentError ? {payload} : {}),
        },
      });
    }
  };
}
