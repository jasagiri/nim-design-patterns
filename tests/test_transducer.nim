import unittest
import std/[options, sugar, tables, sets]
import ../src/nim_design_patterns/functional/transducer

suite "Transducer Pattern":
  test "Basic transducer operations":
    # Create a simple sequence
    let numbers = @[1, 2, 3, 4, 5]
    
    # Create a simple map transducer that doubles each value
    let doubleTransducer = map(proc(x: int): int = x * 2)
    
    # Apply the transducer to the sequence
    let doubled = into(numbers, doubleTransducer)
    
    # Check the result
    check doubled == @[2, 4, 6, 8, 10]

  test "Filter transducer":
    let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    
    # Create a filter transducer that keeps only even numbers
    let evenFilter = filter(proc(x: int): bool = x mod 2 == 0)
    
    # Apply the transducer
    let evens = into(numbers, evenFilter)
    
    # Check the result
    check evens == @[2, 4, 6, 8, 10]

  test "Take transducer":
    let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    
    # Create a take transducer that takes the first 3 elements
    let takeThree = take[int](3)
    
    # Apply the transducer
    let firstThree = into(numbers, takeThree)
    
    # Check the result
    check firstThree == @[1, 2, 3]

  test "Drop transducer":
    let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    
    # Create a drop transducer that skips the first 7 elements
    let dropSeven = drop[seq[int], int](7)
    
    # Apply the transducer
    let lastThree = into(numbers, dropSeven)
    
    # Check the result
    check lastThree == @[8, 9, 10]

  test "TakeWhile transducer":
    let numbers = @[2, 4, 6, 7, 8, 10]
    
    # Create a takeWhile transducer that takes elements while they are even
    let takeWhileEven = takeWhile(proc(x: int): bool = x mod 2 == 0)
    
    # Apply the transducer
    let evenPrefix = into(numbers, takeWhileEven)
    
    # Check the result
    check evenPrefix == @[2, 4, 6]

  test "DropWhile transducer":
    let numbers = @[2, 4, 6, 7, 8, 10]
    
    # Create a dropWhile transducer that drops elements while they are even
    let dropWhileEven = dropWhile(proc(x: int): bool = x mod 2 == 0)
    
    # Apply the transducer
    let afterEvens = into(numbers, dropWhileEven)
    
    # Check the result
    check afterEvens == @[7, 8, 10]

  test "Deduplicate transducer":
    let numbers = @[1, 2, 2, 3, 3, 3, 4, 5, 5]
    
    # Create a deduplicate transducer
    let dedup = deduplicate[int]()
    
    # Apply the transducer
    let unique = into(numbers, dedup)
    
    # Check the result
    check unique == @[1, 2, 3, 4, 5]

  test "FlatMap transducer":
    let numbers = @[1, 2, 3]
    
    # Create a flatMap transducer that repeats each number n times
    let repeatTransducer = flatMap(
      proc(x: int): seq[int] = 
        result = @[]
        for i in 1..x:
          result.add(x)
    )
    
    # Apply the transducer
    let repeated = into(numbers, repeatTransducer)
    
    # Check the result (1 appears once, 2 appears twice, 3 appears three times)
    check repeated == @[1, 2, 2, 3, 3, 3]

  test "Composing transducers":
    let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    
    # Create individual transducers
    let doubleTransducer = map(proc(x: int): int = x * 2)
    let evenFilter = filter(proc(x: int): bool = x mod 2 == 0)
    let takeThree = take[int](3)
    
    # Compose them together
    let pipeline = comp(takeThree, evenFilter, doubleTransducer)
    
    # Apply the composed transducer
    let result = into(numbers, pipeline)
    
    # Check the result (double all, keep evens, take 3)
    # [1,2,3,4,5,6,7,8,9,10] -> [2,4,6,8,10,12,14,16,18,20] -> [2,4,6,8,10,12,14,16,18,20] -> [2,4,6]
    check result == @[2, 4, 6]

  test "Common reducers":
    let numbers = @[1, 2, 3, 4, 5]
    
    # Using the summing reducer
    let sum = transform(
      numbers,
      identity[int, int](),
      summingReducer(),
      0
    )
    check sum == 15
    
    # Using the counting reducer
    let count = transform(
      numbers,
      identity[int, int](),
      countingReducer[int](),
      0
    )
    check count == 5
    
    # Using the joining reducer
    let strings = @["Hello", "world", "of", "transducers"]
    let joined = transform(
      strings,
      identity[string, string](),
      joiningReducer(" "),
      ""
    )
    check joined == "Hello world of transducers"
    
    # Using the first element reducer
    let first = transform(
      numbers,
      identity[Option[int], int](),
      firstReducer[int](),
      none(int)
    )
    check first == some(1)
    
    # Using the last element reducer
    let last = transform(
      numbers,
      identity[Option[int], int](),
      lastReducer[int](),
      none(int)
    )
    check last == some(5)

  test "Stateful transducers - windowed":
    let numbers = @[1, 2, 3, 4, 5, 6]
    
    # Create a windowed transducer with window size 3
    let windowedTransducer = windowed[int](3)
    
    # Apply the transducer
    let windows = into(numbers, windowedTransducer)
    
    # Check the result
    check windows.len == 4  # We should get 4 windows
    check windows[0] == @[1, 2, 3]
    check windows[1] == @[2, 3, 4]
    check windows[2] == @[3, 4, 5]
    check windows[3] == @[4, 5, 6]

  test "Stateful transducers - indexed":
    let letters = @["a", "b", "c"]
    
    # Create an indexed transducer
    let indexedTransducer = indexed[string]()
    
    # Apply the transducer
    let indexed = into(letters, indexedTransducer)
    
    # Check the result
    check indexed.len == 3
    check indexed[0] == (0, "a")
    check indexed[1] == (1, "b")
    check indexed[2] == (2, "c")

  test "Stateful transducers - partition":
    let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9]
    
    # Create a partition transducer with chunk size 3
    let partitionTransducer = partition[int](3)
    
    # Apply the transducer
    let partitions = into(numbers, partitionTransducer)
    
    # Check the result
    check partitions.len == 3  # We should get 3 partitions
    check partitions[0] == @[1, 2, 3]
    check partitions[1] == @[4, 5, 6]
    check partitions[2] == @[7, 8, 9]

  test "Complex pipeline with multiple transducers":
    let input = @[1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10]
    
    # Create a pipeline of transformations:
    # 1. Remove duplicates
    # 2. Keep only even numbers
    # 3. Square each number
    # 4. Take the first 3 results
    let pipeline = comp(
      take[int](3),
      map(proc(x: int): int = x * x),
      filter(proc(x: int): bool = x mod 2 == 0),
      deduplicate[int]()
    )
    
    # Apply the pipeline
    let result = into(input, pipeline)
    
    # Check the result (deduplicate -> filter evens -> square -> take 3)
    # [1,2,2,3,4,5,6,7,8,9,10,10] -> [1,2,3,4,5,6,7,8,9,10] -> [2,4,6,8,10] -> [4,16,36,64,100] -> [4,16,36]
    check result == @[4, 16, 36]