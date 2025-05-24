## Factory Pattern implementation with cross-cutting concerns

import std/[tables, strformat, times, macros]
import results
import nim_libaspects/[logging, monitoring, metrics]
import ../core/base

type
  FactoryFunc*[T] = proc(): T
  
  Factory*[T] = ref object of Pattern
    ## Generic factory for creating objects
    creators: Table[string, FactoryFunc[T]]
    logger: Logger
    monitor: MonitoringSystem
    metricsCollector: MetricsRegistry
    defaultCreator: FactoryFunc[T]
  
  FactoryBuilder*[T] = ref object
    ## Builder for configuring factories
    factory: Factory[T]

# Helper functions
proc recordMetric(registry: MetricsRegistry, metricType: string, name: string, value: float = 1.0, labels: seq[string] = @[]) =
  ## Helper to record metrics safely
  if registry.isNil:
    return
  
  case metricType
  of "counter":
    let counter = registry.counter(name, @["key"])  # Declare label names
    counter.inc(labels, value)
  of "timer":
    # For timers, we just track the time manually since Timer API requires start/stop
    let gauge = registry.gauge(name & "_duration_ms", @["key"])  # Declare label names
    gauge.set(value, labels)
  else:
    discard

proc newFactory*[T](name = "Factory"): Factory[T] =
  ## Create a new factory instance
  result = Factory[T](
    name: name,
    kind: pkCreational,
    description: "Factory pattern for object creation",
    creators: initTable[string, FactoryFunc[T]]()
  )

proc newFactoryBuilder*[T](name = "Factory"): FactoryBuilder[T] =
  ## Create a factory builder
  FactoryBuilder[T](factory: newFactory[T](name))

# Builder methods
proc withLogging*(builder: FactoryBuilder, logger: Logger): FactoryBuilder =
  ## Add logging to factory
  builder.factory.logger = logger
  builder

proc withMonitoring*(builder: FactoryBuilder, monitor: MonitoringSystem): FactoryBuilder =
  ## Add monitoring to factory  
  builder.factory.monitor = monitor
  builder

proc withMetrics*(builder: FactoryBuilder, collector: MetricsRegistry): FactoryBuilder =
  ## Add metrics collection to factory
  builder.factory.metricsCollector = collector
  builder

proc register*[T](builder: FactoryBuilder[T], key: string, 
                  creator: FactoryFunc[T]): FactoryBuilder[T] =
  ## Register a creator function
  builder.factory.creators[key] = creator
  builder

proc setDefault*[T](builder: FactoryBuilder[T], 
                    creator: FactoryFunc[T]): FactoryBuilder[T] =
  ## Set default creator
  builder.factory.defaultCreator = creator
  builder

proc build*(builder: FactoryBuilder): auto =
  ## Build the configured factory
  builder.factory

# Factory methods
proc register*[T](factory: Factory[T], key: string, creator: FactoryFunc[T]) =
  ## Register a creator function
  factory.creators[key] = creator
  
  if not factory.logger.isNil:
    factory.logger.info(&"Registered creator for '{key}'")

proc create*[T](factory: Factory[T], key: string): Result[T, PatternError] =
  ## Create an object using registered creator
  let startTime = now()
  
  if not factory.logger.isNil:
    factory.logger.debug(&"Creating object with key '{key}'")
  
  if key notin factory.creators:
    if factory.defaultCreator.isNil:
      let error = newPatternError(factory.name, 
        &"No creator registered for key '{key}'")
      
      if not factory.logger.isNil:
        factory.logger.error(error.msg)
      
      return Result[T, PatternError].err(error)
    else:
      # Use default creator
      try:
        let obj = factory.defaultCreator()
        
        recordMetric(factory.metricsCollector, "timer", "factory.create.time", 
                     inMilliseconds(now() - startTime).float, @["default"])
        
        return Result[T, PatternError].ok(obj)
      except CatchableError as e:
        let error = newPatternError(factory.name, 
          &"Default creator failed: {e.msg}", "creation")
        return Result[T, PatternError].err(error)
  
  try:
    let obj = factory.creators[key]()
    
    # Record metrics
    recordMetric(factory.metricsCollector, "counter", "factory.created", 1.0, @[key])
    recordMetric(factory.metricsCollector, "timer", "factory.create.time", 
                 inMilliseconds(now() - startTime).float, @[key])
    
    # Update monitoring
    # TODO: Add monitoring integration when API is available
    
    if not factory.logger.isNil:
      factory.logger.info(&"Successfully created object with key '{key}'")
    
    Result[T, PatternError].ok(obj)
    
  except CatchableError as e:
    let error = newPatternError(factory.name, 
      &"Creator for key '{key}' failed: {e.msg}", "creation")
    
    if not factory.logger.isNil:
      factory.logger.error(error.msg)
    
    recordMetric(factory.metricsCollector, "counter", "factory.errors", 1.0, @[key])
    
    Result[T, PatternError].err(error)

proc createBatch*[T](factory: Factory[T], keys: seq[string]): seq[Result[T, PatternError]] =
  ## Create multiple objects
  result = newSeq[Result[T, PatternError]](keys.len)
  
  if not factory.logger.isNil:
    factory.logger.info(&"Creating batch of {keys.len} objects")
  
  for i, key in keys:
    result[i] = factory.create(key)

# Convenience templates
template factoryFor*(T: typedesc, body: untyped): Factory[T] =
  ## DSL for creating factories
  let factoryBuilder = newFactoryBuilder[T]()
  template register(key: string, creator: FactoryFunc[T]) =
    discard factoryBuilder.register(key, creator)
  body
  factoryBuilder.build()

# Example usage in macro
macro defineFactory*(name: untyped, T: typedesc, registrations: untyped): untyped =
  ## Macro for defining factories at compile time
  let nameStr = $name
  result = quote do:
    var `name` = newFactory[`T`](`nameStr`)
    `registrations`