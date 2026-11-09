// Generated public declarations come from the same resolved WIT as the runtime.
// ref:DEC-host-sdk-typed-application-boundary
const camel = name =>
  name.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
const pascal = name =>
{
  const value = camel(name);
  return value[0].toUpperCase() + value.slice(1);
};
/** Emits an asynchronous application API with opaque resource types. */
export function declarations(contract, interfaceName)
{
  const resultType = type =>
  {
    if (typeof type !== 'number') return undefined;
    const kind = contract.types[type].kind;
    return kind.type !== undefined ? resultType(kind.type) : kind.result;
  };
  const functions = Object.values(contract.interfaces[interfaceName]);
  const visited = new Set();
  const names = new Map();
  function typeName(id)
  {
    const name = contract.types[id].name;
    const label = name ? pascal(name) : `Type${id}`;
    if (names.has(label) && names.get(label) !== id)
      throw new Error('unsupported: colliding façade type names');
    names.set(label, id);
    return label;
  }
  function type(ty)
  {
    if (ty == null) return 'void';
    if (typeof ty === 'string')
    {
      const value = {
        string: 'string',
        bool: 'boolean',
        u8: 'number',
        s8: 'number',
        u16: 'number',
        s16: 'number',
        u32: 'number',
        s32: 'number',
        u64: 'bigint',
        s64: 'bigint',
      }[ty];
      if (!value) throw new Error('unsupported façade scalar ' + ty);
      return value;
    }
    if (contract.types[ty].kind.type !== undefined)
      return type(contract.types[ty].kind.type);
    if (visited.has(ty)) return typeName(ty);
    visited.add(ty);
    const {kind} = contract.types[ty];
    if (kind === 'resource') return typeName(ty);
    // Traverse every referenced type now, including error types exposed by WIT.
    expression(kind);
    return typeName(ty);
  }
  function expression(kind)
  {
    if (kind.type !== undefined) return type(kind.type);
    if (kind.handle) return type(kind.handle.own ?? kind.handle.borrow);
    if (kind.list !== undefined)
      return kind.list === 'u8' ? 'Uint8Array' : `Array<${type(kind.list)}>`;
    if (kind.option !== undefined) return `(${type(kind.option)} | null)`;
    if (kind.result)
      return `{tag: 'ok'; val: ${type(kind.result.ok)}} | {tag: 'err'; val: ${type(kind.result.err)}}`;
    if (kind.record)
      return `{${kind.record.fields.map(field => `${JSON.stringify(camel(field.name))}: ${type(field.type)}`).join('; ')}}`;
    if (kind.variant)
      return kind.variant.cases
        .map(
          item =>
            `{tag: ${JSON.stringify(item.name)}${item.type == null ? '' : `; val: ${type(item.type)}`}}`,
        )
        .join(' | ');
    if (kind.enum)
      return kind.enum.cases.map(item => JSON.stringify(item.name)).join(' | ');
    throw new Error('unsupported façade type');
  }
  function signature(fn, method = false)
  {
    if (method) type(fn.params[0].type);
    const params = fn.params
      .slice(method ? 1 : 0)
      .map(param => `${camel(param.name)}: ${type(param.type)}`);
    params.push('controls?: {signal?: AbortSignal}');
    const result = resultType(fn.result);
    // Record the error schema too, while Promise rejection carries the failure.
    type(fn.result);
    return `(${params.join(', ')}): Promise<${type(result ? result.ok : fn.result)}>`;
  }
  const operations = functions
    .filter(fn => fn.kind?.method === undefined)
    .map(fn =>
    {
      const name = fn.name.startsWith('[constructor]')
        ? 'new' + pascal(fn.name.slice(13))
        : camel(fn.name.replace(/^\[static\]/, '').replace('.', '-'));
      if (
        ['identity', 'invoke', 'drop', 'close', 'revoke', 'then'].includes(name)
      )
        throw new Error('unsupported: export conflicts with client lifecycle');
      return `${JSON.stringify(name)}${signature(fn)};`;
    });
  for (const fn of functions) signature(fn, fn.kind?.method !== undefined);
  const types = [];
  for (const id of visited)
  {
    const {kind} = contract.types[id];
    if (kind === 'resource')
    {
      const methods = functions
        .filter(fn => fn.kind?.method === id)
        .map(fn =>
        {
          const name = camel(fn.name.split('.')[1]);
          if (name === 'dispose' || name === 'then')
            throw new Error(
              'unsupported: resource method conflicts with disposal',
            );
          return `${JSON.stringify(name)}${signature(fn, true)};`;
        });
      types.push(
        `export interface ${typeName(id)} {readonly [resourceBrand]: ${JSON.stringify(typeName(id))}; dispose(controls?: {signal?: AbortSignal}): Promise<void>; ${methods.join('\n')}}`,
      );
    }
    else types.push(`export type ${typeName(id)} = ${expression(kind)};`);
  }
  return `// Generated from resolved WIT. Do not edit.\nimport type {HostInstance, HostOptions} from 'wasm-platform-kit';\ndeclare const resourceBrand: unique symbol;\n${types.join('\n')}\nexport interface Application extends HostInstance {${operations.join('\n')}}\nexport function createApplication(options?: Omit<HostOptions, 'manifest' | 'nativeArtifacts'>): Promise<Application>;\n`;
}
