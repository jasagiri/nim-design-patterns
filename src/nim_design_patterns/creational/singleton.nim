## Singleton Pattern implementation with thread safety

import std/[locks, atomics, strformat]
import results
import nim_libaspects/[logging, monitoring]
import ../core/base

type
  Singleton*[T] = ref object of Pattern
    ## Thread-safe singleton implementation
    instance: ptr T
    initialized: Atomic[bool]
    lock: Lock
    creator: proc(): T
    logger: Logger
    monitor: MonitoringSystem

var singletonRegistry {.threadvar.}: Table[string, pointer]

proc newSingleton*[T](name: string, creator: proc(): T): Singleton[T] =
  ## Create a new singleton wrapper
  result = Singleton[T](
    name: name,
    kind: pkCreational,
    description: "Singleton pattern for single instance",
    creator: creator
  )
  initLock(result.lock)
  result.initialized.store(false)

proc withLogging*(singleton: Singleton, logger: Logger): Singleton =
  ## Add logging to singleton
  singleton.logger = logger
  singleton

proc withMonitoring*(singleton: Singleton, monitor: MonitoringSystem): Singleton =
  ## Add monitoring to singleton
  singleton.monitor = monitor
  singleton

proc getInstance*[T](singleton: Singleton[T]): Result[ptr T, PatternError] =
  ## Get the singleton instance (thread-safe)
  # Fast path - already initialized
  if singleton.initialized.load(moAcquire):
    return Result[ptr T, PatternError].ok(singleton.instance)
  
  # Slow path - need to initialize
  withLock(singleton.lock):
    # Double-check inside lock
    if singleton.initialized.load(moRelaxed):
      return Result[ptr T, PatternError].ok(singleton.instance)
    
    try:
      if not singleton.logger.isNil:
        singleton.logger.debug(&"Creating singleton instance for '{singleton.name}'")
      
      # Create the instance
      let obj = singleton.creator()
      singleton.instance = cast[ptr T](alloc0(sizeof(T)))
      singleton.instance[] = obj
      
      # Mark as initialized
      singleton.initialized.store(true, moRelease)
      
      if not singleton.logger.isNil:
        singleton.logger.info(&"Singleton '{singleton.name}' created successfully")
      
      if not singleton.monitor.isNil:
        singleton.monitor.recordEvent(&"singleton.created.{singleton.name}")
        singleton.monitor.gauge("singleton.instances", 1)
      
      Result[ptr T, PatternError].ok(singleton.instance)
      
    except CatchableError as e:
      let error = newPatternError(singleton.name, 
        &"Failed to create singleton: {e.msg}", "initialization")
      
      if not singleton.logger.isNil:
        singleton.logger.error(error.msg)
      
      Result[ptr T, PatternError].err(error)

proc reset*[T](singleton: Singleton[T]) =
  ## Reset the singleton (mainly for testing)
  withLock(singleton.lock):
    if singleton.initialized.load(moRelaxed) and not singleton.instance.isNil:
      dealloc(singleton.instance)
      singleton.instance = nil
      singleton.initialized.store(false, moRelease)
      
      if not singleton.logger.isNil:
        singleton.logger.warn(&"Singleton '{singleton.name}' reset")

# Template for singleton creation
template singleton*(T: typedesc, name: string, body: untyped): auto =
  ## Create a singleton with custom initialization
  let s = newSingleton[T](name, proc(): T =
    body
  )
  s

template singletonWithAspects*(T: typedesc, name: string, 
                              logger: Logger, monitor: MonitoringSystem,
                              body: untyped): auto =
  ## Create a singleton with logging and monitoring
  let s = singleton(T, name, body)
    .withLogging(logger)
    .withMonitoring(monitor)
  s

# Macro for compile-time singleton
macro defineSingleton*(name: untyped, T: typedesc, init: untyped): untyped =
  ## Define a singleton at compile time
  let singletonVar = ident($name & "Singleton")
  let getterName = ident("get" & $name)
  
  result = quote do:
    var `singletonVar` = newSingleton[`T`]($`name`, proc(): `T` =
      `init`
    )
    
    proc `getterName`(): Result[ptr `T`, PatternError] =
      `singletonVar`.getInstance()

# Registry for global singletons
proc registerGlobalSingleton*[T](name: string, singleton: Singleton[T]) =
  ## Register a singleton globally
  singletonRegistry[name] = cast[pointer](singleton)

proc getGlobalSingleton*(name: string): Result[pointer, PatternError] =
  ## Get a global singleton by name
  if name in singletonRegistry:
    Result[pointer, PatternError].ok(singletonRegistry[name])
  else:
    Result[pointer, PatternError].err(
      newPatternError("GlobalRegistry", &"Singleton '{name}' not found")
    )