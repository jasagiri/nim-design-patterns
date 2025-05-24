## Immutability Pattern implementation for Nim
##
## Immutability is a core principle in functional programming where data structures
## once created cannot be modified. Instead, operations create new instances with
## the desired changes. This pattern enhances safety, especially in concurrent environments.
##
## This implementation provides:
## - Immutable data structures (lists, maps, sets)
## - Non-destructive update operations
## - Persistent data structures with structural sharing
## - Copy-on-write semantics

import std/[tables, sets]
import ../core/base

type ImmutabilityPattern* = ref object of Pattern

proc newImmutabilityPattern*(): ImmutabilityPattern =
  ImmutabilityPattern(
    name: "Immutability",
    kind: pkFunctional,
    description: "A pattern that uses immutable data structures for predictable state management"
  )

# ---------------------------------------------------------------------------
# Immutable List
# ---------------------------------------------------------------------------

type
  ImmutableList*[T] = ref object
    ## A persistent immutable linked list
    case isEmpty*: bool
    of true: discard
    of false:
      head*: T
      tail*: ImmutableList[T]

proc empty*[T](): ImmutableList[T] =
  ## Create an empty immutable list
  ImmutableList[T](isEmpty: true)

proc cons*[T](head: T, tail: ImmutableList[T]): ImmutableList[T] =
  ## Add an element to the front of an immutable list
  ImmutableList[T](isEmpty: false, head: head, tail: tail)

proc singleton*[T](value: T): ImmutableList[T] =
  ## Create an immutable list with a single element
  cons(value, empty[T]())

proc toSeq*[T](list: ImmutableList[T]): seq[T] =
  ## Convert an immutable list to a sequence
  var res: seq[T] = @[]
  var current = list
  while not current.isEmpty:
    res.add(current.head)
    current = current.tail
  res

proc fromSeq*[T](s: seq[T]): ImmutableList[T] =
  ## Create an immutable list from a sequence
  result = empty[T]()
  for i in countdown(s.len - 1, 0):
    result = cons(s[i], result)

proc map*[T, U](list: ImmutableList[T], f: proc(x: T): U): ImmutableList[U] =
  ## Apply a function to each element in an immutable list
  if list.isEmpty:
    empty[U]()
  else:
    cons(f(list.head), map(list.tail, f))

proc filter*[T](list: ImmutableList[T], predicate: proc(x: T): bool): ImmutableList[T] =
  ## Keep only elements that satisfy a predicate
  if list.isEmpty:
    empty[T]()
  else:
    if predicate(list.head):
      cons(list.head, filter(list.tail, predicate))
    else:
      filter(list.tail, predicate)

proc foldLeft*[T, U](list: ImmutableList[T], initial: U, f: proc(acc: U, x: T): U): U =
  ## Left fold (reduce) operation on an immutable list
  var acc = initial
  var current = list
  while not current.isEmpty:
    acc = f(acc, current.head)
    current = current.tail
  acc

proc foldRight*[T, U](list: ImmutableList[T], initial: U, f: proc(x: T, acc: U): U): U =
  ## Right fold operation on an immutable list
  if list.isEmpty:
    initial
  else:
    f(list.head, foldRight(list.tail, initial, f))

proc append*[T](a, b: ImmutableList[T]): ImmutableList[T] =
  ## Concatenate two immutable lists
  if a.isEmpty:
    b
  else:
    cons(a.head, append(a.tail, b))

proc reverse*[T](list: ImmutableList[T]): ImmutableList[T] =
  ## Reverse an immutable list
  var reversed = empty[T]()
  var current = list
  while not current.isEmpty:
    reversed = cons(current.head, reversed)
    current = current.tail
  reversed

proc take*[T](list: ImmutableList[T], n: int): ImmutableList[T] =
  ## Take the first n elements from an immutable list
  if n <= 0 or list.isEmpty:
    empty[T]()
  else:
    cons(list.head, take(list.tail, n-1))

proc drop*[T](list: ImmutableList[T], n: int): ImmutableList[T] =
  ## Drop the first n elements from an immutable list
  var current = list
  var count = n
  while count > 0 and not current.isEmpty:
    current = current.tail
    count -= 1
  current

# ---------------------------------------------------------------------------
# Immutable Map
# ---------------------------------------------------------------------------

type
  ImmutableMap*[K, V] = ref object
    ## A persistent immutable map implementation
    data: Table[K, V]

proc emptyMap*[K, V](): ImmutableMap[K, V] =
  ## Create an empty immutable map
  ImmutableMap[K, V](data: initTable[K, V]())

proc fromTable*[K, V](table: Table[K, V]): ImmutableMap[K, V] =
  ## Create an immutable map from a table
  var newTable = table
  ImmutableMap[K, V](data: newTable)

proc contains*[K, V](m: ImmutableMap[K, V], key: K): bool =
  ## Check if a key exists in the map
  m.data.hasKey(key)

proc get*[K, V](m: ImmutableMap[K, V], key: K): V =
  ## Get a value from the map (raises KeyError if not found)
  m.data[key]

proc getOrDefault*[K, V](m: ImmutableMap[K, V], key: K, default: V): V =
  ## Get a value from the map with a default if not found
  if m.data.hasKey(key):
    m.data[key]
  else:
    default

proc put*[K, V](m: ImmutableMap[K, V], key: K, value: V): ImmutableMap[K, V] =
  ## Create a new map with an added or updated key-value pair
  var newTable = m.data
  newTable[key] = value
  ImmutableMap[K, V](data: newTable)

