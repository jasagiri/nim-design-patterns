## Circuit Breaker Pattern implementation
##
## The Circuit Breaker pattern prevents cascading failures in distributed systems
## by "breaking the circuit" when a dependent service fails, allowing the system 
## to fail fast and recover when the dependency becomes available again.
##
## This implementation provides:
## - Three states: Closed (normal operation), Open (failing fast), Half-Open (testing recovery)
## - Configurable failure thresholds, retry intervals, and timeout windows
## - Fallback mechanisms for when the circuit is open
## - Detailed metrics, logging, and event publishing
## - Thread-safe operations with built-in locking
## - Customizable health checks for service dependencies

import std/[tables, sets, strformat, options, times, locks, atomics]
import nim_libaspects/[logging, metrics, errors, events]
import ../core/base

type
  CircuitState* = enum
    csrClosed   # Normal operation, requests pass through
    csrOpen     # Circuit is open, requests fail fast
    csrHalfOpen # Testing if the service is back online
  
  CircuitStatistics* = object
    ## Statistics for circuit breaker operations
    totalCalls*: int
    successfulCalls*: int
    failedCalls*: int
    rejectedCalls*: int
    lastFailureTime*: DateTime
    lastSuccessTime*: DateTime
    currentState*: CircuitState
    openCircuitCount*: int
    
  CircuitBreakerConfig* = object
    ## Configuration for circuit breaker behavior
    failureThreshold*: int       # Number of failures before opening circuit
    resetTimeout*: Duration      # Time before half-open state (recovery attempt)
    successThreshold*: int       # Consecutive successes needed to close circuit
    timeout*: Duration           # Timeout for monitored operations
    monitorInterval*: Duration   # Interval for health check monitoring
    
  CircuitResult*[T] = object
    ## Result of a circuit-protected operation
    success*: bool
    value*: Option[T]
    error*: Option[ref CatchableError]
    circuitState*: CircuitState
    operationTime*: Duration
    
  ServiceOperation*[T] = proc(): Result[T, ref CatchableError]
  FallbackOperation*[T] = proc(): Result[T, ref CatchableError]
  HealthCheck* = proc(): bool
  
  CircuitBreaker*[T] = ref object of Pattern
    ## Circuit breaker implementation
    name*: string
    config*: CircuitBreakerConfig
    state*: Atomic[CircuitState]
    failureCount*: Atomic[int]
    successCount*: Atomic[int]
    lastError*: ref CatchableError
    lastStateChange*: DateTime
    statistics*: CircuitStatistics
    
    fallback*: Option[FallbackOperation[T]]
    healthCheck*: Option[HealthCheck]
    
    lock*: Lock
    logger*: Logger
    metrics*: MetricsRegistry
    eventBus*: EventBus
  
  CircuitOpenError* = object of CatchableError
    ## Error when circuit is open
    serviceName*: string
    openSince*: DateTime

# Default configuration
proc defaultConfig*(): CircuitBreakerConfig =
  ## Create a default configuration for circuit breaker
  CircuitBreakerConfig(
    failureThreshold: 3,            # Open after 3 failures
    resetTimeout: initDuration(seconds = 30),   # Wait 30 seconds before recovery attempt
    successThreshold: 2,            # Close after 2 consecutive successes
    timeout: initDuration(seconds = 5),         # 5 second timeout for operations
    monitorInterval: initDuration(seconds = 15) # Check health every 15 seconds
  )

# Circuit Breaker implementation
proc newCircuitBreaker*[T](name: string, config = defaultConfig()): CircuitBreaker[T] =
  ## Create a new circuit breaker
  result = CircuitBreaker[T](
    name: name,
    kind: pkBehavioral,
    description: "Circuit Breaker pattern",
    config: config,
    state: Atomic[CircuitState](csrClosed.int),
    failureCount: Atomic[int](0),
    successCount: Atomic[int](0),
    lastStateChange: now(),
    statistics: CircuitStatistics(
      currentState: csrClosed,
      lastSuccessTime: now(),
      lastFailureTime: now()
    )
  )
  
  initLock(result.lock)

