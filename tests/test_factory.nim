## Test suite for Factory pattern

import std/[unittest, strformat, strutils]
import nim_libaspects/[errors, logging, metrics, monitoring]
import nim_design_patterns/creational/factory

# Note: recordMetric is tested indirectly through factory's public API

type
  # Test products
  Product = ref object of RootObj
    name*: string
  
  ConcreteProductA = ref object of Product
  ConcreteProductB = ref object of Product
  
  # Custom error for testing
  CustomError = ref object of CatchableError

# Exception-throwing creator for testing error handling
proc errorCreator(): Product =
  raise CustomError(msg: "Creator failed")

suite "Factory Pattern Tests":
  setup:
    # Create fresh factory for each test
    let factory = newFactory[Product]("TestFactory")
    
    # Register product creators
    factory.register("A", proc(): Product = ConcreteProductA(name: "Product A"))
    factory.register("B", proc(): Product = ConcreteProductB(name: "Product B"))
  
  test "Factory creates product by key":
    # When creating a registered product
    let result = factory.create("A")
    
    # Then it succeeds
    check result.isOk()
    
    # And returns the expected product
    let product = result.get()
    check product.name == "Product A"
    check product of ConcreteProductA
  
  test "Factory returns error for unknown key":
    # When creating an unregistered product
    let result = factory.create("C")
    
    # Then it fails
    check result.isErr()
    
    # And error message contains the key
    check "C" in result.error.msg
  
  test "Factory uses default creator when available":
    # Given a factory with default creator
    let defaultFactory = newFactoryBuilder[Product]("DefaultFactory")
      .setDefault(proc(): Product = ConcreteProductA(name: "Default Product"))
      .build()
    
    # When creating with unknown key
    let result = defaultFactory.create("unknown")
    
    # Then it uses the default creator
    check result.isOk()
    check result.get().name == "Default Product"
  
  test "Factory returns error when creator throws exception":
    # Given a factory with error-throwing creator
    factory.register("Error", errorCreator)
    
    # When creating product
    let result = factory.create("Error")
    
    # Then it returns error
    check result.isErr()
    check "Creator for key 'Error' failed" in result.error.msg
  
  test "Factory with logging passes log messages":
    # Given a factory with logging
    let mockLogger = newLogger("MockLogger")
    mockLogger.addHandler(newConsoleHandler())
    
    let loggingFactory = newFactoryBuilder[Product]("LoggingFactory")
      .withLogging(mockLogger)
      .register("A", proc(): Product = ConcreteProductA(name: "Product A"))
      .build()
    
    # When creating product
    let result = loggingFactory.create("A")
    
    # Then operation succeeds (logging doesn't interfere)
    check result.isOk()
  
  test "Factory DSL creates usable factory":
    # Given a factory created with DSL
    let dslFactory = factoryFor(Product):
      register("A", proc(): Product = ConcreteProductA(name: "DSL Product"))
    
    # When creating product
    let result = dslFactory.create("A")
    
    # Then it works as expected
    check result.isOk()
    check result.get().name == "DSL Product"
  
  test "Factory creates batch of products":
    # When creating multiple products
    let results = factory.createBatch(@["A", "B", "Unknown"])
    
    # Then returns expected results
    check results.len == 3
    check results[0].isOk()
    check results[1].isOk()
    check results[2].isErr()
    
    # And products have correct types
    check results[0].get() of ConcreteProductA
    check results[1].get() of ConcreteProductB

suite "Factory Builder Tests":
  test "Builder creates factory with logging":
    # Given a factory builder
    let builder = newFactoryBuilder[Product]("BuilderFactory")
    
    # When building with configuration
    let factory = builder
      .withLogging(newLogger("TestLogger"))
      .register("A", proc(): Product = ConcreteProductA(name: "Product A"))
      .build()
    
    # Then factory works as expected
    let result = factory.create("A")
    check result.isOk()
    check result.get().name == "Product A"
  
  test "Builder sets default creator":
    # Given a builder with default creator
    let builder = newFactoryBuilder[Product]()
      .setDefault(proc(): Product = ConcreteProductA(name: "Default"))
    
    # When building and creating with unknown key
    let factory = builder.build()
    let result = factory.create("Unknown")
    
    # Then it uses default creator
    check result.isOk()
    check result.get().name == "Default"

