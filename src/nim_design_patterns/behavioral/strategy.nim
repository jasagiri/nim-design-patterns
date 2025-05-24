## Strategy Pattern implementation

import std/[tables, strformat, options, times]
import results
import nim_libaspects/[logging, config, metrics]
import ../core/base

type
  StrategyFunc*[T, R] = proc(data: T): R
  
  Strategy*[T, R] = ref object of Pattern
    ## Generic strategy implementation
    execute*: StrategyFunc[T, R]
  
  Context*[T, R] = ref object of Pattern
    ## Context that uses strategies
    strategy: Strategy[T, R]
    fallbackStrategy: Strategy[T, R]
    logger: Logger
    config: Config
    metrics: MetricsRegistry
  
  StrategyRegistry*[T, R] = ref object
    ## Registry for multiple strategies
    strategies: Table[string, Strategy[T, R]]

proc newStrategy*[T, R](name: string, 
                       execute: StrategyFunc[T, R],
                       description = ""): Strategy[T, R] =
  ## Create a new strategy
  result = Strategy[T, R](
    name: name,
    kind: pkBehavioral,
    description: if description.len > 0: description else: &"Strategy for {$T} -> {$R}",
    execute: execute
  )

proc execute*[T, R](strategy: Strategy[T, R], data: T): R =
  ## Execute strategy directly
  strategy.execute(data)

# Context 
proc newContext*[T, R](name = "Context"): Context[T, R] =
  ## Create a new context
  result = Context[T, R](
    name: name,
    kind: pkBehavioral, 
    description: &"Strategy pattern context for {$T} -> {$R}"
  )

proc withLogging*[T, R](context: Context[T, R], 
                       logger: Logger): Context[T, R] =
  ## Add logging to context
  context.logger = logger
  context

proc withConfig*[T, R](context: Context[T, R], 
                      config: Config): Context[T, R] =
  ## Add configuration to context
  context.config = config
  context

proc withMetrics*[T, R](context: Context[T, R],
                       metrics: MetricsRegistry): Context[T, R] =
  ## Add metrics to context
  context.metrics = metrics
  context

proc setStrategy*[T, R](context: Context[T, R], 
                       strategy: Strategy[T, R]): Context[T, R] =
  ## Set the current strategy
  context.strategy = strategy
  
  if not context.logger.isNil:
    context.logger.info(&"Strategy set to '{strategy.name}'")
  
  context

proc setFallbackStrategy*[T, R](context: Context[T, R],
                              strategy: Strategy[T, R]): Context[T, R] =
  ## Set fallback strategy
  context.fallbackStrategy = strategy
  
  if not context.logger.isNil:
    context.logger.info(&"Fallback strategy set to '{strategy.name}'")
  
  context

proc fromConfig*[T, R](context: Context[T, R],
                      config: Config,
                      key: string,
                      registry: StrategyRegistry[T, R]): Context[T, R] =
  ## Set strategy from configuration
  if config.isNil:
    if not context.logger.isNil:
      context.logger.error("Cannot load strategy from nil config")
    return context
  
  let strategyName = config.getString(key, "")
  if strategyName.len == 0:
    if not context.logger.isNil:
      context.logger.warn(&"No strategy name found at config key '{key}'")
    return context
  
  if strategyName notin registry.strategies:
    if not context.logger.isNil:
      context.logger.error(&"Strategy '{strategyName}' not found in registry")
    return context
  
  let strategy = registry.strategies[strategyName]
  context.setStrategy(strategy)

proc execute*[T, R](context: Context[T, R], data: T): Result[R, PatternError] =
  ## Execute current strategy
  if context.strategy.isNil:
    if context.fallbackStrategy.isNil:
      return Result[R, PatternError].err(
        newPatternError(context.name, "No strategy set and no fallback available")
      )
    else:
      if not context.logger.isNil:
        context.logger.warn("Using fallback strategy")
      
      try:
        let startTime = now()
        let result = context.fallbackStrategy.execute(data)
        
        if not context.metrics.isNil:
          let duration = now() - startTime
          let timer = context.metrics.gauge("strategy.fallback.execution_ms", @["strategy"])
          timer.set(duration.inMilliseconds.float, @[context.fallbackStrategy.name])
          let counter = context.metrics.counter("strategy.fallback.used", @["strategy"])
          counter.inc(@[context.fallbackStrategy.name])
        
        return Result[R, PatternError].ok(result)
      except CatchableError as e:
        return Result[R, PatternError].err(
          newPatternError(context.name, &"Fallback strategy failed: {e.msg}")
        )
  
  try:
    if not context.logger.isNil:
      context.logger.debug(&"Executing strategy '{context.strategy.name}'")
    
    let startTime = now()
    let result = context.strategy.execute(data)
    
    if not context.metrics.isNil:
      let duration = now() - startTime
      let timer = context.metrics.gauge(
        &"strategy.{context.strategy.name}.execution_ms", @["strategy"])
      timer.set(duration.inMilliseconds.float, @[context.strategy.name])
      let counter = context.metrics.counter(
        &"strategy.{context.strategy.name}.used", @["strategy"])
      counter.inc(@[context.strategy.name])
    
    if not context.logger.isNil:
      context.logger.info(&"Strategy '{context.strategy.name}' executed successfully")
    
    Result[R, PatternError].ok(result)
    
  except CatchableError as e:
    if not context.logger.isNil:
      context.logger.error(&"Strategy execution failed: {e.msg}")
    
    if not context.metrics.isNil:
      let counter = context.metrics.counter(
        &"strategy.{context.strategy.name}.error", @["strategy"])
      counter.inc(@[context.strategy.name])
    
    Result[R, PatternError].err(
      newPatternError(context.name, &"Strategy execution failed: {e.msg}")
    )