proc withLogging*[T](breaker: CircuitBreaker[T], logger: Logger): CircuitBreaker[T] =
  ## Add logging to circuit breaker
  result = breaker
  result.logger = logger

proc withMetrics*[T](breaker: CircuitBreaker[T], metrics: MetricsRegistry): CircuitBreaker[T] =
  ## Add metrics collection to circuit breaker
  result = breaker
  result.metrics = metrics

proc withEventBus*[T](breaker: CircuitBreaker[T], eventBus: EventBus): CircuitBreaker[T] =
  ## Add event bus to circuit breaker
  result = breaker
  result.eventBus = eventBus

proc withFallback*[T](breaker: CircuitBreaker[T], 
                     fallback: FallbackOperation[T]): CircuitBreaker[T] =
  ## Add fallback operation for when circuit is open
  result = breaker
  result.fallback = some(fallback)

proc withHealthCheck*[T](breaker: CircuitBreaker[T], 
                        healthCheck: HealthCheck): CircuitBreaker[T] =
  ## Add health check for dependency monitoring
  result = breaker
  result.healthCheck = some(healthCheck)

proc getState*[T](breaker: CircuitBreaker[T]): CircuitState =
  ## Get current circuit state
  CircuitState(breaker.state.load(moRelaxed))

proc setState*[T](breaker: CircuitBreaker[T], state: CircuitState) =
  ## Set circuit state with logging and events
  let oldState = breaker.getState()
  
  if oldState != state:
    # Update state
    breaker.state.store(state.int, moRelease)
    breaker.lastStateChange = now()
    
    # Update statistics
    withLock(breaker.lock):
      breaker.statistics.currentState = state
      if state == csrOpen:
        inc breaker.statistics.openCircuitCount
    
    # Log state change
    if not breaker.logger.isNil:
      breaker.logger.info(&"Circuit '{breaker.name}' changed from {oldState} to {state}")
    
    # Publish event
    if not breaker.eventBus.isNil:
      breaker.eventBus.publish(newEvent("circuit.state_changed", %*{
        "circuit": breaker.name,
        "oldState": $oldState,
        "newState": $state,
        "timestamp": $now()
      }))
    
    # Record metric
    if not breaker.metrics.isNil:
      breaker.metrics.gauge(&"circuit.{breaker.name}.state", state.ord.float)
      breaker.metrics.increment(&"circuit.{breaker.name}.state_changes")

proc recordSuccess*[T](breaker: CircuitBreaker[T]) =
  ## Record a successful operation
  withLock(breaker.lock):
    inc breaker.statistics.totalCalls
    inc breaker.statistics.successfulCalls
    breaker.statistics.lastSuccessTime = now()
  
  # Update metrics
  if not breaker.metrics.isNil:
    breaker.metrics.increment(&"circuit.{breaker.name}.success")
  
  let state = breaker.getState()
  
  case state:
  of csrClosed:
    # Already closed, reset failure count
    breaker.failureCount.store(0, moRelaxed)
    
  of csrHalfOpen:
    # In half-open state, increment success count
    let newSuccessCount = breaker.successCount.fetchAdd(1, moRelaxed) + 1
    
    # If we've reached the success threshold, close the circuit
    if newSuccessCount >= breaker.config.successThreshold:
      breaker.setState(csrClosed)
      breaker.successCount.store(0, moRelaxed)
      breaker.failureCount.store(0, moRelaxed)
  
  of csrOpen:
    # This shouldn't happen normally, but handle anyway
    discard

