## Integration with nim-libaspects for cross-cutting concerns

import std/[strformat, options, json, times]
import results
import nim_libaspects/[logging, monitoring, metrics, events, reporting]
import ../core/base
import ../creational/[factory, builder, singleton]
import ../structural/[adapter, decorator, proxy]
import ../behavioral/[observer, strategy, command]

# Factory integration
proc withAspects*[T](factory: Factory[T], logger: Logger, 
                     monitor: MonitoringSystem, 
                     metrics: MetricsRegistry): Factory[T] =
  ## Configure factory with all aspects
  factory.logger = logger
  factory.monitor = monitor  
  factory.metricsCollector = metrics
  factory

proc createWithEvent*[T](factory: Factory[T], key: string, 
                        eventBus: EventBus): Result[T, PatternError] =
  ## Create object and publish event
  let result = factory.create(key)
  
  if result.isOk:
    let event = newEvent(&"factory.created.{key}", %*{
      "factory": factory.name,
      "key": key,
      "type": $T
    })
    eventBus.publish(event)
  else:
    let event = newEvent(&"factory.failed.{key}", %*{
      "factory": factory.name,
      "key": key,
      "error": result.error.msg
    })
    eventBus.publish(event)
  
  result

# Builder integration  
proc buildWithReport*[T](builder: Builder[T], 
                        reporter: Reporter): Result[T, PatternError] =
  ## Build object and generate report
  let startTime = now()
  let result = builder.build()
  let duration = now() - startTime
  
  var report = newReport("BuilderReport")
  report.addSection("Summary", %*{
    "builder": builder.name,
    "type": $T,
    "duration": duration,
    "success": result.isOk
  })
  
  if result.isErr:
    report.addSection("Error", %*{
      "message": result.error.msg,
      "context": result.error.context
    })
  
  discard reporter.generate(report)
  result

# Observer integration with EventBus
type
  EventBusObserver* = ref object of Observer
    eventBus: EventBus
    pattern: string

proc newEventBusObserver*(eventBus: EventBus, pattern: string): EventBusObserver =
  EventBusObserver(
    eventBus: eventBus,
    pattern: pattern
  )

method update*(observer: EventBusObserver, subject: Subject) =
  ## Publish subject state changes to event bus
  let event = newEvent(observer.pattern, %*{
    "subject": subject.name,
    "state": subject.getState()
  })
  observer.eventBus.publish(event)

# Strategy pattern with configuration
proc createStrategyFromConfig*[T](config: Config, 
                                 section: string): Result[Strategy[T], PatternError] =
  ## Create strategy based on configuration
  let strategySection = config.getSection(section)
  if strategySection.isErr:
    return Result[Strategy[T], PatternError].err(
      newPatternError("Strategy", &"Config section '{section}' not found")
    )
  
  let cfg = strategySection.get()
  let strategyType = cfg.getString("type", "default")
  
  # This would map strategy types to implementations
  case strategyType:
  of "aggressive":
    Result[Strategy[T], PatternError].ok(createAggressiveStrategy[T]())
  of "conservative":  
    Result[Strategy[T], PatternError].ok(createConservativeStrategy[T]())
  else:
    Result[Strategy[T], PatternError].ok(createDefaultStrategy[T]())

# Command pattern with logging
type
  LoggedCommand* = ref object of Command
    command: Command
    logger: Logger

proc newLoggedCommand*(command: Command, logger: Logger): LoggedCommand =
  LoggedCommand(
    command: command,
    logger: logger
  )

method execute*(cmd: LoggedCommand) =
  cmd.logger.info(&"Executing command: {cmd.command.name}")
  let startTime = now()
  
  try:
    cmd.command.execute()
    let duration = now() - startTime
    cmd.logger.info(&"Command completed in {duration}ms")
  except CatchableError as e:
    cmd.logger.error(&"Command failed: {e.msg}")
    raise

method undo*(cmd: LoggedCommand) =
  cmd.logger.info(&"Undoing command: {cmd.command.name}")
  cmd.command.undo()

# Monitoring aspect for patterns
proc monitorPattern*[T: Pattern](pattern: T, monitor: MonitoringSystem): T =
  ## Add monitoring to any pattern
  monitor.addCheck(&"pattern.{pattern.name}", proc(): HealthCheckResult =
    HealthCheckResult(
      status: HealthStatus.Healthy,
      message: &"Pattern {pattern.name} is operational",
      metadata: %*{"type": $pattern.kind}
    )
  )
  pattern

# Metrics collection for patterns
proc collectMetrics*[T: Pattern](pattern: T, collector: MetricsRegistry): T =
  ## Add metrics collection to patterns
  collector.counter(&"pattern.{pattern.name}.usage")
  collector.gauge(&"pattern.{pattern.name}.instances")
  collector.histogram(&"pattern.{pattern.name}.performance")
  pattern

# Global pattern registry with aspects
var globalPatternRegistry* = newRegistry()
  .withLogging(newLogger("PatternRegistry"))
  .withMonitoring(newMonitoringSystem())
  .withMetrics(newMetricsRegistry())

proc registerPattern*(name: string, pattern: Pattern) =
  ## Register pattern with aspects
  globalPatternRegistry.register(name, pattern)
  if not globalPatternRegistry.logger.isNil:
    globalPatternRegistry.logger.info(&"Registered pattern: {name}")
  if not globalPatternRegistry.metricsCollector.isNil:
    let counter = globalPatternRegistry.metricsCollector.counter("patterns.registered", @[])
    counter.inc()

# Example integration setup
proc setupPatternsWithAspects*(): void =
  ## Initialize all patterns with cross-cutting concerns
  let logger = newLogger("Patterns")
  let monitor = newMonitoringSystem()
  let metrics = newMetricsRegistry()
  let eventBus = newEventBus()
  
  # Configure patterns
  let factory = newFactory[string]()
    .withAspects(logger, monitor, metrics)
  
  let builder = newBuilder[Config]()
    .withLogging(logger)
  
  let singleton = newSingleton("AppConfig", proc(): Config =
    newConfig()
  ).withLogging(logger).withMonitoring(monitor)
  
  # Register patterns
  registerPattern("StringFactory", factory)
  registerPattern("ConfigBuilder", builder)
  registerPattern("AppConfigSingleton", singleton)