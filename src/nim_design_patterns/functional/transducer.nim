## Transducer Pattern implementation for Nim
##
## Transducers are composable algorithmic transformations that are decoupled from their 
## input and output sources. They can be composed together to form efficient data transformation
## pipelines that avoid creating intermediate collections.
##
## This implementation provides:
## - Core transducer types and operations
## - Common transducers (map, filter, take, etc.)
## - Transducible contexts (sequences, tables, etc.)
## - Composition of transducers
## - Efficient reduction operations

import ../core/base
import std/[tables, options, sugar, sets]

type TransducerPattern* = ref object of Pattern

proc newTransducerPattern*(): TransducerPattern =
  TransducerPattern(
    name: "Transducer",
    kind: pkFunctional,
    description: "A pattern for composable algorithmic transformations that are independent of input/output context"
  )

# ---------------------------------------------------------------------------
# Core transducer types
# ---------------------------------------------------------------------------

type
  # The reducing function type: takes an accumulated result and a new input,
  # returns the next accumulated result
  ReducingFunction*[R, E] = proc(acc: R, input: E): R {.closure.}

  # A transducer transforms a reducing function into another reducing function
  Transducer*[R, A, B] = proc(rf: ReducingFunction[R, B]): ReducingFunction[R, A]

# Identity transducer - passes through values unchanged
proc identity*[R, E](): Transducer[R, E, E] =
  return proc(rf: ReducingFunction[R, E]): ReducingFunction[R, E] =
    return proc(acc: R, input: E): R {.closure.} =
      return rf(acc, input)

# ---------------------------------------------------------------------------
# Core transducer operations
# ---------------------------------------------------------------------------

# Compose two transducers
proc compose*[R, A, B, C](t1: Transducer[R, B, C], t2: Transducer[R, A, B]): Transducer[R, A, C] =
  return proc(rf: ReducingFunction[R, C]): ReducingFunction[R, A] =
    let step = t1(rf)
    return t2(step)

# Transduce: apply a transducer to a collection with a reducer and initial value
proc transduce*[R, A, B, Coll](
  xform: Transducer[R, A, B],
  reducing: ReducingFunction[R, B],
  init: R,
  coll: Coll
): R =
  var acc = init
  let step = xform(reducing)
  
  # Handle different collection types
  when Coll is seq:
    for item in coll:
      acc = step(acc, item)
  elif Coll is Table:
    for k, v in coll:
      # For tables, we transform the key-value pairs as tuples
      acc = step(acc, (k, v))
  else:
    # Default case for other iterables
    for item in coll:
      acc = step(acc, item)
  
  return acc

# ---------------------------------------------------------------------------
# Common transducers
# ---------------------------------------------------------------------------

# Map transducer
proc map*[R, A, B](f: proc(x: A): B): Transducer[R, A, B] =
  return proc(rf: ReducingFunction[R, B]): ReducingFunction[R, A] =
    return proc(acc: R, input: A): R {.closure.} =
      return rf(acc, f(input))

# Filter transducer
proc filter*[R, E](predicate: proc(x: E): bool): Transducer[R, E, E] =
  return proc(rf: ReducingFunction[R, E]): ReducingFunction[R, E] =
    return proc(acc: R, input: E): R {.closure.} =
      if predicate(input):
        return rf(acc, input)
      else:
        return acc

# Take transducer
proc take*[R, E](n: int): Transducer[R, E, E] =
  return proc(rf: ReducingFunction[R, E]): ReducingFunction[R, E] =
    var count = 0
    return proc(acc: R, input: E): R {.closure.} =
      if count < n:
        count += 1
        return rf(acc, input)
      else:
        return acc

# Drop transducer
proc drop*[R, E](n: int): Transducer[R, E, E] =
  return proc(rf: ReducingFunction[R, E]): ReducingFunction[R, E] =
    var count = 0
    return proc(acc: R, input: E): R {.closure.} =
      if count < n:
        count += 1
        return acc
      else:
        return rf(acc, input)

# TakeWhile transducer
proc takeWhile*[R, E](predicate: proc(x: E): bool): Transducer[R, E, E] =
  return proc(rf: ReducingFunction[R, E]): ReducingFunction[R, E] =
    var taking = true
    return proc(acc: R, input: E): R {.closure.} =
      if taking and predicate(input):
        return rf(acc, input)
      else:
        taking = false
        return acc

# DropWhile transducer
proc dropWhile*[R, E](predicate: proc(x: E): bool): Transducer[R, E, E] =
  return proc(rf: ReducingFunction[R, E]): ReducingFunction[R, E] =
    var dropping = true
    return proc(acc: R, input: E): R {.closure.} =
      if dropping and predicate(input):
        return acc
      else:
        dropping = false
        return rf(acc, input)