proc recordFailure*[T](breaker: CircuitBreaker[T], error: ref CatchableError) =
  ## Record a failed operation
  withLock(breaker.lock):
    inc breaker.statistics.totalCalls
    inc breaker.statistics.failedCalls
    breaker.statistics.lastFailureTime = now()
    breaker.lastError = error
  
  # Update metrics
  if not breaker.metrics.isNil:
    breaker.metrics.increment(&"circuit.{breaker.name}.failure")
  
  let state = breaker.getState()
  
  case state:
  of csrClosed:
    # In closed state, increment failure count
    let newFailureCount = breaker.failureCount.fetchAdd(1, moRelaxed) + 1
    
    # If we've reached the failure threshold, open the circuit
    if newFailureCount >= breaker.config.failureThreshold:
      breaker.setState(csrOpen)
      
      # Log details about what caused the circuit to open
      if not breaker.logger.isNil:
        breaker.logger.error(&"Circuit '{breaker.name}' opened due to: {error.msg}")
  
  of csrHalfOpen:
    # In half-open state, any failure opens the circuit again
    breaker.setState(csrOpen)
    breaker.successCount.store(0, moRelaxed)
    
    if not breaker.logger.isNil:
      breaker.logger.warn(&"Circuit '{breaker.name}' reopened during recovery test: {error.msg}")
  
  of csrOpen:
    # Already open, just update metrics
    if not breaker.metrics.isNil:
      breaker.metrics.increment(&"circuit.{breaker.name}.rejected")

proc isCircuitOpenDurationExceeded*[T](breaker: CircuitBreaker[T]): bool =
  ## Check if we've waited long enough since circuit opened
  let now = now()
  let timeSinceStateChange = now - breaker.lastStateChange
  timeSinceStateChange > breaker.config.resetTimeout

proc checkState*[T](breaker: CircuitBreaker[T]) =
  ## Check if half-open state should be entered
  let state = breaker.getState()
  
  if state == csrOpen and breaker.isCircuitOpenDurationExceeded():
    # Transition to half-open to test the service
    breaker.setState(csrHalfOpen)
    
    # Reset counters
    breaker.successCount.store(0, moRelaxed)
    
    if not breaker.logger.isNil:
      breaker.logger.info(&"Circuit '{breaker.name}' is half-open, testing recovery")

proc execute*[T](breaker: CircuitBreaker[T], 
                operation: ServiceOperation[T]): CircuitResult[T] =
  ## Execute an operation with circuit breaker protection
  var result = CircuitResult[T](
    success: false,
    circuitState: breaker.getState()
  )
  
  # Check state before executing
  breaker.checkState()
  
  # Get current state
  let state = breaker.getState()
  result.circuitState = state
  
  # Handle based on state
  case state:
  of csrOpen:
    # Circuit is open, fail fast
    withLock(breaker.lock):
      inc breaker.statistics.totalCalls
      inc breaker.statistics.rejectedCalls
    
    if not breaker.metrics.isNil:
      breaker.metrics.increment(&"circuit.{breaker.name}.fast_fail")
    
    # Create circuit open error
    let circuitError = new CircuitOpenError
    circuitError.msg = &"Circuit '{breaker.name}' is open"
    circuitError.serviceName = breaker.name
    circuitError.openSince = breaker.lastStateChange
    
    result.error = some(circuitError)
    
    # Try fallback if available
    if breaker.fallback.isSome:
      let fallbackResult = breaker.fallback.get()()
      
      if fallbackResult.isOk:
        result.success = true
        result.value = some(fallbackResult.get())
        
        if not breaker.metrics.isNil:
          breaker.metrics.increment(&"circuit.{breaker.name}.fallback_success")
        
        if not breaker.logger.isNil:
          breaker.logger.debug(&"Circuit '{breaker.name}' used fallback successfully")
      else:
        # Fallback also failed
        if not breaker.metrics.isNil:
          breaker.metrics.increment(&"circuit.{breaker.name}.fallback_failure")
        
        if not breaker.logger.isNil:
          breaker.logger.warn(&"Circuit '{breaker.name}' fallback failed: {fallbackResult.error.msg}")
    
  of csrClosed, csrHalfOpen:
    # Circuit allows attempts (closed or half-open)
    let startTime = getMonoTime()
    
    # Execute the operation
    let opResult = operation()
    
    # Record time spent
    let endTime = getMonoTime()
    result.operationTime = endTime - startTime
    
    # Handle result
    if opResult.isOk:
      result.success = true
      result.value = some(opResult.get())
      breaker.recordSuccess()
      
      if not breaker.logger.isNil and state == csrHalfOpen:
        breaker.logger.info(&"Circuit '{breaker.name}' recovery test successful")
    else:
      result.error = some(opResult.error)
      breaker.recordFailure(opResult.error)
  
  result

