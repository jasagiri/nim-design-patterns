## Tests for the Circuit Breaker pattern

import unittest
import std/[strformat, tables, options, times]
import nim_libaspects/[logging, errors, events, metrics]
import nim_design_patterns/modern/circuit_breaker

# Helper proc to export for test_all.nim
proc runTests*(): int =
  # Return number of failures
  let results = unittest.runTests()
  results.failures

suite "Circuit Breaker Pattern Tests":
  # Setup test objects
  setup:
    # Test service that can fail on demand
    var shouldServiceFail = false
    
    # Simple service operation
    let serviceOperation = proc(): Result[string, ref CatchableError] =
      if shouldServiceFail:
        return Result[string, ref CatchableError].err(
          (ref CatchableError)(msg: "Service unavailable")
        )
      Result[string, ref CatchableError].ok("Success")
    
    # Fallback operation
    let fallbackOperation = proc(): Result[string, ref CatchableError] =
      Result[string, ref CatchableError].ok("Fallback result")
    
    # Create a circuit breaker with custom config for faster testing
    var config = defaultConfig()
    config.failureThreshold = 2      # Open after 2 failures
    config.resetTimeout = initDuration(milliseconds = 100)  # Shorter timeout for testing
    config.successThreshold = 1      # Close after 1 success
    
    let breaker = newCircuitBreaker[string]("TestCircuit", config)
      .withFallback(fallbackOperation)
    
    # Use metrics to track operations
    let metrics = newMetricsRegistry()
    breaker.withMetrics(metrics)
  
  test "Circuit starts in closed state":
    # Verify initial state
    check breaker.getState() == csrClosed
    
    # Execute successful operation
    let result = breaker.execute(serviceOperation)
    
    # Verify results
    check result.success == true
    check result.value.get() == "Success"
    check result.circuitState == csrClosed
    
    # Check statistics
    let stats = breaker.getStatistics()
    check stats.totalCalls == 1
    check stats.successfulCalls == 1
    check stats.failedCalls == 0
    check stats.rejectedCalls == 0

  test "Circuit opens after failure threshold is reached":
    # Make service fail
    shouldServiceFail = true
    
    # First failure
    var result = breaker.execute(serviceOperation)
    check result.success == false
    check result.error.isSome
    check breaker.getState() == csrClosed  # Still closed after first failure
    
    # Second failure (should open circuit)
    result = breaker.execute(serviceOperation)
    check result.success == false
    check result.error.isSome
    check breaker.getState() == csrOpen    # Now open after second failure
    
    # Check statistics
    let stats = breaker.getStatistics()
    check stats.totalCalls == 2
    check stats.successfulCalls == 0
    check stats.failedCalls == 2
    check stats.rejectedCalls == 0
    check stats.openCircuitCount == 1

  test "Open circuit uses fallback and fails fast":
    # First force circuit open
    breaker.forceOpen()
    check breaker.getState() == csrOpen
    
    # Request with open circuit
    let result = breaker.execute(serviceOperation)
    
    # Should use fallback
    check result.success == true
    check result.value.get() == "Fallback result"
    check result.error.isSome
    check result.error.get() of CircuitOpenError
    
    # Check statistics
    let stats = breaker.getStatistics()
    check stats.rejectedCalls == 1  # Request was rejected but fallback worked

  test "Circuit transitions to half-open after timeout":
    # Force circuit open
    breaker.forceOpen()
    check breaker.getState() == csrOpen
    
    # Wait for timeout
    sleep(150)  # A bit longer than our 100ms timeout
    
    # Run circuit check
    breaker.checkState()
    
    # Should now be half-open
    check breaker.getState() == csrHalfOpen

  test "Half-open circuit closes after success":
    # Set service to succeed
    shouldServiceFail = false
    
    # Force half-open state
    breaker.setState(csrHalfOpen)
    
    # Execute operation (should succeed)
    let result = breaker.execute(serviceOperation)
    
    # Verify circuit closed
    check result.success == true
    check breaker.getState() == csrClosed  # Back to closed after success

  test "Half-open circuit reopens after failure":
    # Set service to fail
    shouldServiceFail = true
    
    # Force half-open state
    breaker.setState(csrHalfOpen)
    
    # Execute operation (should fail)
    let result = breaker.execute(serviceOperation)
    
    # Verify circuit reopened
    check result.success == false
    check breaker.getState() == csrOpen  # Back to open after failure

  test "Reset clears all statistics":
    # Execute some operations
    shouldServiceFail = false
    discard breaker.execute(serviceOperation)
    discard breaker.execute(serviceOperation)
    
    # Check we have stats
    var stats = breaker.getStatistics()
    check stats.totalCalls > 0
    
    # Reset circuit
    breaker.reset()
    
    # Check stats are cleared
    stats = breaker.getStatistics()
    check stats.totalCalls == 0
    check stats.successfulCalls == 0
    check stats.failedCalls == 0
    check stats.rejectedCalls == 0
    check breaker.getState() == csrClosed

  test "DSL works correctly":
    # Setup
    shouldServiceFail = false
    
    # Use DSL to execute with circuit breaker
    let result = withCircuitBreaker[string]("DSLCircuit", config):
      if shouldServiceFail:
        raise newException(CatchableError, "Service unavailable")
      "Success from DSL"
    
    # Verify results
    check result.success == true
    check result.value.get() == "Success from DSL"
    check result.circuitState == csrClosed

  test "Multiple failures and recoveries work correctly":
    # Scenario: Multiple cycles of failure and recovery
    
    # Start with working service
    shouldServiceFail = false
    var result = breaker.execute(serviceOperation)
    check result.success == true
    check breaker.getState() == csrClosed
    
    # Make service fail until circuit opens
    shouldServiceFail = true
    result = breaker.execute(serviceOperation)
    check result.success == false
    check breaker.getState() == csrClosed
    
    result = breaker.execute(serviceOperation)
    check result.success == false
    check breaker.getState() == csrOpen
    
    # Service back to normal
    shouldServiceFail = false
    
    # Circuit still open, should use fallback
    result = breaker.execute(serviceOperation)
    check result.success == true
    check result.value.get() == "Fallback result"
    check breaker.getState() == csrOpen
    
    # Wait for timeout and transition to half-open
    sleep(150)
    breaker.checkState()
    check breaker.getState() == csrHalfOpen
    
    # Try again, should succeed and close circuit
    result = breaker.execute(serviceOperation)
    check result.success == true
    check result.value.get() == "Success"
    check breaker.getState() == csrClosed
    
    # Check final statistics
    let stats = breaker.getStatistics()
    check stats.openCircuitCount >= 1
    check stats.successfulCalls >= 2
    check stats.failedCalls >= 2

when isMainModule:
  unittest.run()