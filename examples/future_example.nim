## Example usage of the Future/Promise pattern
##
## This example demonstrates how the Future/Promise pattern can be used
## to handle asynchronous operations, chain transforms, and combine results

import std/[asyncdispatch, os, httpClient, strformat, json, options, times]
import ../src/nim_design_patterns/concurrency/future
import ../src/nim_design_patterns/core/base
import nim_libaspects/logging

# Create a logger for our example
let logger = newConsoleLogger()
logger.log(lvlInfo, "Starting Future/Promise pattern example")

# Simple functions that return futures
proc fetchDataAsync(url: string): Future[string] =
  let promise = newPromise[string](logger)
  let future = promise.future
  
  # Simulate an asynchronous HTTP request
  asyncCheck (proc() {.async.} =
    try:
      logger.log(lvlInfo, &"Fetching data from {url}")
      
      # Use Nim's HTTP client for the actual request
      let client = newHttpClient()
      let response = client.get(url)
      
      # Add a small delay to simulate network latency
      await sleepAsync(500) 
      
      if response.code == Http200:
        promise.resolve(response.body)
      else:
        promise.reject((ref CatchableError)(
          msg: &"HTTP request failed with status code {response.code}"
        ))
    except CatchableError as e:
      promise.reject(e)
  )()
  
  future

proc parseJsonAsync(jsonStr: string): Future[JsonNode] =
  let promise = newPromise[JsonNode](logger)
  
  # Parse the JSON asynchronously
  asyncCheck (proc() {.async.} =
    try:
      logger.log(lvlInfo, "Parsing JSON data")
      
      # Simulate processing time
      await sleepAsync(100)
      
      let parsed = parseJson(jsonStr)
      promise.resolve(parsed)
    except CatchableError as e:
      promise.reject(e)
  )()
  
  promise.future

proc processDataAsync(data: JsonNode): Future[seq[string]] =
  let promise = newPromise[seq[string]](logger)
  
  # Process the JSON data asynchronously
  asyncCheck (proc() {.async.} =
    try:
      logger.log(lvlInfo, "Processing data")
      
      # Simulate processing time
      await sleepAsync(200)
      
      var result: seq[string] = @[]
      
      # Extract some data from JSON
      # For example, if we have an array of objects with 'name' fields
      if data.kind == JArray:
        for item in data:
          if item.hasKey("name"):
            result.add(item["name"].getStr())
      
      promise.resolve(result)
    except CatchableError as e:
      promise.reject(e)
  )()
  
  promise.future

proc saveResultsAsync(items: seq[string]): Future[int] =
  let promise = newPromise[int](logger)
  
  # Simulate saving to a database asynchronously
  asyncCheck (proc() {.async.} =
    try:
      logger.log(lvlInfo, &"Saving {items.len} items to database")
      
      # Simulate database operation
      await sleepAsync(300)
      
      # Return the number of items saved
      promise.resolve(items.len)
    except CatchableError as e:
      promise.reject(e)
  )()
  
  promise.future

# Example of comprehensive, real-world usage
proc runExample() {.async.} =
  logger.log(lvlInfo, "Starting the Future/Promise example flow")
  
  # Multiple data sources
  let urls = [
    "https://jsonplaceholder.typicode.com/users",
    "https://jsonplaceholder.typicode.com/posts?userId=1"
  ]
  
  # Fetch data from multiple sources concurrently
  var dataFutures: seq[Future[string]] = @[]
  
  for url in urls:
    let future = fetchDataAsync(url)
    dataFutures.add(future)
    
    # Add timeout and error handling
    discard future.withTimeout(5000)
      .onError(proc(err: ref CatchableError) =
        logger.log(lvlError, &"Failed to fetch from {url}: {err.msg}")
      )
  
  # Wait for all fetches to complete
  let allDataFuture = all(dataFutures, logger)
  
  # Continue processing once all data is available
  let allData = await toNimFuture(allDataFuture)
  logger.log(lvlInfo, &"Successfully fetched data from {allData.len} sources")
  
  # Parse all JSON responses concurrently
  var parsedFutures: seq[Future[JsonNode]] = @[]
  
  for dataStr in allData:
    let future = parseJsonAsync(dataStr)
    parsedFutures.add(future)
  
  # Wait for all parsing to complete
  let allParsedFuture = all(parsedFutures, logger)
  
  # Process the parsed data
  let allParsed = await toNimFuture(allParsedFuture)
  
  # Process each JSON document and extract items
  var processingFutures: seq[Future[seq[string]]] = @[]
  
  for parsedJson in allParsed:
    let future = processDataAsync(parsedJson)
    processingFutures.add(future)
  
  # Combine all processing results
  let allProcessedFuture = all(processingFutures, logger)
  
  # Flatten all items into a single list
  let processedLists = await toNimFuture(allProcessedFuture)
  var allItems: seq[string] = @[]
  
  for itemList in processedLists:
    allItems.add(itemList)
  
  logger.log(lvlInfo, &"Extracted {allItems.len} items from data sources")
  
  # Save all items
  let saveFuture = saveResultsAsync(allItems)
  
  # Wait for save to complete with timeout
  discard saveFuture.withTimeout(2000)
  
  # Handle completion
  saveFuture.onSuccess(
    proc(count: int) =
      logger.log(lvlInfo, &"Successfully saved {count} items")
  ).onError(
    proc(err: ref CatchableError) =
      logger.log(lvlError, &"Failed to save items: {err.msg}")
  ).finally(
    proc() =
      logger.log(lvlInfo, "Save operation completed (success or failure)")
  )
  
  # Wait for save operation to complete
  discard await toNimFuture(
    saveFuture.map(proc(count: int): string = &"Saved {count} items")
  )
  
  logger.log(lvlInfo, "Example completed")

# Run the example
proc main() =
  # Run the async example
  waitFor runExample()
  
  # Process any remaining callbacks
  while hasPendingOperations():
    poll(100)
  
  logger.log(lvlInfo, "Application shutdown complete")

when isMainModule:
  main()