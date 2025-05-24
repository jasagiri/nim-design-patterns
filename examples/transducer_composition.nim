## Transducer Composition Example
##
## This example demonstrates how to compose transducers.

import ../src/nim_design_patterns/functional/transducer

# Sample data
let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

# Create individual transducers with explicit type parameters
let evenFilter = filter[seq[int], int](proc(x: int): bool = x mod 2 == 0)
let doubler = map[seq[int], int, int](proc(x: int): int = x * 2)
let takeThree = take[seq[int], int](3)

# Compose them 
let composed = compose(takeThree, compose(doubler, evenFilter))

# Apply the composition
let result = transduce(
  composed,
  collectingReducer[int](),
  @[],
  numbers
)

echo "First 3 even numbers doubled: ", result