suite "Factory Metrics and Monitoring Tests":
  test "Factory records metrics when collector is provided":
    # Given a factory with metrics
    let metrics = newMetricsRegistry()
    let factory = newFactoryBuilder[Product]("MetricsFactory")
      .withMetrics(metrics)
      .register("A", proc(): Product = ConcreteProductA(name: "Product A"))
      .build()
    
    # When creating products
    discard factory.create("A")
    discard factory.create("A")
    
    # Then metrics are recorded
    let counter = metrics.counter("factory.created", @["key"])
    check counter.value(@["A"]) == 2.0
    
    # And timer metrics exist
    let gauge = metrics.gauge("factory.create.time_duration_ms", @["key"])
    check gauge.value(@["A"]) >= 0.0
  
  test "Factory records error metrics on failure":
    # Given a factory with metrics
    let metrics = newMetricsRegistry()
    let factory = newFactoryBuilder[Product]("MetricsFactory")
      .withMetrics(metrics)
      .register("Error", errorCreator)
      .build()
    
    # When creation fails
    discard factory.create("Error")
    
    # Then error metrics are recorded
    let counter = metrics.counter("factory.errors", @["key"])
    check counter.value(@["Error"]) == 1.0
  
  test "Factory with monitoring configured":
    # Given a factory with monitoring
    let monitor = newMonitoringSystem()
    let factory = newFactoryBuilder[Product]("MonitoringFactory")
      .withMonitoring(monitor)
      .register("A", proc(): Product = ConcreteProductA(name: "Product A"))
      .build()
    
    # When creating product
    let result = factory.create("A")
    
    # Then creation succeeds
    check result.isOk()
  
  test "Factory records metrics for default creator":
    # Given a factory with metrics and default creator
    let metrics = newMetricsRegistry()
    let factory = newFactoryBuilder[Product]("DefaultMetricsFactory")
      .withMetrics(metrics)
      .setDefault(proc(): Product = ConcreteProductA(name: "Default"))
      .build()
    
    # When creating with unknown key
    discard factory.create("unknown")
    
    # Then metrics are recorded for default
    let gauge = metrics.gauge("factory.create.time_duration_ms", @["key"])
    check gauge.value(@["default"]) >= 0.0
  
  test "Default creator error is handled properly":
    # Given a factory with error-throwing default creator
    let factory = newFactoryBuilder[Product]("ErrorDefaultFactory")
      .setDefault(errorCreator)
      .build()
    
    # When creating with unknown key
    let result = factory.create("unknown")
    
    # Then it returns error
    check result.isErr()
    check "Default creator failed" in result.error.msg

suite "Factory Edge Cases":
  test "Factory with all aspects configured":
    # Given a factory with all cross-cutting concerns
    let logger = newLogger("FullLogger")
    logger.addHandler(newConsoleHandler())
    let metrics = newMetricsRegistry()
    let monitor = newMonitoringSystem()
    
    let factory = newFactoryBuilder[Product]("FullFactory")
      .withLogging(logger)
      .withMetrics(metrics)
      .withMonitoring(monitor)
      .register("A", proc(): Product = ConcreteProductA(name: "Product A"))
      .build()
    
    # When creating product
    let result = factory.create("A")
    
    # Then all aspects work together
    check result.isOk()
    check metrics.counter("factory.created", @["key"]).value(@["A"]) == 1.0
  
  test "Factory handles empty batch creation":
    # Given a factory
    let factory = newFactory[Product]("EmptyBatchFactory")
    
    # When creating empty batch
    let results = factory.createBatch(@[])
    
    # Then returns empty results
    check results.len == 0
  
  test "Factory register logs when logger is available":
    # Given a factory with logger
    let logger = newLogger("RegisterLogger")
    logger.addHandler(newConsoleHandler())
    
    let factory = newFactoryBuilder[Product]("LogRegisterFactory")
      .withLogging(logger)
      .build()
    
    # When registering creator
    factory.register("A", proc(): Product = ConcreteProductA(name: "Product A"))
    
    # Then registration is logged
    # (Logger output happens, we just verify no errors)
    let result = factory.create("A")
    check result.isOk()
  
  test "Factory handles nil metrics gracefully":
    # Given a factory without metrics
    let factory = newFactory[Product]("NoMetricsFactory")
    factory.register("A", proc(): Product = ConcreteProductA(name: "Product A"))
    
    # When creating product (no metrics configured)
    let result = factory.create("A")
    
    # Then operation succeeds without metrics
    check result.isOk()
  
  test "Multiple products with same key":
    # Given a factory
    let factory = newFactory[Product]("OverwriteFactory")
    
    # When registering multiple creators with same key
    factory.register("A", proc(): Product = ConcreteProductA(name: "First A"))
    factory.register("A", proc(): Product = ConcreteProductA(name: "Second A"))
    
    # Then latest registration wins
    let result = factory.create("A")
    check result.isOk()
    check result.get().name == "Second A"

suite "Factory Macro Tests":
  test "DefineFactory macro creates working factory":
    # Use the macro to define a factory
    defineFactory(macroFactory, Product):
      macroFactory.register("A", proc(): Product = ConcreteProductA(name: "Macro Product"))
    
    # When using the factory
    let result = macroFactory.create("A")
    
    # Then it works as expected
    check result.isOk()
    check result.get().name == "Macro Product"

when isMainModule:
  discard