# Strategy registry
proc newStrategyRegistry*[T, R](): StrategyRegistry[T, R] =
  ## Create a new strategy registry
  StrategyRegistry[T, R](strategies: initTable[string, Strategy[T, R]]())

proc register*[T, R](registry: StrategyRegistry[T, R],
                   strategy: Strategy[T, R]): StrategyRegistry[T, R] =
  ## Register a strategy
  registry.strategies[strategy.name] = strategy
  registry

proc get*[T, R](registry: StrategyRegistry[T, R],
               name: string): Option[Strategy[T, R]] =
  ## Get a strategy by name
  if name in registry.strategies:
    some(registry.strategies[name])
  else:
    none(Strategy[T, R])

# Strategy family
type
  StrategyFamily*[T, R] = ref object of Pattern
    ## Collection of related strategies
    strategies: Table[string, Strategy[T, R]]
    defaultStrategy: string
    logger: Logger

proc newStrategyFamily*[T, R](name: string): StrategyFamily[T, R] =
  ## Create a new strategy family
  result = StrategyFamily[T, R](
    name: name,
    kind: pkBehavioral,
    description: &"Strategy family for {$T} -> {$R}",
    strategies: initTable[string, Strategy[T, R]](),
    defaultStrategy: ""
  )

proc withLogging*[T, R](family: StrategyFamily[T, R],
                       logger: Logger): StrategyFamily[T, R] =
  ## Add logging to strategy family
  family.logger = logger
  family

proc add*[T, R](family: StrategyFamily[T, R],
               strategy: Strategy[T, R],
               isDefault = false): StrategyFamily[T, R] =
  ## Add strategy to family
  family.strategies[strategy.name] = strategy
  
  if isDefault:
    family.defaultStrategy = strategy.name
    
    if not family.logger.isNil:
      family.logger.info(&"Set '{strategy.name}' as default strategy")
  
  if not family.logger.isNil:
    family.logger.debug(&"Added strategy '{strategy.name}' to family '{family.name}'")
  
  family

proc get*[T, R](family: StrategyFamily[T, R],
               name: string): Option[Strategy[T, R]] =
  ## Get strategy from family
  if name in family.strategies:
    some(family.strategies[name])
  elif family.defaultStrategy.len > 0:
    some(family.strategies[family.defaultStrategy])
  else:
    none(Strategy[T, R])

proc getDefault*[T, R](family: StrategyFamily[T, R]): Option[Strategy[T, R]] =
  ## Get default strategy
  if family.defaultStrategy.len > 0:
    some(family.strategies[family.defaultStrategy])
  else:
    none(Strategy[T, R])

# Helper templates
template createStrategy*[T, R](name: string, body: untyped): Strategy[T, R] =
  ## Create strategy with inline implementation
  newStrategy[T, R](name, proc(data: T): R = body)

template withStrategy*[T, R](context: Context[T, R], 
                          tempStrategy: Strategy[T, R], 
                          data: T, 
                          body: untyped): untyped =
  ## Execute with temporary strategy
  let oldStrategy = context.strategy
  discard context.setStrategy(tempStrategy)
  
  try:
    let result = context.execute(data)
    body
  finally:
    discard context.setStrategy(oldStrategy)

# Conditional strategies
proc createConditionalStrategy*[T, R](
    name: string,
    condition: proc(data: T): bool,
    trueStrategy: Strategy[T, R],
    falseStrategy: Strategy[T, R]): Strategy[T, R] =
  ## Create strategy that chooses between two strategies
  result = newStrategy[T, R](
    name,
    proc(data: T): R =
      if condition(data):
        trueStrategy.execute(data)
      else:
        falseStrategy.execute(data)
  )

# Common strategy implementations
proc createDefaultStrategy*[T, R](defaultValue: R): Strategy[T, R] =
  ## Create strategy that returns default value
  newStrategy[T, R](
    "DefaultStrategy", 
    proc(data: T): R = defaultValue,
    "Returns a default value regardless of input"
  )

proc createCachingStrategy*[T, R](
    baseStrategy: Strategy[T, R]): Strategy[T, R] =
  ## Create caching wrapper for strategy
  var cache = initTable[T, R]()
  
  result = newStrategy[T, R](
    &"Caching{baseStrategy.name}",
    proc(data: T): R =
      if data in cache:
        return cache[data]
      
      let result = baseStrategy.execute(data)
      cache[data] = result
      result
    ,
    &"Caching wrapper for {baseStrategy.name}"
  )