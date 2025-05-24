## Lazy Evaluation Pattern implementation for Nim
##
## Lazy evaluation is a strategy where expressions are not evaluated until their
## values are actually needed. This can improve performance by avoiding
## unnecessary calculations and enables working with potentially infinite data structures.
##
## This implementation provides:
## - A generic Lazy[T] type for delayed computation
## - Utilities for creating and working with lazy values
## - Support for lazy sequences and streams
## - Memoization to avoid redundant calculations

import ../core/base
import std/tables

type LazyPattern* = ref object of Pattern

proc newLazyPattern*(): LazyPattern =
  LazyPattern(
    name: "Lazy Evaluation",
    kind: pkFunctional,
    description: "A pattern that delays computation until results are needed"
  )

# ---------------------------------------------------------------------------
# Basic Lazy type
# ---------------------------------------------------------------------------

type
  Lazy*[T] = ref object
    ## A container for a value that will be computed on demand
    memoized: bool
    computed: bool
    value: T
    producer: proc(): T

proc lazy*[T](producer: proc(): T): Lazy[T] =
  ## Create a lazy value that will be computed when needed
  Lazy[T](
    memoized: true,
    computed: false,
    producer: producer
  )

proc lazyNoMemo*[T](producer: proc(): T): Lazy[T] =
  ## Create a lazy value that will be recomputed every time it's accessed
  Lazy[T](
    memoized: false,
    computed: false,
    producer: producer
  )

proc force*[T](l: Lazy[T]): T =
  ## Force the evaluation of a lazy value and return the result
  if not l.computed and l.memoized:
    l.value = l.producer()
    l.computed = true
    return l.value
  elif not l.memoized:
    return l.producer()
  else:
    return l.value

proc isComputed*[T](l: Lazy[T]): bool =
  ## Check if a lazy value has already been computed
  l.computed

proc map*[T, U](l: Lazy[T], f: proc(x: T): U): Lazy[U] =
  ## Transform a lazy value with a function, preserving laziness
  lazy(proc(): U = f(force(l)))

proc flatMap*[T, U](l: Lazy[T], f: proc(x: T): Lazy[U]): Lazy[U] =
  ## Chain lazy computations together
  lazy(proc(): U = force(f(force(l))))

proc zip*[T, U](a: Lazy[T], b: Lazy[U]): Lazy[(T, U)] =
  ## Combine two lazy values into a tuple, preserving laziness
  lazy(proc(): (T, U) = (force(a), force(b)))

# ---------------------------------------------------------------------------
# Lazy Sequences
# ---------------------------------------------------------------------------

type
  LazySeq*[T] = ref object
    ## A lazy sequence that computes elements on demand
    case isEmpty*: bool
    of true: discard
    of false:
      head*: Lazy[T]
      tail*: Lazy[LazySeq[T]]

proc emptyLazySeq*[T](): LazySeq[T] =
  ## Create an empty lazy sequence
  LazySeq[T](isEmpty: true)

proc cons*[T](head: Lazy[T], tail: Lazy[LazySeq[T]]): LazySeq[T] =
  ## Construct a lazy sequence with a head and tail
  LazySeq[T](isEmpty: false, head: head, tail: tail)

proc lazySeq*[T](head: T, tail: LazySeq[T]): LazySeq[T] =
  ## Helper to create a lazy sequence from a value and another sequence
  cons(lazy(proc(): T = head), lazy(proc(): LazySeq[T] = tail))

proc lazySeqFromProc*[T](producer: proc(index: int): T): LazySeq[T] =
  ## Create an infinite lazy sequence from an index-based generator function
  
  proc buildSeq(n: int): LazySeq[T] =
    lazySeq(producer(n), buildSeq(n + 1))
  
  buildSeq(0)

proc take*[T](seq: LazySeq[T], n: int): seq[T] =
  ## Take first n elements from a lazy sequence and return as a regular sequence
  if n <= 0 or seq.isEmpty:
    return @[]
  
  var elements: seq[T] = @[]
  var current = seq
  var count = n
  
  while count > 0 and not current.isEmpty:
    elements.add(force(current.head))
    current = force(current.tail)
    count -= 1
    
  elements

proc filter*[T](seq: LazySeq[T], predicate: proc(x: T): bool): LazySeq[T] =
  ## Filter a lazy sequence lazily
  if seq.isEmpty:
    return emptyLazySeq[T]()
    
  let headValue = force(seq.head)
  let tailLazy = force(seq.tail)
  
  if predicate(headValue):
    return lazySeq(headValue, filter(tailLazy, predicate))
  else:
    return filter(tailLazy, predicate)

proc map*[T, U](seq: LazySeq[T], f: proc(x: T): U): LazySeq[U] =
  ## Transform a lazy sequence lazily
  if seq.isEmpty:
    return emptyLazySeq[U]()
    
  lazySeq(f(force(seq.head)), map(force(seq.tail), f))

# ---------------------------------------------------------------------------
# Memoization utility
# ---------------------------------------------------------------------------

proc memoize*[T, U](f: proc(x: T): U): proc(x: T): U =
  ## Create a memoized version of a function that caches results
  var cache = newTable[T, U]()
  
  result = proc(x: T): U =
    if x in cache:
      return cache[x]
    else:
      let value = f(x)
      cache[x] = value
      return value

# Example implementation for functions with multiple arguments
proc memoize2*[T, U, V](f: proc(x: T, y: U): V): proc(x: T, y: U): V =
  ## Create a memoized version of a two-argument function
  var cache = newTable[(T, U), V]()
  
  result = proc(x: T, y: U): V =
    let key = (x, y)
    if key in cache:
      return cache[key]
    else:
      let value = f(x, y)
      cache[key] = value
      return value

# ---------------------------------------------------------------------------
# Common lazy sequences
# ---------------------------------------------------------------------------

proc naturals*(): LazySeq[int] =
  ## Create a lazy sequence of natural numbers (0, 1, 2, ...)
  lazySeqFromProc(proc(i: int): int = i)

proc fibonacci*(): LazySeq[int] =
  ## Create a lazy sequence of Fibonacci numbers (0, 1, 1, 2, 3, 5, ...)
  
  # Better implementation using memoization
  var memo = newTable[int, int]()
  memo[0] = 0
  memo[1] = 1
  
  proc fib(n: int): int =
    if n in memo:
      return memo[n]
    
    result = fib(n-1) + fib(n-2)
    memo[n] = result
  
  lazySeqFromProc(proc(i: int): int = fib(i))

proc primes*(): LazySeq[int] =
  ## Create a lazy sequence of prime numbers (2, 3, 5, 7, 11, ...)
  
  # More efficient prime generator that doesn't recompute for each new prime
  var knownPrimes: seq[int] = @[2, 3]
  
  proc isPrime(n: int): bool =
    # Check against known primes first
    for p in knownPrimes:
      if p * p > n:  # We've checked all possible factors
        return true
      if n mod p == 0:
        return false
    return true
  
  proc genPrimes(n: int): int =
    if n < knownPrimes.len:
      return knownPrimes[n]
    
    # Find the next prime
    var candidate = knownPrimes[^1] + 2  # Start from the last known prime + 2
    while not isPrime(candidate):
      candidate += 2  # Only check odd numbers
    
    # Add to our known primes list
    knownPrimes.add(candidate)
    return candidate
  
  lazySeqFromProc(genPrimes)