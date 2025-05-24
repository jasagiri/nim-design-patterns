## Standalone test runner for Lens pattern

import std/[unittest, os, strformat, times]
import test_lens

proc main() =
  echo "\n================================================================"
  echo " nim-design-patterns: Running Lens Pattern Tests"
  echo "================================================================\n"
  
  let startTime = epochTime()
  
  # Run the lens tests
  var failures = 0
  failures += test_lens.runTests()
  
  let duration = epochTime() - startTime
  
  echo "\n----------------------------------------------------------------"
  if failures == 0:
    echo &" ✓ ALL LENS TESTS PASSED in {duration:.2f} seconds"
  else:
    echo &" ✗ {failures} TEST(S) FAILED in {duration:.2f} seconds"
  echo "----------------------------------------------------------------\n"
  
  # Exit with appropriate code for CI integration
  quit(if failures > 0: 1 else: 0)

when isMainModule:
  main()