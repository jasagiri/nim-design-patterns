## Adapter Pattern implementation

import std/[macros, strformat, tables]
import results
import nim_libaspects/logging
import ../core/base

type
  AdapterFunc*[T, U] = proc(from: T): U
  
  Adapter*[T, U] = ref object of Pattern
    ## Generic adapter for type conversions
    adaptFunc: AdapterFunc[T, U]
    logger: Logger
    sourceType: string
    targetType: string
  
  AdapterRegistry* = ref object
    ## Registry for multiple adapters
    adapters: Table[string, pointer]

proc newAdapter*[T, U](adaptFunc: AdapterFunc[T, U], name = ""): Adapter[T, U] =
  ## Create a new adapter
  result = Adapter[T, U](
    name: if name.len > 0: name else: &"Adapter_{$T}To{$U}",
    kind: pkStructural,
    description: &"Adapter pattern from {$T} to {$U}",
    adaptFunc: adaptFunc,
    sourceType: $T,
    targetType: $U
  )

proc withLogging*[T, U](adapter: Adapter[T, U], logger: Logger): Adapter[T, U] =
  ## Add logging to adapter
  adapter.logger = logger
  adapter

proc adapt*[T, U](adapter: Adapter[T, U], source: T): Result[U, PatternError] =
  ## Adapt from source to target type
  try:
    if not adapter.logger.isNil:
      adapter.logger.debug(&"Adapting from {adapter.sourceType} to {adapter.targetType}")
    
    let result = adapter.adaptFunc(source)
    
    if not adapter.logger.isNil:
      adapter.logger.info(&"Successfully adapted {adapter.sourceType} to {adapter.targetType}")
    
    Result[U, PatternError].ok(result)
    
  except CatchableError as e:
    let error = newPatternError(adapter.name, 
      &"Adaptation failed: {e.msg}", "adaptation")
    
    if not adapter.logger.isNil:
      adapter.logger.error(error.msg)
    
    Result[U, PatternError].err(error)

# Registry
proc newAdapterRegistry*(): AdapterRegistry =
  AdapterRegistry(adapters: initTable[string, pointer]())

proc register*[T, U](registry: AdapterRegistry, adapter: Adapter[T, U]) =
  ## Register an adapter
  let key = &"{$T}->{$U}"
  registry.adapters[key] = cast[pointer](adapter)

proc get*[T, U](registry: AdapterRegistry): Result[Adapter[T, U], PatternError] =
  ## Get adapter for specific types
  let key = &"{$T}->{$U}"
  
  if key notin registry.adapters:
    Result[Adapter[T, U], PatternError].err(
      newPatternError("AdapterRegistry", &"No adapter found for {key}")
    )
  else:
    Result[Adapter[T, U], PatternError].ok(
      cast[Adapter[T, U]](registry.adapters[key])
    )

# Template for direct adapter creation
template adapt*[T, U](source: T, body: untyped): U =
  ## Create and apply adapter inline
  block:
    let adapter = newAdapter(proc(from: T): U = body)
    let result = adapter.adapt(source)
    if result.isErr:
      raise newException(PatternError, result.error.msg)
    result.get()

# Macro for type-safe adapters
macro createAdapter*[T, U](name: string, body: untyped): untyped =
  ## Create named adapter at compile time
  let adapterName = ident(name.strVal & "Adapter")
  let sourceType = ident($T)
  let targetType = ident($U)
  
  result = quote do:
    let `adapterName` = newAdapter[`sourceType`, `targetType`](
      proc(from: `sourceType`): `targetType` =
        `body`
    )

# Two-way adapter
type TwoWayAdapter*[T, U] = ref object of Pattern
  ## Bi-directional adapter
  forwardAdapter: Adapter[T, U]
  backwardAdapter: Adapter[U, T]

proc newTwoWayAdapter*[T, U](
    toU: AdapterFunc[T, U], 
    toT: AdapterFunc[U, T],
    name = ""): TwoWayAdapter[T, U] =
  ## Create two-way adapter
  result = TwoWayAdapter[T, U](
    name: if name.len > 0: name else: &"TwoWayAdapter_{$T}_{$U}",
    kind: pkStructural,
    description: &"Two-way adapter between {$T} and {$U}",
    forwardAdapter: newAdapter[T, U](toU),
    backwardAdapter: newAdapter[U, T](toT)
  )

proc withLogging*[T, U](adapter: TwoWayAdapter[T, U], 
                       logger: Logger): TwoWayAdapter[T, U] =
  ## Add logging to two-way adapter
  adapter.forwardAdapter.withLogging(logger)
  adapter.backwardAdapter.withLogging(logger)
  adapter

proc adaptToU*[T, U](adapter: TwoWayAdapter[T, U], source: T): Result[U, PatternError] =
  ## Adapt from T to U
  adapter.forwardAdapter.adapt(source)

proc adaptToT*[T, U](adapter: TwoWayAdapter[T, U], source: U): Result[T, PatternError] =
  ## Adapt from U to T
  adapter.backwardAdapter.adapt(source)

# Object adapter
type
  ObjectAdapter*[T, U] = ref object of Adapter[T, U]
    ## Object-based adapter (composition)
    adaptee: T

proc newObjectAdapter*[T, U](adaptee: T, adaptFunc: AdapterFunc[T, U]): ObjectAdapter[T, U] =
  ## Create object adapter with composition
  result = ObjectAdapter[T, U](
    name: &"ObjectAdapter_{$T}To{$U}",
    kind: pkStructural,
    description: &"Object adapter from {$T} to {$U}",
    adaptFunc: adaptFunc,
    adaptee: adaptee,
    sourceType: $T,
    targetType: $U
  )

proc getAdaptee*[T, U](adapter: ObjectAdapter[T, U]): T =
  ## Get the wrapped adaptee object
  adapter.adaptee