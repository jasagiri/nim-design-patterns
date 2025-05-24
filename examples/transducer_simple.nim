## Simple example of the Transducer pattern
##
## This example demonstrates the basic operations of transducers.

import ../src/nim_design_patterns/functional/transducer
import std/options

# Sample data
let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

# Create transducers with explicit type parameters
let doubler = map[seq[int], int, int](proc(x: int): int = x * 2)
let evenFilter = filter[seq[int], int](proc(x: int): bool = x mod 2 == 0)
let takeFirst3 = take[seq[int], int](3)

# Apply a single transducer
let doubled = transduce(
  doubler,
  collectingReducer[int](),
  @[],
  numbers
)
echo "Doubled numbers: ", doubled

# Apply a chain of transducers
let composed = compose(
  takeFirst3,
  compose(
    doubler,
    evenFilter
  )
)

let result = transduce(
  composed,
  collectingReducer[int](),
  @[],
  numbers
)
echo "First 3 even numbers doubled: ", result

# Use a different reducer
let evenFilterForInt = filter[int, int](proc(x: int): bool = x mod 2 == 0)
let sum = transduce(
  evenFilterForInt,
  summingReducer(),
  0,
  numbers
)
echo "Sum of even numbers: ", sum