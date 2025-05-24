## Monad Pattern implementation for Nim
##
## Monads are a design pattern that allows chaining operations on wrapped values without
## unwrapping them in between. They are fundamental to functional programming languages
## and help manage side effects, state transformations, and error handling in a pure way.
##
## This implementation provides:
## - A Maybe monad for handling optional values
## - A Result monad for error handling
## - A State monad for managing state transformations
## - Utility functions for working with monads
## - Techniques for composing monads

import std/[options, sugar]
import ../core/base

# ---------------------------------------------------------------------------
# Maybe Monad
# ---------------------------------------------------------------------------

type Maybe*[T] = Option[T]

proc just*[T](value: T): Maybe[T] =
  ## Create a Maybe that contains a value
  some(value)

proc nothing*[T](): Maybe[T] =
  ## Create an empty Maybe
  none(T)

proc map*[T, U](m: Maybe[T], f: proc(x: T): U): Maybe[U] =
  ## Apply a function to the value inside a Maybe if it exists
  if m.isSome:
    just(f(m.get))
  else:
    nothing[U]()

proc flatMap*[T, U](m: Maybe[T], f: proc(x: T): Maybe[U]): Maybe[U] =
  ## Apply a function that returns a Maybe to a Maybe value
  ## (also known as bind or chain)
  if m.isSome:
    f(m.get)
  else:
    nothing[U]()

proc filter*[T](m: Maybe[T], predicate: proc(x: T): bool): Maybe[T] =
  ## Filter a Maybe value, keeping it only if it satisfies a predicate
  if m.isSome and predicate(m.get):
    m
  else:
    nothing[T]()

proc getOrElse*[T](m: Maybe[T], default: T): T =
  ## Extract the value from a Maybe or return a default if it's empty
  if m.isSome:
    m.get
  else:
    default

# ---------------------------------------------------------------------------
# Result Monad
# ---------------------------------------------------------------------------

type
  Result*[T, E] = object
    ## Result monad for handling operations that might succeed or fail
    case isSuccess*: bool
    of true:
      value*: T
    of false:
      error*: E

proc success*[T, E](value: T): Result[T, E] =
  ## Create a successful Result
  Result[T, E](isSuccess: true, value: value)

proc failure*[T, E](error: E): Result[T, E] =
  ## Create a failed Result
  Result[T, E](isSuccess: false, error: error)

proc map*[T, E, U](r: Result[T, E], f: proc(x: T): U): Result[U, E] =
  ## Apply a function to the success value of a Result
  if r.isSuccess:
    success[U, E](f(r.value))
  else:
    failure[U, E](r.error)

proc flatMap*[T, E, U](r: Result[T, E], f: proc(x: T): Result[U, E]): Result[U, E] =
  ## Apply a function that returns a Result to a Result value
  if r.isSuccess:
    f(r.value)
  else:
    failure[U, E](r.error)

proc mapError*[T, E, F](r: Result[T, E], f: proc(e: E): F): Result[T, F] =
  ## Transform the error value of a Result
  if r.isSuccess:
    success[T, F](r.value)
  else:
    failure[T, F](f(r.error))

proc getOrElse*[T, E](r: Result[T, E], default: T): T =
  ## Extract the value from a Result or return a default if it's a failure
  if r.isSuccess:
    r.value
  else:
    default

proc fold*[T, E, U](r: Result[T, E], onSuccess: proc(v: T): U, onFailure: proc(e: E): U): U =
  ## Handle both success and failure cases of a Result
  if r.isSuccess:
    onSuccess(r.value)
  else:
    onFailure(r.error)

# ---------------------------------------------------------------------------
# State Monad
# ---------------------------------------------------------------------------

type
  StateFunc*[S, A] = proc(s: S): tuple[value: A, state: S]
  State*[S, A] = object
    ## State monad for tracking state through computations
    run*: StateFunc[S, A]

proc state*[S, A](f: StateFunc[S, A]): State[S, A] =
  ## Create a new State monad
  State[S, A](run: f)

