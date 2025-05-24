## Tests for Future/Promise pattern
##
## This module tests the concurrency/future.nim implementation of the Future/Promise pattern

import std/[unittest, asyncdispatch, strformat, times, tables, options, threadpool]
import std/locks except Lock
import std/atomics
import ../src/nim_design_patterns/concurrency/future
import ../src/nim_design_patterns/core/base

# Helper for test tracking
var testStats = (passed: 0, failed: 0)

proc runTests*(): int =
  ## Run all tests in this module
  ## Returns the number of failed tests
  
  suite "Future/Promise Pattern Tests":
    echo "  Future/Promise Tests:"
    
    test "Create and resolve a simple future":
      let promise = newPromise[int]()
      let future = promise.future
      
      # Check initial state
      check(future.getState() == fsPending)
      check(not future.isCompleted())
      
      # Resolve the future
      promise.resolve(42)
      
      # Check state after resolution
      check(future.getState() == fsResolved)
      check(future.isCompleted())
      check(future.isResolved())
      check(not future.isRejected())
      check(future.getValue().get() == 42)
      
      inc testStats.passed
    
    test "Create and reject a future":
      let promise = newPromise[string]()
      let future = promise.future
      
      # Reject the future
      let error = (ref CatchableError)(msg: "Test error")
      promise.reject(error)
      
      # Check state after rejection
      check(future.getState() == fsRejected)
      check(future.isCompleted())
      check(future.isRejected())
      check(not future.isResolved())
      check(future.getError().get().msg == "Test error")
      
      inc testStats.passed
    
    test "Register callbacks on future":
      let promise = newPromise[int]()
      let future = promise.future
      
      var successCalled = false
      var successValue = 0
      var errorCalled = false
      var finallyCalled = false
      
      discard future.onSuccess(
        proc(value: int) =
          successCalled = true
          successValue = value
      ).onError(
        proc(error: ref CatchableError) =
          errorCalled = true
      ).finally(
        proc() =
          finallyCalled = true
      )
      
      promise.resolve(99)
      
      check(successCalled)
      check(successValue == 99)
      check(not errorCalled)
      check(finallyCalled)
      
      inc testStats.passed
    
    test "Transform a future with map":
      let promise = newPromise[int]()
      let future = promise.future
      
      # Create a transformed future
      let transformedFuture = future.map(
        proc(value: int): string =
          $value & " transformed"
      )
      
      # Resolve the original future
      promise.resolve(42)
      
      # Check transformed future
      check(transformedFuture.isResolved())
      check(transformedFuture.getValue().get() == "42 transformed")
      
      inc testStats.passed
    
    test "Chain futures with flatMap":
      let promise1 = newPromise[int]()
      let future1 = promise1.future
      
      # Create a chained future with flatMap
      let chainedFuture = future1.flatMap(
        proc(value: int): Future[string] =
          let p = newPromise[string]()
          p.resolve($value & " chained")
          return p.future
      )
      
      # Resolve the first future
      promise1.resolve(42)
      
      # Check chained future
      check(chainedFuture.isResolved())
      check(chainedFuture.getValue().get() == "42 chained")
      
      inc testStats.passed
    
    test "Recover from a rejected future":
      let promise = newPromise[int]()
      let future = promise.future
      
      # Create a recovered future
      let recoveredFuture = future.recover(
        proc(error: ref CatchableError): int =
          return 999  # Fallback value
      )
      
      # Reject the original future
      promise.reject((ref CatchableError)(msg: "Error"))
      
      # Check recovered future
      check(recoveredFuture.isResolved())
      check(recoveredFuture.getValue().get() == 999)
      
      inc testStats.passed
    
    test "Timeout for a future":
      let promise = newPromise[int]()
      let future = promise.future
      
      # Set a timeout of 100ms
      discard future.withTimeout(100)
      
      # Sleep to allow the timeout to trigger
      sleep(200)
      
      # Check that future timed out
      check(future.isTimedOut())
      check(future.getError().get() of FutureTimeoutError)
      
      inc testStats.passed
    
    test "Cancel a future":
      let promise = newPromise[int]()
      let future = promise.future
      
      # Cancel the future
      future.cancel()
      
      # Check the state
      check(future.isCancelled())
      check(future.getError().get() of FutureCancelledError)
      
      inc testStats.passed
    
    test "Wait for future completion":
      let promise = newPromise[int]()
      let future = promise.future
      
      # Resolve after a delay
      asyncCheck (proc() {.async.} =
        await sleepAsync(50)
        promise.resolve(42)
      )()
      
      # Wait for completion
      let completed = future.waitForCompletion(200)
      
      check(completed)
      check(future.isResolved())
      check(future.getValue().get() == 42)
      
      inc testStats.passed
    
    test "Combine multiple futures with all()":
      let promise1 = newPromise[int]()
      let promise2 = newPromise[int]()
      let promise3 = newPromise[int]()
      
      let future1 = promise1.future
      let future2 = promise2.future
      let future3 = promise3.future
      
      let combinedFuture = all(@[future1, future2, future3])
      
      # Resolve the futures
      promise1.resolve(1)
      promise2.resolve(2)
      promise3.resolve(3)
      
      # Wait for the combined future
      let completed = combinedFuture.waitForCompletion()
      
      check(completed)
      check(combinedFuture.isResolved())
      
      let result = combinedFuture.getValue().get()
      check(result.len == 3)
      check(result[0] == 1)
      check(result[1] == 2)
      check(result[2] == 3)
      
      inc testStats.passed
    
    test "Race futures with any()":
      let promise1 = newPromise[string]()
      let promise2 = newPromise[string]()
      let promise3 = newPromise[string]()
      
      let future1 = promise1.future
      let future2 = promise2.future
      let future3 = promise3.future
      
      let raceFuture = any(@[future1, future2, future3])
      
      # Resolve only the second future
      promise2.resolve("winner")
      
      # Wait for the race future
      let completed = raceFuture.waitForCompletion()
      
      check(completed)
      check(raceFuture.isResolved())
      check(raceFuture.getValue().get() == "winner")
      
      inc testStats.passed
    
    test "Create futures from values and errors":
      let successFuture = fromValue[int](42)
      let errorFuture = fromError[int]((ref CatchableError)(msg: "Created with error"))
      
      check(successFuture.isResolved())
      check(successFuture.getValue().get() == 42)
      
      check(errorFuture.isRejected())
      check(errorFuture.getError().get().msg == "Created with error")
      
      inc testStats.passed
    
    test "Create future from synchronous function":
      let funcFuture = fromProc[int](
        proc(): int =
          return 42
      )
      
      let completed = funcFuture.waitForCompletion(100)
      
      check(completed)
      check(funcFuture.isResolved())
      check(funcFuture.getValue().get() == 42)
      
      inc testStats.passed
    
    test "Create future from asynchronous function":
      let asyncFuncFuture = fromAsyncProc[int](
        proc(): Future[int] {.async.} =
          await sleepAsync(50)
          return 42
      )
      
      let completed = asyncFuncFuture.waitForCompletion(200)
      
      check(completed)
      check(asyncFuncFuture.isResolved())
      check(asyncFuncFuture.getValue().get() == 42)
      
      inc testStats.passed
    
    test "Integrate with Nim's asyncdispatch":
      # Create a Nim future
      var nimFuture = newFuture[int]("test")
      
      # Convert to our Future
      let customFuture = fromNimFuture(nimFuture)
      
      # Complete the Nim future
      nimFuture.complete(42)
      
      check(customFuture.waitForCompletion(100))
      check(customFuture.isResolved())
      check(customFuture.getValue().get() == 42)
      
      # Now test conversion in the other direction
      let promise = newPromise[string]()
      let ourFuture = promise.future
      
      let convertedNimFuture = toNimFuture(ourFuture)
      
      promise.resolve("hello")
      
      check(not convertedNimFuture.finished)  # Need to pump events
      poll()  # Process pending callbacks
      
      check(convertedNimFuture.finished)
      check(not convertedNimFuture.failed)
      check(convertedNimFuture.read() == "hello")
      
      inc testStats.passed
  
  # Return the number of failed tests
  echo &"  Future/Promise Tests: {testStats.passed} passed, {testStats.failed} failed"
  testStats.failed

# When run directly, execute tests
when isMainModule:
  discard runTests()