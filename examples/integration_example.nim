## Integration example showing how to combine nim-design-patterns with nim-aspect-libs and nim-lang-core

import std/[strformat, strutils, json, tables, options]

# nim-aspect-libs imports
import nim_libaspects/[logging, metrics, monitoring, errors, events, config]

# nim-lang-core imports (for AST analysis)
import nim_core

# Design patterns
import nim_design_patterns/creational/[factory, builder, singleton]
import nim_design_patterns/structural/[adapter, decorator, proxy]
import nim_design_patterns/behavioral/[observer, strategy, command]
import nim_design_patterns/integration/[nim_libs_integration, nim_core_integration]

proc main() =
  echo "Design Patterns Integration Example"
  echo "==================================="
  
  # Set up cross-cutting concerns
  let logger = newLogger("DesignPatterns")
  logger.addHandler(newConsoleHandler())
  logger.setLevel(lvlInfo)
  
  let metrics = newMetricsRegistry()
  let monitor = newMonitoringSystem()
  let eventBus = newEventBus()
  let config = newConfig()

  # Subscribe to pattern-related events for monitoring
  discard eventBus.subscribe("pattern.*", proc(e: Event) =
    logger.info(&"Event received: {e.eventType}", %*{"data": e.data})
  )
  
  # Example 1: Factory Pattern with Logging and Metrics
  echo "\n--- Factory Pattern Example ---"
  
  # Define product types
  type
    Product = ref object of RootObj
      name*: string
    
    ConcreteProductA = ref object of Product
    ConcreteProductB = ref object of Product
  
  # Create factory with cross-cutting concerns
  let factory = newFactory[Product]("ProductFactory")
    .withLogging(logger)
    .withMetrics(metrics)
    .withMonitoring(monitor)
  
  # Register product creators
  factory.register("A", proc(): Product = ConcreteProductA(name: "Product A"))
  factory.register("B", proc(): Product = ConcreteProductB(name: "Product B"))
  
  # Create product using factory
  let productResult = factory.create("A")
  if productResult.isOk:
    let product = productResult.get()
    echo &"Created product: {product.name}"
  else:
    echo &"Factory error: {productResult.error.msg}"
  
  # Example 2: Observer Pattern with Event Bus
  echo "\n--- Observer Pattern Example ---"
  
  # Define custom data type
  type
    Temperature = ref object
      value*: float
  
  # Create subject 
  let subject = newSubject("WeatherStation")
    .withLogging(logger)
    .withEventBus(eventBus)
  
  # Create observers
  let temperatureObserver = observer("TemperatureObserver"):
    let temp = cast[Temperature](subject.getState())
    echo &"Temperature Observer: Current temperature is {temp.value}°C"
  
  let loggingObserver = newLoggingObserver("LoggingObserver", logger)
  let eventObserver = newEventObserver("EventObserver", eventBus)
  
  # Attach observers
  subject.attach(temperatureObserver)
        .attach(loggingObserver)
        .attach(eventObserver)
  
  # Update state to trigger notifications
  subject.setState(Temperature(value: 25.5))
  
  # Example 3: Strategy Pattern with Configuration
  echo "\n--- Strategy Pattern Example ---"
  
  # Define sorting strategies
  let ascendingStrategy = newStrategy[seq[int], seq[int]](
    "AscendingSort",
    proc(data: seq[int]): seq[int] =
      result = data
      sort(result)
  )
  
  let descendingStrategy = newStrategy[seq[int], seq[int]](
    "DescendingSort",
    proc(data: seq[int]): seq[int] =
      result = data
      sort(result, SortOrder.Descending)
  )
  
  # Create registry and register strategies
  let strategyRegistry = newStrategyRegistry[seq[int], seq[int]]()
  strategyRegistry.register(ascendingStrategy)
  strategyRegistry.register(descendingStrategy)
  
  # Create context with configuration from config
  # In a real app, this would be loaded from a file or env vars
  let sortConfig = %*{"sortStrategy": "AscendingSort"}
  let sortingContext = newContext[seq[int], seq[int]]("SortingContext")
    .withLogging(logger)
    .fromConfig(config, "sortStrategy", strategyRegistry)
    .setStrategy(ascendingStrategy)  # Default strategy
  
  # Use strategy
  let numbers = @[5, 2, 8, 1, 9]
  let sortedResult = sortingContext.execute(numbers)
  if sortedResult.isOk:
    echo &"Sorted numbers: {sortedResult.get()}"
  
  # Example 4: Command Pattern with Invoker
  echo "\n--- Command Pattern Example ---"
  
  # Create commands
  var output = ""
  
  let appendCommand = newSimpleCommand(
    "AppendHello",
    proc(): CommandResult =
      output &= "Hello "
      newCommandResult(nil, true, "", %*{"output": output})
    ,
    proc(): CommandResult =
      output = output[0 ..< output.len - 6]
      newCommandResult(nil, true, "", %*{"output": output})
  )
  
  let appendWorldCommand = newSimpleCommand(
    "AppendWorld",
    proc(): CommandResult =
      output &= "World!"
      newCommandResult(nil, true, "", %*{"output": output})
    ,
    proc(): CommandResult =
      output = output[0 ..< output.len - 6]
      newCommandResult(nil, true, "", %*{"output": output})
  )
  
  # Create invoker with cross-cutting concerns
  let invoker = newInvoker()
    .withLogging(logger)
    .withEventBus(eventBus)
    .withHistory()
    .withUndo()
  
  # Execute commands
  discard invoker.execute(appendCommand)
  discard invoker.execute(appendWorldCommand)
  
  echo &"After commands: '{output}'"
  
  # Undo last command
  discard invoker.undo()
  echo &"After undo: '{output}'"
  
  # Example 5: Decorator Pattern with Metrics
  echo "\n--- Decorator Pattern Example ---"
  
  # Component interface and concrete implementation
  type
    DataProcessor = ref object of RootObj
    
    SimpleProcessor = ref object of DataProcessor
  
  proc process(processor: DataProcessor, data: string): string {.base.} =
    raise newException(CatchableError, "Abstract method")
  
  proc process(processor: SimpleProcessor, data: string): string =
    result = data.toUpperCase()
  
  # Create base component
  let processor = SimpleProcessor()
  
  # Create decorated component with metrics
  let decoratedProcessor = newDecorator[DataProcessor](
    processor,
    proc(self: DataProcessor): string =
      let data = "hello world"
      let startTime = now()
      let result = process(self, data)
      let duration = now() - startTime
      
      metrics.recordTime("processor.duration", duration)
      metrics.increment("processor.calls")
      
      logger.info(&"Processed data in {duration}ms")
      result
  )
  
  # Execute with decorator
  let processedData = decoratedProcessor.execute()
  echo &"Decorated result: {processedData}"
  
  # Example 6: Integration with nim-lang-core AST analysis
  echo "\n--- AST Analysis Integration Example ---"
  
  # Note: In a real application, you would use nim_core to parse actual Nim files
  # and analyze their AST. This is a simplified demonstration.
  
  # Create analyzer components
  let context = AstContext(path: "example.nim")
  let typeAnalyzer = newTypeAnalyzer()
  var symbolIndex = newSymbolIndex()
  
  # In real usage, you would:
  # 1. Parse Nim source files to get AST
  # 2. Use the pattern detector to analyze the AST
  # 3. Apply transformations or generate reports
  
  echo "AST Analysis components initialized:"
  echo "  - AstContext for: example.nim"
  echo "  - TypeAnalyzer ready"
  echo "  - SymbolIndex ready"
  echo "  - Pattern detection available"
  
  # Print metrics and monitoring summary
  echo "\n--- Telemetry Summary ---"
  echo "Metrics collected:"
  for metric in metrics.getMetrics():
    echo &"  - {metric.name}: {metric.value}"
  
  echo "\nMonitoring checks:"
  for check in monitor.getChecks():
    echo &"  - {check.name}: {check.lastStatus}"
  
  echo "\nEvents published:"
  echo &"  - Total events: {eventBus.getStats().eventsPublished}"

when isMainModule:
  main()