# Deduplicate transducer
proc deduplicate*[R, E](h: HashSet[E] = initHashSet[E]()): Transducer[R, E, E] =
  return proc(rf: ReducingFunction[R, E]): ReducingFunction[R, E] =
    var seen = h
    return proc(acc: R, input: E): R {.closure.} =
      if input in seen:
        return acc
      else:
        seen.incl(input)
        return rf(acc, input)

# FlatMap transducer
proc flatMap*[R, A, B](f: proc(x: A): seq[B]): Transducer[R, A, B] =
  return proc(rf: ReducingFunction[R, B]): ReducingFunction[R, A] =
    return proc(acc: R, input: A): R {.closure.} =
      var result = acc
      for item in f(input):
        result = rf(result, item)
      return result

# ---------------------------------------------------------------------------
# Common reducers
# ---------------------------------------------------------------------------

# Collecting reducer (builds a sequence)
proc collectingReducer*[E](): ReducingFunction[seq[E], E] =
  return proc(acc: seq[E], input: E): seq[E] {.closure.} =
    var copy = acc
    copy.add(input)
    return copy

# Summing reducer
proc summingReducer*(): ReducingFunction[int, int] =
  return proc(acc: int, input: int): int {.closure.} =
    return acc + input

# Counting reducer
proc countingReducer*[E](): ReducingFunction[int, E] =
  return proc(acc: int, input: E): int {.closure.} =
    return acc + 1

# Joining reducer (builds a string)
proc joiningReducer*(separator: string = ""): ReducingFunction[string, string] =
  return proc(acc: string, input: string): string {.closure.} =
    if acc.len == 0:
      return input
    else:
      return acc & separator & input

# First element reducer (gets the first element)
proc firstReducer*[E](): ReducingFunction[Option[E], E] =
  return proc(acc: Option[E], input: E): Option[E] {.closure.} =
    if acc.isNone:
      return some(input)
    else:
      return acc

# Last element reducer (gets the last element)
proc lastReducer*[E](): ReducingFunction[Option[E], E] =
  return proc(acc: Option[E], input: E): Option[E] {.closure.} =
    return some(input)

# ---------------------------------------------------------------------------
# Helper functions for sequences
# ---------------------------------------------------------------------------

# Apply a transducer to a sequence and collect the results
proc into*[A, B](
  coll: seq[A],
  xform: Transducer[seq[B], A, B]
): seq[B] =
  return transduce(xform, collectingReducer[B](), @[], coll)

# Apply a transducer to a sequence and reduce with a custom reducer
proc transform*[R, A, B](
  coll: seq[A],
  xform: Transducer[R, A, B],
  reducing: ReducingFunction[R, B],
  init: R
): R =
  return transduce(xform, reducing, init, coll)

# Create a transducer that combines several transducers
proc comp*[R, A, B, C](t1: Transducer[R, B, C], t2: Transducer[R, A, B]): Transducer[R, A, C] =
  return compose(t1, t2)

proc comp*[R, A, B, C, D](
  t1: Transducer[R, C, D],
  t2: Transducer[R, B, C],
  t3: Transducer[R, A, B]
): Transducer[R, A, D] =
  return compose(t1, compose(t2, t3))

proc comp*[R, A, B, C, D, E](
  t1: Transducer[R, D, E],
  t2: Transducer[R, C, D],
  t3: Transducer[R, B, C],
  t4: Transducer[R, A, B]
): Transducer[R, A, E] =
  return compose(t1, compose(t2, compose(t3, t4)))

# ---------------------------------------------------------------------------
# Stateful transducers
# ---------------------------------------------------------------------------

# Windowed transducer - creates windows of size n
proc windowed*[R, E](size: int): Transducer[R, E, seq[E]] =
  return proc(rf: ReducingFunction[R, seq[E]]): ReducingFunction[R, E] =
    var window: seq[E] = @[]
    return proc(acc: R, input: E): R {.closure.} =
      window.add(input)
      if window.len > size:
        window.delete(0)
      
      if window.len == size:
        # Create a copy of the window to avoid it being mutated
        var windowCopy = window
        return rf(acc, windowCopy)
      else:
        return acc

# Indexed transducer - adds index information
proc indexed*[R, E](): Transducer[R, E, (int, E)] =
  return proc(rf: ReducingFunction[R, (int, E)]): ReducingFunction[R, E] =
    var idx = 0
    return proc(acc: R, input: E): R {.closure.} =
      let res = rf(acc, (idx, input))
      idx += 1
      return res

# Partition transducer - groups elements into chunks of size n
proc partition*[R, E](size: int): Transducer[R, E, seq[E]] =
  return proc(rf: ReducingFunction[R, seq[E]]): ReducingFunction[R, E] =
    var buffer: seq[E] = @[]
    return proc(acc: R, input: E): R {.closure.} =
      buffer.add(input)
      
      if buffer.len >= size:
        let chunk = buffer
        buffer = @[]
        return rf(acc, chunk)
      else:
        return acc