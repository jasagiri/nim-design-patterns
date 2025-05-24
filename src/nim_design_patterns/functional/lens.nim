## Lens Pattern
## 
## A lens is a functional programming construct which can be thought of as a 
## composable pair of getter and setter functions.
##
## Lenses allow you to abstract field access and modification for nested data structures, 
## and make it easy to create transformations that change deeply nested data in a 
## purely functional way (without mutating the original data structure).
##
## This implementation provides:
## * Basic lenses for object field access
## * Lens composition
## * Optional lenses for nilable references
## * Helper functions for working with collections

import options
import sugar
import sequtils

# Define a generic Lens type
type
  Lens*[S, A] = object
    ## A lens focusing on a value of type A within a structure of type S
    getter*: proc(s: S): A {.closure.}
    setter*: proc(s: S, a: A): S {.closure.}

# Create a lens
proc lens*[S, A](getter: proc(s: S): A, setter: proc(s: S, a: A): S): Lens[S, A] =
  ## Create a lens from a getter and setter function
  Lens[S, A](getter: getter, setter: setter)

# Get a value through a lens
proc get*[S, A](l: Lens[S, A], s: S): A =
  ## Get the focused value from the structure
  l.getter(s)

# Set a value through a lens
proc set*[S, A](l: Lens[S, A], s: S, a: A): S =
  ## Set the focused value in the structure, returning a new structure
  l.setter(s, a)

# Modify a value through a lens
proc modify*[S, A](l: Lens[S, A], s: S, f: proc(a: A): A): S =
  ## Modify the focused value using a function, returning a new structure
  let a = l.get(s)
  l.set(s, f(a))

# Method syntax for a more fluent API
proc modify*[A, B](s: A, l: Lens[A, B], f: proc(b: B): B): A =
  ## Method syntax version of modify for a more fluent API
  l.modify(s, f)

# Composition of lenses
proc compose*[S, A, B](outer: Lens[S, A], inner: Lens[A, B]): Lens[S, B] =
  ## Compose two lenses to create a lens that focuses deeper into a structure
  lens[S, B](
    getter = (s: S) => inner.get(outer.get(s)),
    setter = (s: S, b: B) => outer.set(s, inner.set(outer.get(s), b))
  )

# Optional lens for safely working with nil references
proc optional*[S, A, B](outerLens: Lens[S, A], innerLens: Lens[A, B]): Lens[S, Option[B]] =
  ## Create an optional lens for safely handling nilable references
  lens[S, Option[B]](
    getter = proc(s: S): Option[B] =
      let a = outerLens.get(s)
      if a.isNil:
        return none(B)
      return some(innerLens.get(a))
    ,
    setter = proc(s: S, ob: Option[B]): S =
      if ob.isNone:
        return s
      let a = outerLens.get(s)
      if a.isNil:
        return s
      let newA = innerLens.set(a, ob.get)
      return outerLens.set(s, newA)
  )

# Helper function to create a field lens
proc field*[T, F](name: string, get: proc(obj: T): F, set: proc(obj: T, val: F): T): Lens[T, F] =
  ## Create a lens for a field in an object
  lens[T, F](get, set)

# Create a lens for an index in a sequence
proc at*[T](idx: int): Lens[seq[T], T] =
  ## Create a lens focusing on an element in a sequence at the given index
  lens[seq[T], T](
    getter = proc(s: seq[T]): T = s[idx],
    setter = proc(s: seq[T], v: T): seq[T] =
      var newSeq = s
      newSeq[idx] = v
      newSeq
  )

# Apply a lens transformation to each element in a sequence
proc mapLens*[S, A](lens: Lens[S, A], f: proc(a: A): A): proc(s: seq[S]): seq[S] =
  ## Create a function that applies a lens transformation to each element in a sequence
  return proc(s: seq[S]): seq[S] =
    s.map(proc(item: S): S = lens.modify(item, f))