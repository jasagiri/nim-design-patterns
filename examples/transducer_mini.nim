## Minimal Transducer Example
##
## This example demonstrates basic transducer functionality.

import ../src/nim_design_patterns/functional/transducer

# Sample data
let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

# Create a filter transducer with explicit type parameters
let evenFilter = filter[seq[int], int](proc(x: int): bool = x mod 2 == 0)

# Apply the transducer
let result = transduce(
  evenFilter,
  collectingReducer[int](),
  @[],
  numbers
)

echo "Even numbers: ", result