proc forceOpen*[T](breaker: CircuitBreaker[T]) =
  ## Manually force the circuit to open state
  breaker.setState(csrOpen)

proc forceClose*[T](breaker: CircuitBreaker[T]) =
  ## Manually force the circuit to closed state
  breaker.setState(csrClosed)
  breaker.failureCount.store(0, moRelaxed)
  breaker.successCount.store(0, moRelaxed)

proc reset*[T](breaker: CircuitBreaker[T]) =
  ## Reset the circuit breaker to initial state
  breaker.setState(csrClosed)
  breaker.failureCount.store(0, moRelaxed)
  breaker.successCount.store(0, moRelaxed)
  
  withLock(breaker.lock):
    breaker.statistics.totalCalls = 0
    breaker.statistics.successfulCalls = 0
    breaker.statistics.failedCalls = 0
    breaker.statistics.rejectedCalls = 0
    breaker.statistics.lastSuccessTime = now()
    breaker.statistics.lastFailureTime = now()
  
  if not breaker.logger.isNil:
    breaker.logger.info(&"Circuit '{breaker.name}' has been reset")
  
  if not breaker.eventBus.isNil:
    breaker.eventBus.publish(newEvent("circuit.reset", %*{
      "circuit": breaker.name,
      "timestamp": $now()
    }))

proc getStatistics*[T](breaker: CircuitBreaker[T]): CircuitStatistics =
  ## Get statistics for the circuit breaker
  withLock(breaker.lock):
    result = breaker.statistics
    result.currentState = breaker.getState()

proc startHealthMonitor*[T](breaker: CircuitBreaker[T]) =
  ## Start health monitoring in a separate thread
  if breaker.healthCheck.isNone:
    if not breaker.logger.isNil:
      breaker.logger.warn(&"Cannot start health monitor for circuit '{breaker.name}' - no health check defined")
    return
  
  let healthCheckInterval = breaker.config.monitorInterval.inMilliseconds.int
  
  # In a real implementation, this would use a proper thread or timer
  # Here we'll just demonstrate the concept
  proc monitorHealth() {.thread.} =
    while true:
      # Sleep for interval
      sleep(healthCheckInterval)
      
      # Check if we're in open state
      if breaker.getState() == csrOpen:
        # Run health check
        let isHealthy = breaker.healthCheck.get()()
        
        if isHealthy:
          # Service is healthy again, transition to half-open
          breaker.setState(csrHalfOpen)
          
          if not breaker.logger.isNil:
            breaker.logger.info(&"Health check passed for circuit '{breaker.name}', entering half-open state")
  
  # Start monitoring thread
  var monitorThread: Thread[void]
  createThread(monitorThread, monitorHealth)
  
  if not breaker.logger.isNil:
    breaker.logger.info(&"Started health monitor for circuit '{breaker.name}'")

# Utility functions
proc protectHttpCall*[T](name: string, 
                       url: string, 
                       httpCall: proc(): Result[T, ref CatchableError],
                       logger: Logger = nil): CircuitBreaker[T] =
  ## Create a circuit breaker protecting an HTTP call
  let breaker = newCircuitBreaker[T](name)
  
  if not logger.isNil:
    breaker.withLogging(logger)
  
  # Add health check
  let healthCheck = proc(): bool =
    try:
      # Simple ping check
      let client = newHttpClient()
      client.timeout = 2000 # 2 seconds
      
      let response = client.get(url)
      result = response.code >= 200 and response.code < 500
    except:
      result = false
  
  breaker.withHealthCheck(healthCheck)
  
  # Start health monitor
  breaker.startHealthMonitor()
  
  breaker

# DSL for circuit breaker
template withCircuitBreaker*[T](name: string, config: CircuitBreakerConfig, body: untyped): CircuitResult[T] =
  ## Run code with circuit breaker protection
  let breaker = newCircuitBreaker[T](name, config)
  
  let operation = proc(): Result[T, ref CatchableError] =
    try:
      let result: T = body
      Result[T, ref CatchableError].ok(result)
    except CatchableError as e:
      Result[T, ref CatchableError].err(e)
  
  breaker.execute(operation)