proc runState*[S, A](s: State[S, A], initialState: S): tuple[value: A, state: S] =
  ## Execute a State computation with the given initial state
  s.run(initialState)

proc evalState*[S, A](s: State[S, A], initialState: S): A =
  ## Execute a State computation and return only the result value
  s.run(initialState).value

proc execState*[S, A](s: State[S, A], initialState: S): S =
  ## Execute a State computation and return only the final state
  s.run(initialState).state

proc map*[S, A, B](s: State[S, A], f: proc(a: A): B): State[S, B] =
  ## Apply a function to the value inside a State
  state(proc(state: S): tuple[value: B, state: S] =
    let (a, newState) = s.run(state)
    (f(a), newState)
  )

proc flatMap*[S, A, B](s: State[S, A], f: proc(a: A): State[S, B]): State[S, B] =
  ## Apply a function that returns a State to a State
  state(proc(state: S): tuple[value: B, state: S] =
    let (a, intermediateState) = s.run(state)
    f(a).run(intermediateState)
  )

type EmptyType* = tuple[]  # Empty type for void operations

proc modify*[S](f: proc(s: S): S): State[S, EmptyType] =
  ## Create a State that modifies the state and returns no value
  state(proc(s: S): tuple[value: EmptyType, state: S] =
    ((), f(s))
  )

proc get*[S](): State[S, S] =
  ## Create a State that returns the current state as the value
  state(proc(s: S): tuple[value: S, state: S] =
    (s, s)
  )

proc put*[S](newState: S): State[S, EmptyType] =
  ## Create a State that replaces the state and returns no value
  state(proc(s: S): tuple[value: EmptyType, state: S] =
    ((), newState)
  )

# ---------------------------------------------------------------------------
# MonadPattern object for framework integration
# ---------------------------------------------------------------------------

type MonadPattern* = ref object of Pattern

proc newMonadPattern*(): MonadPattern =
  MonadPattern(
    name: "Monad",
    kind: pkFunctional,
    description: "A design pattern that allows sequencing operations while passing context"
  )

# ---------------------------------------------------------------------------
# Utility functions for monadic composition
# ---------------------------------------------------------------------------

proc flatten*[T](mm: Maybe[Maybe[T]]): Maybe[T] =
  ## Flatten a nested Maybe
  mm.flatMap(proc(m: Maybe[T]): Maybe[T] = m)

proc flatten*[T, E](rr: Result[Result[T, E], E]): Result[T, E] =
  ## Flatten a nested Result
  rr.flatMap(proc(r: Result[T, E]): Result[T, E] = r)

proc traverse*[T, U](list: seq[T], f: proc(x: T): Maybe[U]): Maybe[seq[U]] =
  ## Apply a function that returns a Maybe to a sequence, collecting the results
  ## Returns Nothing if any application returns Nothing
  var results: seq[U] = @[]
  for item in list:
    let maybeResult = f(item)
    if maybeResult.isNone:
      return nothing[seq[U]]()
    results.add(maybeResult.get)
  return just(results)

proc traverse*[T, U, E](list: seq[T], f: proc(x: T): Result[U, E]): Result[seq[U], E] =
  ## Apply a function that returns a Result to a sequence, collecting the results
  ## Returns the first failure if any application fails
  var results: seq[U] = @[]
  for item in list:
    let result = f(item)
    if not result.isSuccess:
      return failure[seq[U], E](result.error)
    results.add(result.value)
  return success[seq[U], E](results)

# ---------------------------------------------------------------------------
# Example monadic combinators (similar to do-notation in Haskell)
# ---------------------------------------------------------------------------

template withMaybe*[T, U](m: Maybe[T], id, body: untyped): Maybe[U] =
  ## A template to simplify working with Maybe values
  if m.isNone:
    nothing[U]()
  else:
    let id {.inject.} = m.get
    body

template withResult*[T, E, U](r: Result[T, E], id, body: untyped): Result[U, E] =
  ## A template to simplify working with Result values
  if not r.isSuccess:
    failure[U, E](r.error)
  else:
    let id {.inject.} = r.value
    body