proc delete*[K, V](m: ImmutableMap[K, V], key: K): ImmutableMap[K, V] =
  ## Create a new map with a key removed
  var newTable = m.data
  newTable.del(key)
  ImmutableMap[K, V](data: newTable)

proc toTable*[K, V](m: ImmutableMap[K, V]): Table[K, V] =
  ## Convert an immutable map to a table
  m.data

proc keys*[K, V](m: ImmutableMap[K, V]): seq[K] =
  ## Get all keys from the map
  var keySeq: seq[K] = @[]
  for k in m.data.keys:
    keySeq.add(k)
  keySeq

proc values*[K, V](m: ImmutableMap[K, V]): seq[V] =
  ## Get all values from the map
  var valueSeq: seq[V] = @[]
  for v in m.data.values:
    valueSeq.add(v)
  valueSeq

proc map*[K, V, U](m: ImmutableMap[K, V], f: proc(k: K, v: V): U): ImmutableMap[K, U] =
  ## Apply a function to each value in the map
  var newTable = initTable[K, U]()
  for k, v in m.data.pairs:
    newTable[k] = f(k, v)
  ImmutableMap[K, U](data: newTable)

proc filter*[K, V](m: ImmutableMap[K, V], predicate: proc(k: K, v: V): bool): ImmutableMap[K, V] =
  ## Keep only entries that satisfy a predicate
  var newTable = initTable[K, V]()
  for k, v in m.data.pairs:
    if predicate(k, v):
      newTable[k] = v
  ImmutableMap[K, V](data: newTable)

# ---------------------------------------------------------------------------
# Immutable Set
# ---------------------------------------------------------------------------

type
  ImmutableSet*[T] = ref object
    ## A persistent immutable set implementation
    data: HashSet[T]

proc emptySet*[T](): ImmutableSet[T] =
  ## Create an empty immutable set
  ImmutableSet[T](data: initHashSet[T]())

proc fromHashSet*[T](hashSet: HashSet[T]): ImmutableSet[T] =
  ## Create an immutable set from a hash set
  var newSet = hashSet
  ImmutableSet[T](data: newSet)

proc contains*[T](s: ImmutableSet[T], value: T): bool =
  ## Check if a value exists in the set
  s.data.contains(value)

proc add*[T](s: ImmutableSet[T], value: T): ImmutableSet[T] =
  ## Create a new set with an added value
  var newSet = s.data
  newSet.incl(value)
  ImmutableSet[T](data: newSet)

proc remove*[T](s: ImmutableSet[T], value: T): ImmutableSet[T] =
  ## Create a new set with a value removed
  var newSet = s.data
  newSet.excl(value)
  ImmutableSet[T](data: newSet)

proc toHashSet*[T](s: ImmutableSet[T]): HashSet[T] =
  ## Convert an immutable set to a hash set
  s.data

proc toSeq*[T](s: ImmutableSet[T]): seq[T] =
  ## Convert an immutable set to a sequence
  var itemSeq: seq[T] = @[]
  for item in s.data:
    itemSeq.add(item)
  itemSeq

proc union*[T](a, b: ImmutableSet[T]): ImmutableSet[T] =
  ## Union of two immutable sets
  var newSet = a.data
  for item in b.data:
    newSet.incl(item)
  ImmutableSet[T](data: newSet)

proc intersection*[T](a, b: ImmutableSet[T]): ImmutableSet[T] =
  ## Intersection of two immutable sets
  var newSet = initHashSet[T]()
  for item in a.data:
    if b.data.contains(item):
      newSet.incl(item)
  ImmutableSet[T](data: newSet)

proc difference*[T](a, b: ImmutableSet[T]): ImmutableSet[T] =
  ## Difference of two immutable sets (a - b)
  var newSet = a.data
  for item in b.data:
    newSet.excl(item)
  ImmutableSet[T](data: newSet)

proc map*[T, U](s: ImmutableSet[T], f: proc(x: T): U): ImmutableSet[U] =
  ## Apply a function to each element in the set
  var newSet = initHashSet[U]()
  for item in s.data:
    newSet.incl(f(item))
  ImmutableSet[U](data: newSet)

proc filter*[T](s: ImmutableSet[T], predicate: proc(x: T): bool): ImmutableSet[T] =
  ## Keep only elements that satisfy a predicate
  var newSet = initHashSet[T]()
  for item in s.data:
    if predicate(item):
      newSet.incl(item)
  ImmutableSet[T](data: newSet)

# ---------------------------------------------------------------------------
# Extensions for working with Nim's built-in immutable types
# ---------------------------------------------------------------------------

proc modify*[T](s: seq[T], index: int, newValue: T): seq[T] =
  ## Non-destructively modify a sequence at a specific index
  var newSeq = s
  newSeq[index] = newValue
  newSeq

proc insertAt*[T](s: seq[T], index: int, value: T): seq[T] =
  ## Non-destructively insert a value into a sequence at a specific index
  var newSeq = s
  newSeq.insert(value, index)
  newSeq

proc remove*[T](s: seq[T], index: int): seq[T] =
  ## Non-destructively remove a value from a sequence at a specific index
  var newSeq = s
  newSeq.delete(index)
  newSeq

proc update*[K, V](t: Table[K, V], key: K, value: V): Table[K, V] =
  ## Non-destructively update a value in a table
  var newTable = t
  newTable[key] = value
  newTable