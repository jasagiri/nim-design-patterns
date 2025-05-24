## Base types and interfaces for design patterns

import std/[macros, strformat, tables, logging]
import nim_libaspects/[logging as aspectsLogging, monitoring, metrics]

type
  PatternKind* = enum
    pkCreational = "Creational"
    pkStructural = "Structural"
    pkBehavioral = "Behavioral"
    pkFunctional = "Functional"
  
  Pattern* = ref object of RootObj
    ## Base type for all patterns
    name*: string
    kind*: PatternKind
    description*: string
  
  PatternError* = ref object of CatchableError
    ## Error type for pattern-related issues
    pattern*: string
    context*: string
  
  PatternRegistry* = ref object
    ## Registry for pattern instances
    patterns: Table[string, Pattern]
    factories: Table[string, proc(): Pattern]
    logger*: aspectsLogging.Logger
    monitor*: MonitoringSystem
    metricsCollector*: MetricsRegistry

# Initialize logger
let logger = newConsoleLogger()

proc newPatternError*(pattern, msg: string, context = ""): PatternError =
  ## Create a new pattern error
  result = PatternError(
    msg: &"[{pattern}] {msg}",
    pattern: pattern,
    context: context
  )

type PatternResult*[T] = object
  ## Simple result type for pattern operations
  case isSuccess*: bool
  of true:
    value*: T
  of false:
    error*: PatternError

proc ok*[T](result_type: typedesc[PatternResult[T]], value: T): PatternResult[T] =
  PatternResult[T](isSuccess: true, value: value)

proc err*[T](result_type: typedesc[PatternResult[T]], error: PatternError): PatternResult[T] =
  PatternResult[T](isSuccess: false, error: error)

proc newRegistry*(): PatternRegistry =
  ## Create a new pattern registry
  PatternRegistry(
    patterns: initTable[string, Pattern](),
    factories: initTable[string, proc(): Pattern]()
  )

proc withLogging*(registry: PatternRegistry, logger: aspectsLogging.Logger): PatternRegistry =
  ## Add logging to registry
  registry.logger = logger
  registry

proc withMonitoring*(registry: PatternRegistry, monitor: MonitoringSystem): PatternRegistry =
  ## Add monitoring to registry
  registry.monitor = monitor
  registry

proc withMetrics*(registry: PatternRegistry, metricsCollector: MetricsRegistry): PatternRegistry =
  ## Add metrics collection to registry
  registry.metricsCollector = metricsCollector
  registry

proc register*[T: Pattern](registry: PatternRegistry, name: string, 
                          factory: proc(): T) =
  ## Register a pattern factory
  registry.factories[name] = proc(): Pattern = factory()

proc create*(registry: PatternRegistry, name: string): PatternResult[Pattern] =
  ## Create a pattern instance from registry
  if name notin registry.factories:
    return PatternResult[Pattern].err(
      newPatternError(name, "Pattern not registered")
    )
  
  try:
    let pattern = registry.factories[name]()
    registry.patterns[name] = pattern
    PatternResult[Pattern].ok(pattern)
  except CatchableError as e:
    PatternResult[Pattern].err(
      newPatternError(name, e.msg, "Failed to create pattern")
    )

proc get*(registry: PatternRegistry, name: string): PatternResult[Pattern] =
  ## Get an existing pattern instance
  if name in registry.patterns:
    PatternResult[Pattern].ok(registry.patterns[name])
  else:
    PatternResult[Pattern].err(
      newPatternError(name, "Pattern instance not found")
    )

# Logging integration
proc logPattern*(pattern: Pattern, msg: string) =
  ## Log pattern activity  
  logger.log(lvlDebug, &"[{pattern.kind}:{pattern.name}] {msg}")

template withLogging*(patternExpr: typed, body: untyped): untyped =
  ## Add logging to pattern operations
  let pattern = patternExpr
  pattern.logPattern("Starting operation")
  try:
    body
  finally:
    pattern.logPattern("Operation completed")

# Macro for pattern definition
macro definePattern*(name: untyped, kind: PatternKind, 
                    description: string, body: untyped): untyped =
  ## Define a new pattern type
  let typeName = name.strVal & "Pattern"
  let initName = ident("init" & name.strVal)
  
  result = quote do:
    type
      `name`* = ref object of Pattern
        # Add fields from body
    
    proc `initName`*(self: `name`) =
      self.name = `name.strVal`
      self.kind = `kind`
      self.description = `description`
    
    `body`

# Pattern application helpers
proc applyPattern*[T](target: T, pattern: Pattern): PatternResult[T] =
  ## Apply a pattern to a target object
  # This is overridden by specific pattern implementations
  PatternResult[T].err(
    newPatternError(pattern.name, "Pattern application not implemented")
  )