import unittest
import options
import sugar
import strutils

# Import the Monad pattern implementation
import ../src/nim_design_patterns/functional/monad
import ../src/nim_design_patterns/core/base

# Test suite
proc runTests*(): int =
  # Returns the number of test failures
  var failures = 0
  
  # Tests
  suite "Monad Pattern":
    test "Maybe Monad - basic operations":
      # Test just (some)
      let m1 = just(42)
      check m1.isSome
      check m1.get == 42
      
      # Test nothing (none)
      let m2 = nothing[int]()
      check m2.isNone
      
      # Test map
      let m3 = just(10)
      let m4 = m3.map(proc(x: int): int = x * 2)
      check m4.isSome
      check m4.get == 20
      
      # Test map on nothing
      let m5 = nothing[int]()
      let m6 = m5.map(proc(x: int): int = x * 2)
      check m6.isNone
      
      # Test flatMap
      let m7 = just(10)
      let m8 = m7.flatMap(proc(x: int): Maybe[int] = just(x * 3))
      check m8.isSome
      check m8.get == 30
      
      # Test flatMap with a function that returns nothing
      let m9 = just(10)
      let m10 = m9.flatMap(proc(x: int): Maybe[int] = 
        if x > 100: just(x) else: nothing[int]()
      )
      check m10.isNone
      
      # Test flatMap on nothing
      let m11 = nothing[int]()
      let m12 = m11.flatMap(proc(x: int): Maybe[int] = just(x * 3))
      check m12.isNone
      
      # Test getOrElse
      let m13 = just(42)
      check m13.getOrElse(0) == 42
      
      let m14 = nothing[int]()
      check m14.getOrElse(0) == 0
      
      # Test filter
      let m15 = just(42)
      let m16 = m15.filter(proc(x: int): bool = x > 40)
      check m16.isSome
      check m16.get == 42
      
      let m17 = just(42)
      let m18 = m17.filter(proc(x: int): bool = x > 100)
      check m18.isNone
    
    test "Result Monad - basic operations":
      # Define a simple error type
      type ErrorKind = enum
        NotFound, InvalidInput, Unknown
        
      # Test success
      let r1 = success[int, ErrorKind](42)
      check r1.isSuccess
      check r1.value == 42
      
      # Test failure
      let r2 = failure[int, ErrorKind](NotFound)
      check not r2.isSuccess
      check r2.error == NotFound
      
      # Test map
      let r3 = success[int, ErrorKind](10)
      let r4 = r3.map(proc(x: int): int = x * 2)
      check r4.isSuccess
      check r4.value == 20
      
      # Test map on failure
      let r5 = failure[int, ErrorKind](InvalidInput)
      let r6 = r5.map(proc(x: int): int = x * 2)
      check not r6.isSuccess
      check r6.error == InvalidInput
      
      # Test flatMap
      let r7 = success[int, ErrorKind](10)
      let r8 = r7.flatMap(proc(x: int): Result[int, ErrorKind] = 
        success[int, ErrorKind](x * 3)
      )
      check r8.isSuccess
      check r8.value == 30
      
      # Test flatMap with a function that returns failure
      let r9 = success[int, ErrorKind](10)
      let r10 = r9.flatMap(proc(x: int): Result[int, ErrorKind] = 
        if x > 100: success[int, ErrorKind](x) else: failure[int, ErrorKind](InvalidInput)
      )
      check not r10.isSuccess
      check r10.error == InvalidInput
      
      # Test flatMap on failure
      let r11 = failure[int, ErrorKind](NotFound)
      let r12 = r11.flatMap(proc(x: int): Result[int, ErrorKind] = 
        success[int, ErrorKind](x * 3)
      )
      check not r12.isSuccess
      check r12.error == NotFound
      
      # Test getOrElse
      let r13 = success[int, ErrorKind](42)
      check r13.getOrElse(0) == 42
      
      let r14 = failure[int, ErrorKind](NotFound)
      check r14.getOrElse(0) == 0
      
      # Test mapError
      let r15 = failure[int, ErrorKind](InvalidInput)
      let r16 = r15.mapError(proc(e: ErrorKind): string = $e)
      check not r16.isSuccess
      check r16.error == "InvalidInput"
      
      # Test fold
      let r17 = success[int, ErrorKind](42)
      let foldResult1 = r17.fold(
        proc(v: int): string = "Success: " & $v,
        proc(e: ErrorKind): string = "Error: " & $e
      )
      check foldResult1 == "Success: 42"
      
      let r18 = failure[int, ErrorKind](NotFound)
      let foldResult2 = r18.fold(
        proc(v: int): string = "Success: " & $v,
        proc(e: ErrorKind): string = "Error: " & $e
      )
      check foldResult2 == "Error: NotFound"
    
    test "State Monad - basic operations":
      # Define a simple state
      type AppState = object
        count: int
        name: string
      
      # Test basic state execution
      let simpleState = state(proc(s: AppState): tuple[value: int, state: AppState] =
        (s.count, AppState(count: s.count + 1, name: s.name))
      )
      
      let initialState = AppState(count: 0, name: "test")
      let (value, newState) = runState(simpleState, initialState)
      
      check value == 0
      check newState.count == 1
      check newState.name == "test"
      
      # Test evalState (returning only the value)
      let stateValue = evalState(simpleState, initialState)
      check stateValue == 0
      
      # Test execState (returning only the state)
      let stateOnly = execState(simpleState, initialState)
      check stateOnly.count == 1
      check stateOnly.name == "test"
      
      # Test map
      let mappedState = simpleState.map(proc(a: int): string = "Count: " & $a)
      let (mappedValue, mappedNewState) = runState(mappedState, initialState)
      
      check mappedValue == "Count: 0"
      check mappedNewState.count == 1
      
      # Test flatMap (chaining state operations)
      let firstState = state(proc(s: AppState): tuple[value: int, state: AppState] =
        (s.count, AppState(count: s.count + 1, name: s.name))
      )
      
      let secondState = proc(x: int): State[AppState, string] =
        state(proc(s: AppState): tuple[value: string, state: AppState] =
          ("Count: " & $x & ", New count: " & $s.count, 
           AppState(count: s.count * 2, name: s.name & " updated"))
        )
      
      let combinedState = firstState.flatMap(secondState)
      let (combinedValue, combinedNewState) = runState(combinedState, initialState)
      
      check combinedValue == "Count: 0, New count: 1"
      check combinedNewState.count == 2
      check combinedNewState.name == "test updated"
      
      # Test get, put, and modify
      let getState = get[AppState]()
      let putState = put(AppState(count: 100, name: "replaced"))
      let modifyState = modify(proc(s: AppState): AppState = 
        AppState(count: s.count + 10, name: s.name & " modified")
      )
      
      # Chain operations together with flatMap
      let complexState = getState.flatMap(proc(s: AppState): State[AppState, string] =
        # First read the state
        let initialCount = s.count
        # Then modify it
        modifyState.flatMap(proc(_: EmptyType): State[AppState, string] =
          # Then get the modified state
          getState.flatMap(proc(s2: AppState): State[AppState, string] =
            # Then replace it
            putState.flatMap(proc(_: EmptyType): State[AppState, string] =
              # Return some value capturing the whole process
              state(proc(s3: AppState): tuple[value: string, state: AppState] =
                ("Started with " & $initialCount & 
                 ", modified to " & $s2.count & 
                 ", and replaced to " & $s3.count, s3)
              )
            )
          )
        )
      )
      
      let (complexValue, complexFinalState) = runState(complexState, initialState)
      check complexValue == "Started with 0, modified to 10, and replaced to 100"
      check complexFinalState.count == 100
      check complexFinalState.name == "replaced"
    
    test "Monad combinators and utilities":
      # Test flatten for Maybe
      let nested1 = just(just(42))
      let flattened1 = flatten(nested1)
      check flattened1.isSome
      check flattened1.get == 42
      
      let nested2 = just(nothing[int]())
      let flattened2 = flatten(nested2)
      check flattened2.isNone
      
      # Test flatten for Result
      type ErrorKind = enum
        NotFound, InvalidInput
      
      let nested3 = success[Result[int, ErrorKind], ErrorKind](
        success[int, ErrorKind](42)
      )
      let flattened3 = flatten(nested3)
      check flattened3.isSuccess
      check flattened3.value == 42
      
      let nested4 = success[Result[int, ErrorKind], ErrorKind](
        failure[int, ErrorKind](NotFound)
      )
      let flattened4 = flatten(nested4)
      check not flattened4.isSuccess
      check flattened4.error == NotFound
      
      # Test traverse for Maybe
      let numbers = @[1, 2, 3, 4, 5]
      
      let evenResult = traverse(numbers, proc(x: int): Maybe[int] =
        if x mod 2 == 0: just(x * 10) else: nothing[int]()
      )
      check evenResult.isNone
      
      let allResult = traverse(numbers, proc(x: int): Maybe[int] = just(x * 10))
      check allResult.isSome
      check allResult.get == @[10, 20, 30, 40, 50]
      
      # Test traverse for Result
      let traverseResult1 = traverse(numbers, proc(x: int): Result[int, ErrorKind] =
        if x > 3: 
          failure[int, ErrorKind](InvalidInput)
        else:
          success[int, ErrorKind](x * 10)
      )
      check not traverseResult1.isSuccess
      check traverseResult1.error == InvalidInput
      
      let traverseResult2 = traverse(numbers, proc(x: int): Result[int, ErrorKind] =
        success[int, ErrorKind](x * 10)
      )
      check traverseResult2.isSuccess
      check traverseResult2.value == @[10, 20, 30, 40, 50]
    
    test "Monad combinators with templates":
      # Test withMaybe template
      let m1 = just(42)
      let doubledMaybe = withMaybe[int, int](m1, x):
        just(x * 2)
      check doubledMaybe.isSome
      check doubledMaybe.get == 84
      
      let m2 = nothing[int]()
      let doubledNothing = withMaybe[int, int](m2, x):
        just(x * 2)
      check doubledNothing.isNone
      
      # Test withResult template
      type ErrorKind = enum
        NotFound, InvalidInput
        
      let r1 = success[int, ErrorKind](42)
      let doubledResult = withResult[int, ErrorKind, int](r1, x):
        success[int, ErrorKind](x * 2)
      check doubledResult.isSuccess
      check doubledResult.value == 84
      
      let r2 = failure[int, ErrorKind](NotFound)
      let doubledFailure = withResult[int, ErrorKind, int](r2, x):
        success[int, ErrorKind](x * 2)
      check not doubledFailure.isSuccess
      check doubledFailure.error == NotFound
      
      # Test chaining withMaybe
      proc complexMaybeOperation(a: int, b: int): Maybe[int] =
        withMaybe[int, int](just(a), x):
          withMaybe[int, int](just(b), y):
            if y == 0:
              nothing[int]()
            else:
              just(x div y)
      
      let divResult1 = complexMaybeOperation(10, 2)
      check divResult1.isSome
      check divResult1.get == 5
      
      let divResult2 = complexMaybeOperation(10, 0)
      check divResult2.isNone
      
      # Test chaining withResult
      proc complexResultOperation(a: int, b: int): Result[int, ErrorKind] =
        withResult[int, ErrorKind, int](success[int, ErrorKind](a), x):
          withResult[int, ErrorKind, int](success[int, ErrorKind](b), y):
            if y == 0:
              failure[int, ErrorKind](InvalidInput)
            else:
              success[int, ErrorKind](x div y)
      
      let divResult3 = complexResultOperation(10, 2)
      check divResult3.isSuccess
      check divResult3.value == 5
      
      let divResult4 = complexResultOperation(10, 0)
      check not divResult4.isSuccess
      check divResult4.error == InvalidInput
  
  return failures

# Run the tests when this module is executed directly
when isMainModule:
  let failures = runTests()
  quit(if failures > 0: 1 else: 0)