import unittest
import std/tables
import ../src/nim_design_patterns/functional/lazy

suite "Lazy Evaluation Pattern":
  test "Basic lazy value creation and forcing":
    var computationCount = 0
    
    # Create a lazy value
    let lazyVal = lazy(proc(): int =
      computationCount += 1
      return 42
    )
    
    # Computation shouldn't happen until forced
    check computationCount == 0
    check not lazyVal.isComputed
    
    # Force computation
    let result = force(lazyVal)
    check result == 42
    check computationCount == 1
    check lazyVal.isComputed
    
    # Subsequent forces should use memoized value
    discard force(lazyVal)
    check computationCount == 1

  test "Lazy values without memoization":
    var computationCount = 0
    
    # Create a non-memoizing lazy value
    let lazyVal = lazyNoMemo(proc(): int =
      computationCount += 1
      return 42
    )
    
    # Force computation multiple times
    check force(lazyVal) == 42
    check force(lazyVal) == 42
    check force(lazyVal) == 42
    
    # Each force should recompute
    check computationCount == 3

  test "Mapping and transforming lazy values":
    let lazyNum = lazy(proc(): int = 10)
    
    # Map a lazy value
    let doubled = map(lazyNum, proc(x: int): int = x * 2)
    let asString = map(lazyNum, proc(x: int): string = $x)
    
    # Should preserve laziness
    check not doubled.isComputed
    check not asString.isComputed
    
    # Transformations work correctly
    check force(doubled) == 20
    check force(asString) == "10"
    
    # Original lazy value should be computed after one of its maps is forced
    check lazyNum.isComputed

  test "Chaining lazy computations with flatMap":
    let lazyNum = lazy(proc(): int = 10)
    
    # Chain with another lazy computation
    let chained = flatMap(lazyNum, proc(x: int): Lazy[string] =
      lazy(proc(): string = $x & " after processing")
    )
    
    # Should preserve laziness
    check not chained.isComputed
    
    # Correct result after forcing
    check force(chained) == "10 after processing"

  test "Combining lazy values with zip":
    let lazyNum = lazy(proc(): int = 10)
    let lazyStr = lazy(proc(): string = "hello")
    
    # Zip two lazy values
    let combined = zip(lazyNum, lazyStr)
    
    # Should preserve laziness
    check not combined.isComputed
    
    # Correct tuple result after forcing
    let result = force(combined)
    check result[0] == 10
    check result[1] == "hello"
    
    # Both original values should be computed
    check lazyNum.isComputed
    check lazyStr.isComputed

  test "Lazy sequences - take operation":
    # Create an infinite sequence of natural numbers
    let naturalsSeq = naturals()
    
    # Take the first 5 elements
    let firstFive = take(naturalsSeq, 5)
    
    # Check we got the correct elements
    check firstFive == @[0, 1, 2, 3, 4]
    
    # Try with the Fibonacci sequence
    let fibSeq = fibonacci()
    let firstSixFib = take(fibSeq, 6)
    
    # Check we got the correct Fibonacci numbers
    check firstSixFib == @[0, 1, 1, 2, 3, 5]
    
    # Check primes sequence
    let primeSeq = primes()
    let firstFivePrimes = take(primeSeq, 5)
    
    # Check we got the correct prime numbers
    check firstFivePrimes == @[2, 3, 5, 7, 11]

  test "Lazy sequences - filter operation":
    # Create a sequence of natural numbers
    let naturalsSeq = naturals()
    
    # Filter for even numbers
    let evenSeq = filter(naturalsSeq, proc(x: int): bool = x mod 2 == 0)
    
    # Take the first few even numbers
    let firstFiveEven = take(evenSeq, 5)
    
    # Check we got the correct even numbers
    check firstFiveEven == @[0, 2, 4, 6, 8]
    
    # Filter for numbers divisible by 3
    let div3Seq = filter(naturalsSeq, proc(x: int): bool = x mod 3 == 0)
    
    # Take the first few
    let firstFiveDiv3 = take(div3Seq, 5)
    
    # Check we got the correct numbers
    check firstFiveDiv3 == @[0, 3, 6, 9, 12]

  test "Lazy sequences - map operation":
    # Create a sequence of natural numbers
    let naturalsSeq = naturals()
    
    # Map to double each number
    let doubledSeq = map(naturalsSeq, proc(x: int): int = x * 2)
    
    # Take the first few doubled numbers
    let firstFiveDoubled = take(doubledSeq, 5)
    
    # Check we got the correct values
    check firstFiveDoubled == @[0, 2, 4, 6, 8]
    
    # Map to strings
    let stringSeq = map(naturalsSeq, proc(x: int): string = "Number " & $x)
    
    # Take the first few
    let firstThreeStrings = take(stringSeq, 3)
    
    # Check we got the correct strings
    check firstThreeStrings == @["Number 0", "Number 1", "Number 2"]

  test "Function memoization":
    var computationCount = 0
    
    # Create a computationally expensive function
    proc expensiveFunc(n: int): int =
      computationCount += 1
      result = n * n
    
    # Create a memoized version
    let memoizedFunc = memoize(expensiveFunc)
    
    # First call should compute
    check memoizedFunc(5) == 25
    check computationCount == 1
    
    # Second call to same value should use cache
    check memoizedFunc(5) == 25
    check computationCount == 1
    
    # Call with different value should compute
    check memoizedFunc(10) == 100
    check computationCount == 2
    
    # Test with multiple arguments
    var multiArgCount = 0
    
    proc expensiveFunc2(a, b: int): int =
      multiArgCount += 1
      result = a * b
    
    let memoizedFunc2 = memoize2(expensiveFunc2)
    
    check memoizedFunc2(3, 4) == 12
    check multiArgCount == 1
    
    check memoizedFunc2(3, 4) == 12  # Same args, should use cache
    check multiArgCount == 1
    
    check memoizedFunc2(5, 6) == 30  # Different args, should compute
    check multiArgCount == 2