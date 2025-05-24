## Function Composition pattern implementation for Nim
##
## Function composition is a fundamental functional programming pattern that
## allows building complex functions by combining simpler ones. This enables
## a pipeline-style approach to data processing.
##
## This implementation provides:
## - Basic function composition
## - Partial application
## - Currying and uncurrying functions
## - Point-free style programming techniques
## - Pipeline operators for readable data transformation

import std/[sugar, macros]
import ../core/base

type CompositionPattern* = ref object of Pattern

proc newCompositionPattern*(): CompositionPattern =
  CompositionPattern(
    name: "FunctionComposition",
    kind: pkFunctional,
    description: "A pattern that combines functions to create data transformation pipelines"
  )

# ---------------------------------------------------------------------------
# Basic function composition
# ---------------------------------------------------------------------------

proc compose*[A, B, C](f: proc(b: B): C, g: proc(a: A): B): proc(a: A): C =
  ## Compose two functions: (f ∘ g)(x) = f(g(x))
  ## The result is a new function that applies g first, then f
  result = proc(a: A): C = f(g(a))

proc pipe*[A, B, C](g: proc(a: A): B, f: proc(b: B): C): proc(a: A): C =
  ## Pipe two functions: (g |> f)(x) = f(g(x))
  ## Same as compose but with arguments reversed for left-to-right reading
  compose(f, g)

# ---------------------------------------------------------------------------
# Partial application
# ---------------------------------------------------------------------------

proc partial1*[A, B, C](f: proc(a: A, b: B): C, a: A): proc(b: B): C =
  ## Partially apply first argument of a two-argument function
  result = proc(b: B): C = f(a, b)

proc partial2*[A, B, C](f: proc(a: A, b: B): C, b: B): proc(a: A): C =
  ## Partially apply second argument of a two-argument function
  result = proc(a: A): C = f(a, b)

# ---------------------------------------------------------------------------
# Currying and uncurrying
# ---------------------------------------------------------------------------

proc curry*[A, B, C](f: proc(a: A, b: B): C): proc(a: A): proc(b: B): C =
  ## Transform a function of two arguments into a function of one argument
  ## that returns a function of one argument
  result = proc(a: A): proc(b: B): C =
    proc(b: B): C = f(a, b)

proc uncurry*[A, B, C](f: proc(a: A): proc(b: B): C): proc(a: A, b: B): C =
  ## Transform a curried function back to a function of two arguments
  result = proc(a: A, b: B): C = f(a)(b)

# ---------------------------------------------------------------------------
# Higher-order functions
# ---------------------------------------------------------------------------

proc flip*[A, B, C](f: proc(a: A, b: B): C): proc(b: B, a: A): C =
  ## Flip the order of arguments of a two-argument function
  result = proc(b: B, a: A): C = f(a, b)

proc constant*[A, B](a: A): proc(b: B): A =
  ## Create a function that always returns the same value, ignoring its argument
  result = proc(b: B): A = a

proc identity*[T](x: T): T =
  ## The identity function that returns its argument unchanged
  x

# ---------------------------------------------------------------------------
# Function combinators
# ---------------------------------------------------------------------------

proc chain*[T](fs: varargs[proc(x: T): T {.closure.}]): proc(x: T): T {.closure.} =
  ## Chain multiple functions of the same type
  ## Applies each function in sequence to the result of the previous function
  result = proc(x: T): T =
    var res = x
    for f in fs:
      res = f(res)
    res

proc all*[T](predicates: varargs[proc(x: T): bool {.closure.}]): proc(x: T): bool {.closure.} =
  ## Create a function that returns true only if all predicates return true
  result = proc(x: T): bool =
    for p in predicates:
      if not p(x):
        return false
    true

proc any*[T](predicates: varargs[proc(x: T): bool {.closure.}]): proc(x: T): bool {.closure.} =
  ## Create a function that returns true if any predicate returns true
  result = proc(x: T): bool =
    for p in predicates:
      if p(x):
        return true
    false

proc negate*[T](predicate: proc(x: T): bool): proc(x: T): bool =
  ## Create a function that returns the negation of the given predicate
  result = proc(x: T): bool = not predicate(x)

# ---------------------------------------------------------------------------
# Pipeline operators
# ---------------------------------------------------------------------------

macro `|>`*(x: untyped, f: untyped): untyped =
  ## Pipeline operator: x |> f becomes f(x)
  ## Allows for left-to-right function application
  if f.kind == nnkCall:
    # If f is already a call, insert x as the first argument
    result = newCall(f[0])
    result.add(x)
    for i in 1 ..< f.len:
      result.add(f[i])
  else:
    # Otherwise just call f with x
    result = newCall(f, x)

macro `|>>`*[A, B, C](g: proc(a: A): B, f: proc(b: B): C): untyped =
  ## Function composition operator: g |>> f becomes compose(f, g)
  ## Creates a new function that applies g first, then f
  quote do:
    compose(`f`, `g`)

# ---------------------------------------------------------------------------
# Utility functions for common operations
# ---------------------------------------------------------------------------

proc map*[T, U](f: proc(x: T): U): proc(xs: seq[T]): seq[U] =
  ## Create a function that maps f over a sequence
  result = proc(xs: seq[T]): seq[U] =
    var res: seq[U] = @[]
    for x in xs:
      res.add(f(x))
    res

proc filter*[T](predicate: proc(x: T): bool): proc(xs: seq[T]): seq[T] =
  ## Create a function that filters a sequence using a predicate
  result = proc(xs: seq[T]): seq[T] =
    var res: seq[T] = @[]
    for x in xs:
      if predicate(x):
        res.add(x)
    res

proc reduce*[T, U](f: proc(acc: U, x: T): U, initial: U): proc(xs: seq[T]): U =
  ## Create a function that reduces a sequence using f and an initial value
  result = proc(xs: seq[T]): U =
    var acc = initial
    for x in xs:
      acc = f(acc, x)
    acc

# ---------------------------------------------------------------------------
# Examples of point-free style programming
# ---------------------------------------------------------------------------

proc isEven*(x: int): bool = x mod 2 == 0

let 
  # Using compose to create point-free functions
  doubleIt = (x: int) => x * 2
  incrementIt = (x: int) => x + 1
  doubleAndIncrement = compose(incrementIt, doubleIt)
  incrementAndDouble = compose(doubleIt, incrementIt)
  
  # Using pipeline operators for data transformations
  isOdd = negate(isEven)
  getEvenNumbers = filter(isEven)
  doubleAll = map(doubleIt)
  sumAll = reduce((acc: int, x: int) => acc + x, 0)
  
  # Fully point-free data pipeline
  sumOfDoubledEvens = getEvenNumbers |>> doubleAll |>> sumAll