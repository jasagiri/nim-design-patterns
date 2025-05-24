## Transducer Pattern Example
##
## This example demonstrates the power and flexibility of transducers for data transformation.
## Transducers allow for composable, efficient data processing without creating intermediate collections.

import std/[strformat, strutils, times, algorithm, tables]
import ../src/nim_design_patterns/functional/transducer

echo "Transducer Pattern Examples"
echo "=========================="
echo ""

# Example 1: Basic data transformation
# ---------------------------------------
echo "Example 1: Basic Data Processing Pipeline"
echo "----------------------------------------"

# Create sample data
let numbers = @[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

# Create a processing pipeline using transducers:
# 1. Filter out odd numbers
# 2. Multiply each remaining number by 2
# 3. Take only the first 3 results
let evenFilter = filter[seq[int], int](proc(x: int): bool = x mod 2 == 0)
let doubler = map[seq[int], int, int](proc(x: int): int = x * 2)
let takeFirst3 = take[seq[int], int](3)

let pipeline = compose(takeFirst3, compose(doubler, evenFilter))

# Apply the pipeline
let result = into(numbers, pipeline)

echo "Input: ", numbers
echo "Output: ", result
echo "Transformation: Filter even numbers -> Double each -> Take first 3"
echo ""

# Example 2: Log processing
# ---------------------------------------
echo "Example 2: Log Processing"
echo "------------------------"

# Sample log entries
let logEntries = @[
  "INFO: System started - 2023-01-15",
  "DEBUG: Connecting to database - 2023-01-15",
  "ERROR: Failed to connect to server - 2023-01-15",
  "INFO: User 'admin' logged in - 2023-01-15",
  "DEBUG: Query executed in 25ms - 2023-01-15",
  "WARN: High memory usage detected - 2023-01-15",
  "ERROR: Database timeout - 2023-01-16",
  "INFO: Backup completed - 2023-01-16",
  "DEBUG: Cache hit ratio: 78% - 2023-01-16",
  "ERROR: Disk space low - 2023-01-17"
]

echo "Processing log entries..."

# Create transducers for log processing:
# 1. Filter to keep only ERROR and WARN entries
# 2. Extract just the message part (without the level and date)
# 3. Convert to uppercase for emphasis
let errorFilterT = filter[seq[string], string](
  proc(s: string): bool = s.startsWith("ERROR:") or s.startsWith("WARN:")
)
let extractMessageT = map[seq[string], string, string](
  proc(s: string): string = 
    let parts = s.split(" - ")
    if parts.len > 0:
      parts[0]
    else:
      s
)
let upperCaseT = map[seq[string], string, string](
  proc(s: string): string = s.toUpperAscii()
)

let logPipeline = compose(upperCaseT, compose(extractMessageT, errorFilterT))

# Apply the pipeline
let filteredLogs = into(logEntries, logPipeline)

echo "All log entries: ", logEntries.len
echo "Filtered important logs: ", filteredLogs.len
echo "Important messages:"
for log in filteredLogs:
  echo "  - ", log
echo ""

# Example 3: Working with nested data
# ---------------------------------------
echo "Example 3: Nested Data Processing"
echo "-------------------------------"

# Define a User type for nested data example
type
  Address = object
    street: string
    city: string
    country: string
  
  User = object
    id: int
    name: string
    age: int
    active: bool
    addresses: seq[Address]

# Create some sample user data
let users = @[
  User(id: 1, name: "Alice", age: 28, active: true, addresses: @[
    Address(street: "123 Main St", city: "New York", country: "USA"),
    Address(street: "456 High St", city: "Boston", country: "USA")
  ]),
  User(id: 2, name: "Bob", age: 35, active: false, addresses: @[
    Address(street: "789 Oak St", city: "London", country: "UK")
  ]),
  User(id: 3, name: "Charlie", age: 42, active: true, addresses: @[
    Address(street: "101 Pine St", city: "Paris", country: "France"),
    Address(street: "202 Elm St", city: "Berlin", country: "Germany"),
    Address(street: "303 Maple St", city: "Rome", country: "Italy")
  ]),
  User(id: 4, name: "Diana", age: 31, active: true, addresses: @[]),
  User(id: 5, name: "Evan", age: 25, active: false, addresses: @[
    Address(street: "404 Oak St", city: "Tokyo", country: "Japan")
  ])
]

# FlatMap all user addresses
let activeUserFilter = filter[seq[Address], User](
  proc(user: User): bool = user.active  # Active users only
)
let addressFlatMap = flatMap[seq[Address], User, Address](
  proc(user: User): seq[Address] = user.addresses
)
let nonUsaFilter = filter[seq[Address], Address](
  proc(addr: Address): bool = addr.country != "USA"  # Non-USA addresses
)

let addressPipeline = compose(nonUsaFilter, compose(addressFlatMap, activeUserFilter))

let nonUsaAddresses = into(users, addressPipeline)

echo "Processing user addresses..."
echo "Total users: ", users.len
echo "Active users with non-USA addresses:"
for i, addr in nonUsaAddresses:
  echo fmt"  {i+1}. {addr.street}, {addr.city}, {addr.country}"
echo ""

# Example 4: Performance comparison
# ---------------------------------------
echo "Example 4: Performance Comparison"
echo "-------------------------------"

# Generate a larger dataset for performance comparison
var largeDataset = newSeq[int](10000)
for i in 0..<10000:
  largeDataset[i] = i

echo "Processing a dataset of 10,000 elements..."

# Measure traditional approach with intermediate collections
let traditionalStart = cpuTime()
# Traditional approach: create intermediate collections
let step1 = largeDataset.filterIt(it mod 2 == 0)
let step2 = step1.mapIt(it * 2)
let step3 = step2.filterIt(it > 1000 and it < 5000)
let traditionalResult = step3
let traditionalTime = cpuTime() - traditionalStart

# Measure transducer approach
let transducerStart = cpuTime()
# Transducer approach: compose transformations without intermediate collections
let evenFilter2 = filter[seq[int], int](proc(x: int): bool = x mod 2 == 0)
let doubler2 = map[seq[int], int, int](proc(x: int): int = x * 2)
let rangeFilter = filter[seq[int], int](proc(x: int): bool = x > 1000 and x < 5000)

let transducerPipeline = compose(rangeFilter, compose(doubler2, evenFilter2))
let transducerResult = into(largeDataset, transducerPipeline)
let transducerTime = cpuTime() - transducerStart

echo fmt"Traditional approach (with intermediate collections): {traditionalTime:.6f} seconds"
echo fmt"Transducer approach (without intermediate collections): {transducerTime:.6f} seconds"
echo fmt"Results are the same: {traditionalResult == transducerResult}"
echo fmt"Result size: {transducerResult.len} elements"
echo ""

# Example 5: Stateful transformations
# ---------------------------------------
echo "Example 5: Stateful Transformations"
echo "---------------------------------"

# Sample data for time series analysis
type
  Measurement = object
    timestamp: string
    value: float

let measurements = @[
  Measurement(timestamp: "2023-01-01 00:00", value: 10.5),
  Measurement(timestamp: "2023-01-01 01:00", value: 11.2),
  Measurement(timestamp: "2023-01-01 02:00", value: 10.8),
  Measurement(timestamp: "2023-01-01 03:00", value: 9.7),
  Measurement(timestamp: "2023-01-01 04:00", value: 9.5),
  Measurement(timestamp: "2023-01-01 05:00", value: 10.1),
  Measurement(timestamp: "2023-01-01 06:00", value: 12.3),
  Measurement(timestamp: "2023-01-01 07:00", value: 14.2),
  Measurement(timestamp: "2023-01-01 08:00", value: 15.5),
  Measurement(timestamp: "2023-01-01 09:00", value: 16.8)
]

# Create windowed averages
let windowedT = windowed[seq[float], Measurement](3)  # Window size 3
let avgT = map[seq[float], seq[Measurement], float](
  proc(window: seq[Measurement]): float = 
    var sum = 0.0
    for m in window:
      sum += m.value
    sum / float(window.len)
)

let windowedPipeline = compose(avgT, windowedT)

# Apply the pipeline
let movingAverages = into(measurements, windowedPipeline)

echo "Calculating moving averages from time series data..."
echo "Original measurements:"
for m in measurements:
  echo fmt"  {m.timestamp}: {m.value:.1f}"

echo "Moving averages (window size 3):"
for i, avg in movingAverages:
  let startTime = measurements[i].timestamp
  let endTime = measurements[i+2].timestamp
  echo fmt"  {startTime} to {endTime}: {avg:.2f}"