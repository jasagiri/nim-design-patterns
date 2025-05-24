## Main test runner for nim-design-patterns

import std/[unittest, os, strformat, times]

# Import all test modules
import test_factory
import test_observer
import test_saga_minimal_exec  # Using our working saga test
import test_circuit_breaker
import test_executor
import test_statemachine
import test_checks_effects_interactions
import test_lens  # Lens pattern for immutable data
import test_future  # Future/Promise concurrency pattern

# Note: When adding new pattern tests, import them here

# Main test runner
proc main() =
  echo "\n================================================================"
  echo " nim-design-patterns: Running all tests"
  echo "================================================================\n"
  
  let startTime = epochTime()
  
  # Run all tests
  var failures = 0
  failures += test_factory.runTests()
  failures += test_observer.runTests()
  failures += test_saga_minimal_exec.runTests()
  failures += test_circuit_breaker.runTests()
  failures += test_executor.runTests()
  failures += test_statemachine.runTests()
  failures += test_checks_effects_interactions.runTests()
  failures += test_lens.runTests()
  failures += test_future.runTests()
  
  # Add other test modules here as they are created
  # failures += test_builder.runTests()
  # failures += test_singleton.runTests()
  # failures += test_adapter.runTests()
  # failures += test_decorator.runTests()
  # failures += test_proxy.runTests()
  # failures += test_strategy.runTests()
  # failures += test_command.runTests()
  # failures += test_integration.runTests()
  
  # Functional patterns
  # - test_lens.runTests() is already included above
  
  # Concurrency patterns
  # - test_future.runTests() is already included above
  
  let duration = epochTime() - startTime
  
  echo "\n----------------------------------------------------------------"
  if failures == 0:
    echo &" ✓ ALL TESTS PASSED in {duration:.2f} seconds"
  else:
    echo &" ✗ {failures} TEST(S) FAILED in {duration:.2f} seconds"
  echo "----------------------------------------------------------------\n"
  
  # Exit with appropriate code for CI integration
  quit(if failures > 0: 1 else: 0)

when isMainModule:
  main()