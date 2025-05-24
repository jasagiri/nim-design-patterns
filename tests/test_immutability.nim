import unittest
import ../src/nim_design_patterns/functional/immutability
import std/tables
import std/sets

suite "Immutability Pattern":
  test "ImmutableList basic operations":
    # Create and transform
    let emptyList = empty[int]()
    check emptyList.isEmpty

    let list1 = cons(1, cons(2, cons(3, empty[int]())))
    check not list1.isEmpty
    check list1.head == 1
    check list1.tail.head == 2
    
    let list2 = fromSeq(@[1, 2, 3])
    check list2.toSeq() == @[1, 2, 3]
    
    # Singleton
    let singletonList = singleton(42)
    check singletonList.head == 42
    check singletonList.tail.isEmpty
    
    # Map
    let doubled = map(list1, proc(x: int): int = x * 2)
    check doubled.toSeq() == @[2, 4, 6]
    
    # Filter
    let evens = filter(list1, proc(x: int): bool = x mod 2 == 0)
    check evens.toSeq() == @[2]
    
    # Fold operations
    let sum = foldLeft(list1, 0, proc(acc, x: int): int = acc + x)
    check sum == 6
    
    let product = foldRight(list1, 1, proc(x, acc: int): int = x * acc)
    check product == 6
    
    # List operations
    let list3 = fromSeq(@[4, 5, 6])
    let combined = append(list1, list3)
    check combined.toSeq() == @[1, 2, 3, 4, 5, 6]
    
    let reversed = reverse(list1)
    check reversed.toSeq() == @[3, 2, 1]
    
    let firstTwo = take(list1, 2)
    check firstTwo.toSeq() == @[1, 2]
    
    let lastTwo = drop(list1, 1)
    check lastTwo.toSeq() == @[2, 3]

  test "ImmutableMap operations":
    # Create
    let emptyMap = emptyMap[string, int]()
    check not emptyMap.contains("key")
    
    var table = initTable[string, int]()
    table["a"] = 1
    table["b"] = 2
    let map1 = fromTable(table)
    
    # Access
    check map1.contains("a")
    check map1.get("a") == 1
    check map1.getOrDefault("c", 0) == 0
    
    # Modify
    let map2 = put(map1, "c", 3)
    check map2.contains("c")
    check map1.contains("c") == false  # Original unchanged
    
    let map3 = delete(map2, "a")
    check not map3.contains("a")
    check map2.contains("a")  # Original unchanged
    
    # Conversion and utilities
    check map2.keys().len == 3
    check map2.values().len == 3
    
    # Transformations
    let map4 = map(map1, proc(k: string, v: int): string = k & $v)
    check map4.get("a") == "a1"
    
    let filtered = filter(map1, proc(k: string, v: int): bool = v > 1)
    check filtered.contains("b")
    check not filtered.contains("a")

  test "ImmutableSet operations":
    # Create
    let emptySet = emptySet[int]()
    check not emptySet.contains(1)
    
    var hashSet = initHashSet[int]()
    hashSet.incl(1)
    hashSet.incl(2)
    hashSet.incl(3)
    let set1 = fromHashSet(hashSet)
    
    # Access and modify
    check set1.contains(1)
    let set2 = add(set1, 4)
    check set2.contains(4)
    check not set1.contains(4)  # Original unchanged
    
    let set3 = remove(set2, 1)
    check not set3.contains(1)
    check set2.contains(1)  # Original unchanged
    
    # Set operations
    var hashSet2 = initHashSet[int]()
    hashSet2.incl(3)
    hashSet2.incl(4)
    hashSet2.incl(5)
    let set4 = fromHashSet(hashSet2)
    
    let unionSet = union(set1, set4)
    check unionSet.contains(1)
    check unionSet.contains(5)
    
    let intersectionSet = intersection(set1, set4)
    check intersectionSet.contains(3)
    check not intersectionSet.contains(1)
    
    let differenceSet = difference(set1, set4)
    check differenceSet.contains(1)
    check not differenceSet.contains(3)
    
    # Transformations
    let mappedSet = map(set1, proc(x: int): int = x * 10)
    check mappedSet.contains(10)
    check mappedSet.contains(20)
    check mappedSet.contains(30)
    
    let filteredSet = filter(set1, proc(x: int): bool = x > 1)
    check not filteredSet.contains(1)
    check filteredSet.contains(2)

  test "Extensions for built-in types":
    # Sequences
    let seq1 = @[1, 2, 3, 4]
    let seq2 = modify(seq1, 1, 20)
    check seq1[1] == 2  # Original unchanged
    check seq2[1] == 20
    
    let seq3 = insertAt(seq1, 1, 10)
    check seq3 == @[1, 10, 2, 3, 4]
    check seq1 == @[1, 2, 3, 4]  # Original unchanged
    
    let seq4 = remove(seq1, 1)
    check seq4 == @[1, 3, 4]
    check seq1 == @[1, 2, 3, 4]  # Original unchanged
    
    # Tables
    var table1 = initTable[string, int]()
    table1["a"] = 1
    table1["b"] = 2
    
    let table2 = update(table1, "a", 10)
    check table1["a"] == 1  # Original unchanged
    check table2["a"] == 10