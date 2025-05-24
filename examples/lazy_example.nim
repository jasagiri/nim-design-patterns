## Lazy Evaluation Pattern Example
##
## This example demonstrates practical applications of lazy evaluation for
## improved performance and working with potentially infinite data structures.

import std/[strformat, times, sequtils, os]
import ../src/nim_design_patterns/functional/lazy

# Example 1: Avoiding expensive computations that might not be needed
# ---------------------------------------------------------

proc simulateExpensiveComputation(input: int): int =
  # Simulate a computation that takes time
  sleep(100)  # Sleep for 100ms to simulate expensive processing
  result = input * input

proc processUserData(id: int, includeExpensiveMetrics: bool): string =
  echo "Processing user data for ID: ", id
  
  # Create lazy computations that will only execute if needed
  let basicUserInfo = lazy(proc(): string = 
    echo "Fetching basic user info..."
    "User #" & $id
  )
  
  let expensiveMetrics = lazy(proc(): string =
    echo "Computing expensive metrics..."
    let value = simulateExpensiveComputation(id)
    "Metric value: " & $value
  )
  
  # Always use the basic info
  var userData = force(basicUserInfo)
  
  # Only compute expensive metrics if needed
  if includeExpensiveMetrics:
    userData &= "\n" & force(expensiveMetrics)
  
  userData

echo "Example 1: Conditional Computation"
echo "---------------------------------"
echo "Processing with minimal metrics:"
echo processUserData(42, false)
echo "\nProcessing with all metrics:"
echo processUserData(42, true)
echo ""

# Example 2: Working with infinite sequences
# ---------------------------------------------------------

echo "Example 2: Infinite Sequences"
echo "---------------------------"

# Generate prime numbers lazily
let primeSeq = primes()

echo "First 10 prime numbers:"
let first10Primes = take(primeSeq, 10)
for i, prime in first10Primes:
  echo fmt"Prime #{i+1}: {prime}"

# Find the first prime number above 1000
let bigPrimes = filter(primeSeq, proc(x: int): bool = x > 1000)
let firstBigPrime = take(bigPrimes, 1)[0]
echo fmt"\nFirst prime number above 1000: {firstBigPrime}"

# Generate Fibonacci sequence and find first Fibonacci number over 10000
let fibSeq = fibonacci()
let bigFibs = filter(fibSeq, proc(x: int): bool = x > 10000)
let firstBigFib = take(bigFibs, 1)[0]
echo fmt"First Fibonacci number over 10000: {firstBigFib}"
echo ""

# Example 3: Memoization for expensive function calls
# ---------------------------------------------------------

echo "Example 3: Memoization"
echo "--------------------"

# A function to calculate factorials
proc factorial(n: int): int =
  echo fmt"Computing factorial({n})..."
  if n <= 1: 1
  else: n * factorial(n-1)

# Create a memoized version
let memoizedFactorial = memoize(factorial)

echo "Standard factorial calls:"
echo "factorial(5) = ", factorial(5)
echo "factorial(5) again = ", factorial(5)  # Will recompute

echo "\nMemoized factorial calls:"
echo "memoizedFactorial(5) = ", memoizedFactorial(5)
echo "memoizedFactorial(5) again = ", memoizedFactorial(5)  # Uses cached result

echo "\nComputing factorial(6) with memoization:"
echo "memoizedFactorial(6) = ", memoizedFactorial(6)  # Will reuse some computations
echo ""

# Example 4: Lazy data processing pipeline
# ---------------------------------------------------------

echo "Example 4: Lazy Processing Pipeline"
echo "--------------------------------"

# Create a sequence of numbers
let numbers = naturals()

# Build a processing pipeline - all these operations are lazy
let pipeline = numbers
  .map(proc(x: int): int = x * x)                      # Square each number
  .filter(proc(x: int): bool = x mod 3 == 0)           # Keep only those divisible by 3
  .map(proc(x: int): string = "Result: " & $x)         # Convert to strings
  
# Only when we take elements is any processing done
let results = take(pipeline, 5)

echo "Results from lazy pipeline:"
for i, result in results:
  echo fmt"  [{i+1}] {result}"
echo ""

# Example 5: Performance comparison
# ---------------------------------------------------------

echo "Example 5: Performance Comparison"
echo "------------------------------"

# Create a sequence for eager evaluation
var eagerSeq = (0..1_000_000).toSeq()

# Measure time for eager computation
let t1 = cpuTime()
discard eagerSeq
  .map(proc(x: int): int = x * x)
  .filter(proc(x: int): bool = x mod 10 == 0)
  .map(proc(x: int): int = x div 10)
let eagerTime = cpuTime() - t1

# Create a lazy sequence for the same computation
let lazySeq = naturals()

# Measure time for lazy computation (only computing what we need)
let t2 = cpuTime()
discard lazySeq
  .map(proc(x: int): int = x * x)
  .filter(proc(x: int): bool = x mod 10 == 0)
  .map(proc(x: int): int = x div 10)
  # We only need the first 10 results
  .take(10)
let lazyTime = cpuTime() - t2

echo fmt"Time for eager evaluation (processing 1,000,000 elements): {eagerTime:.6f} seconds"
echo fmt"Time for lazy evaluation (only computing what we need): {lazyTime:.6f} seconds"
echo fmt"Lazy evaluation was {eagerTime/lazyTime:.1f}x faster"