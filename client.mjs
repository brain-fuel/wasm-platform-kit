// Typed façades use WIT metadata; application decisions never live in this module.
// ref:DEC-host-sdk-typed-application-boundary
import {HostError} from './policy.mjs';
const camel = name =>
  name.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
const pascal = name =>
{
  const value = camel(name);
  return value[0].toUpperCase() + value.slice(1);
};

/** Adds Promise-returning WIT operations and scoped resources to a generic host. */
export function createClient(host, contract, interfaceName)
{
  const resultType = type =>
  {
    if (typeof type !== 'number') return undefined;
    const kind = contract.types[type].kind;
    return kind.type !== undefined ? resultType(kind.type) : kind.result;
  };
  const functions = contract.interfaces[interfaceName];
  const wrappers = new WeakMap();
  function transform(type, value, output)
  {
    if (type == null || typeof type === 'string') return value;
    const {kind} = contract.types[type];
    if (kind.type !== undefined) return transform(kind.type, value, output);
    if (kind.handle)
    {
      const target = kind.handle.own ?? kind.handle.borrow;
      if (!output)
      {
        const entry = wrappers.get(value);
        if (!entry || entry.type !== target)
          throw new HostError(
            'denied',
            'resource belongs to another client or type',
          );
        return entry.token;
      }
      const resource = {};
      wrappers.set(resource, {type: target, token: value});
      for (const fn of Object.values(functions))
        if (fn.kind?.method === target)
        {
          const name = camel(fn.name.split('.')[1]);
          if (name === 'dispose' || name === 'then')
            throw new HostError(
              'unsupported',
              'resource method conflicts with lifecycle',
            );
          resource[name] = (...args) => call(fn, [resource, ...args]);
        }
      resource.dispose = controls => host.drop(value, controls);
      return Object.freeze(resource);
    }
    if (kind.list !== undefined)
    {
      const items = Array.from(value, item =>
        transform(kind.list, item, output),
      );
      return output && kind.list === 'u8' ? new Uint8Array(items) : items;
    }
    if (kind.record)
      return Object.fromEntries(
        kind.record.fields.map(field => [
          output ? camel(field.name) : field.name,
          transform(
            field.type,
            value[output ? field.name : camel(field.name)],
            output,
          ),
        ]),
      );
    if (kind.option !== undefined)
      return value == null ? null : transform(kind.option, value, output);
    if (kind.variant)
    {
      const variant = kind.variant.cases.find(item => item.name === value?.tag);
      if (!variant) throw new HostError('failed', 'invalid variant');
      return {
        tag: value.tag,
        ...(variant.type == null
          ? {}
          : {val: transform(variant.type, value.val, output)}),
      };
    }
    if (kind.result)
    {
      if (value?.tag !== 'ok' && value?.tag !== 'err')
        throw new HostError('failed', 'invalid result');
      return {
        tag: value.tag,
        val: transform(kind.result[value.tag], value.val, output),
      };
    }
    if (kind.enum) return value;
    throw new HostError('unsupported', 'unsupported façade type');
  }
  async function call(fn, values)
  {
    if (
      values.length < fn.params.length ||
      values.length > fn.params.length + 1
    )
      throw new HostError('failed', 'argument count mismatch');
    const args = fn.params.map((param, i) =>
      transform(param.type, values[i], false),
    );
    const result = resultType(fn.result);
    try
    {
      const value = await host.invoke(fn.name, args, values[fn.params.length]);
      return transform(result ? result.ok : fn.result, value, true);
    }
    catch (error)
    {
      if (result && Object.hasOwn(error, 'payload'))
        error.payload = transform(result.err, error.payload, true);
      throw error;
    }
  }
  const client = {...host};
  for (const fn of Object.values(functions))
  {
    if (fn.kind?.method !== undefined) continue;
    const name = fn.name.startsWith('[constructor]')
      ? 'new' + pascal(fn.name.slice(13))
      : camel(fn.name.replace(/^\[static\]/, '').replace('.', '-'));
    if (Object.hasOwn(client, name) || name === 'then')
      throw new HostError(
        'unsupported',
        'export conflicts with client lifecycle',
      );
    client[name] = (...args) => call(fn, args);
  }
  return Object.freeze(client);
}
