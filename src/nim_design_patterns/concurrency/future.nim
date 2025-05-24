## Future/Promise Pattern Implementation
##
## The Future/Promise pattern provides a clean way to handle asynchronous operations.
## It decouples the value producer from its consumer, allowing asynchronous
## computation while providing structured methods for handling success, failure,
## and chaining operations.
##
## Key components:
## - Promise: Producer-side object that can be resolved or rejected
## - Future: Consumer-side object that can be chained, waited upon, or have callbacks attached
##
## This implementation supports:
## - Generic typing for any result type
## - Error handling with type-safety
## - Callback registration for notification on completion
## - Chaining transforms using map and flatMap (monadic operations)
## - Combining multiple futures with all/any operations
## - Timeouts and cancellation
## - Integration with Nim's standard async/await system

import std/[asyncdispatch, deques, options, tables, times, locks, atomics]
import std/locks except Lock 
import ../core/base
import nim_libaspects/[logging, metrics, errors]

type
  FutureState* = enum
    fsPending    # Not yet completed
    fsResolved   # Completed successfully
    fsRejected   # Completed with error
    fsCancelled  # Explicitly cancelled
    fsTimedOut   # Timed out

  FutureId* = distinct int64

  FutureCallback*[T] = proc(value: T) {.closure.}
  ErrorCallback* = proc(error: ref CatchableError) {.closure.}
  FinallyCallback* = proc() {.closure.}

  Promise*[T] = ref object
    ## Producer-side interface for a Future
    future*: Future[T]

  Future*[T] = ref object of Pattern
    ## Consumer-side interface for asynchronous operations
    id*: FutureId
    state*: Atomic[FutureState]
    value*: Option[T]
    error*: Option[ref CatchableError]
    callbacks*: seq[FutureCallback[T]]
    errorCallbacks*: seq[ErrorCallback]
    finallyCallbacks*: seq[FinallyCallback]
    lock*: Lock
    logger*: Logger
    metrics*: MetricsRegistry
    creationTime*: MonoTime
    completionTime*: MonoTime
    deadline*: Option[MonoTime]

  FutureTimeoutError* = ref object of CatchableError
    futureId*: FutureId

  FutureCancelledError* = ref object of CatchableError
    futureId*: FutureId

# Helper functions for FutureId
proc `$`*(id: FutureId): string = $id.int64
proc `==`*(a, b: FutureId): bool {.borrow.}
proc `<`*(a, b: FutureId): bool {.borrow.}
proc hash*(id: FutureId): Hash {.borrow.}

proc newFutureId*(): FutureId =
  ## Generate a new unique FutureId
  var counter {.global.}: Atomic[int64]
  counter.atomicInc(1, 1)
  FutureId(counter.load)

# Future implementation
proc newFuture*[T](logger: Logger = nil, metrics: MetricsRegistry = nil): Future[T] =
  ## Create a new future
  result = Future[T](
    id: newFutureId(),
    state: Atomic[FutureState](fsPending.int),
    value: none(T),
    error: none(ref CatchableError),
    callbacks: @[],
    errorCallbacks: @[],
    finallyCallbacks: @[],
    logger: logger,
    metrics: metrics,
    creationTime: getMonoTime(),
    completionTime: MonoTime(),
    deadline: none(MonoTime),
    name: "Future",
    kind: pkFunctional,
    description: "Promise/Future pattern for handling asynchronous operations"
  )
  initLock(result.lock)
  
  if not logger.isNil:
    logger.debug("Created future ", $result.id)
  
  if not metrics.isNil:
    metrics.increment("future.created")

# Promise implementation
proc newPromise*[T](logger: Logger = nil, metrics: MetricsRegistry = nil): Promise[T] =
  ## Create a new promise with associated future
  let future = newFuture[T](logger, metrics)
  Promise[T](future: future)

# Future state management
proc getState*[T](future: Future[T]): FutureState =
  ## Get the current state of the future
  FutureState(future.state.load(moRelaxed))

proc setState*[T](future: Future[T], state: FutureState) =
  ## Set the state of the future
  future.state.store(state.int, moRelease)

proc isCompleted*[T](future: Future[T]): bool =
  ## Check if the future is complete (resolved, rejected, cancelled, or timed out)
  let state = future.getState()
  state in [fsResolved, fsRejected, fsCancelled, fsTimedOut]

proc isResolved*[T](future: Future[T]): bool =
  ## Check if the future was resolved successfully
  future.getState() == fsResolved

proc isRejected*[T](future: Future[T]): bool =
  ## Check if the future was rejected with an error
  future.getState() == fsRejected

proc isCancelled*[T](future: Future[T]): bool =
  ## Check if the future was cancelled
  future.getState() == fsCancelled

proc isTimedOut*[T](future: Future[T]): bool =
  ## Check if the future timed out
  future.getState() == fsTimedOut

proc getValue*[T](future: Future[T]): Option[T] =
  ## Get the resolved value if available
  if future.isResolved():
    future.value
  else:
    none(T)

proc getError*[T](future: Future[T]): Option[ref CatchableError] =
  ## Get the error if the future was rejected
  if future.isRejected() or future.isTimedOut() or future.isCancelled():
    future.error
  else:
    none(ref CatchableError)

# Promise resolution
proc resolve*[T](promise: Promise[T], value: T) =
  ## Resolve the promise with a value
  let future = promise.future
  
  if future.isCompleted():
    # Already completed, cannot resolve again
    if not future.logger.isNil:
      future.logger.warn("Attempted to resolve already completed future ", $future.id)
    return
  
  withLock(future.lock):
    if future.isCompleted():
      return
    
    future.value = some(value)
    future.setState(fsResolved)
    future.completionTime = getMonoTime()
  
  # Call success callbacks outside the lock
  for callback in future.callbacks:
    try:
      callback(value)
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future callback: ", e.msg)
  
  # Call finally callbacks
  for callback in future.finallyCallbacks:
    try:
      callback()
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future finally callback: ", e.msg)
  
  if not future.logger.isNil:
    future.logger.debug("Future ", $future.id, " resolved")
  
  if not future.metrics.isNil:
    future.metrics.increment("future.resolved")
    let duration = (future.completionTime - future.creationTime).inMilliseconds.float / 1000.0
    future.metrics.histogram("future.resolution_time", duration)

proc reject*[T](promise: Promise[T], error: ref CatchableError) =
  ## Reject the promise with an error
  let future = promise.future
  
  if future.isCompleted():
    # Already completed, cannot reject again
    if not future.logger.isNil:
      future.logger.warn("Attempted to reject already completed future ", $future.id)
    return
  
  withLock(future.lock):
    if future.isCompleted():
      return
    
    future.error = some(error)
    future.setState(fsRejected)
    future.completionTime = getMonoTime()
  
  # Call error callbacks outside the lock
  for callback in future.errorCallbacks:
    try:
      callback(error)
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future error callback: ", e.msg)
  
  # Call finally callbacks
  for callback in future.finallyCallbacks:
    try:
      callback()
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future finally callback: ", e.msg)
  
  if not future.logger.isNil:
    future.logger.debug("Future ", $future.id, " rejected with error: ", error.msg)
  
  if not future.metrics.isNil:
    future.metrics.increment("future.rejected")
    let duration = (future.completionTime - future.creationTime).inMilliseconds.float / 1000.0
    future.metrics.histogram("future.rejection_time", duration)

# Future callback registration
proc onSuccess*[T](future: Future[T], callback: FutureCallback[T]): Future[T] =
  ## Register a callback for successful completion
  if future.isResolved():
    # Already resolved, call immediately
    try:
      callback(future.value.get())
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future success callback: ", e.msg)
  else:
    withLock(future.lock):
      future.callbacks.add(callback)
  
  # Return self for chaining
  future

proc onError*[T](future: Future[T], callback: ErrorCallback): Future[T] =
  ## Register a callback for error case
  if future.isRejected() or future.isTimedOut() or future.isCancelled():
    # Already failed, call immediately
    try:
      callback(future.error.get())
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future error callback: ", e.msg)
  else:
    withLock(future.lock):
      future.errorCallbacks.add(callback)
  
  # Return self for chaining
  future

proc finally*[T](future: Future[T], callback: FinallyCallback): Future[T] =
  ## Register a callback that runs in all completion cases
  if future.isCompleted():
    # Already completed, call immediately
    try:
      callback()
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future finally callback: ", e.msg)
  else:
    withLock(future.lock):
      future.finallyCallbacks.add(callback)
  
  # Return self for chaining
  future

# Future transformation (monadic operations)
proc map*[T, R](future: Future[T], transformer: proc(value: T): R): Future[R] =
  ## Transform the future's value if successful
  let resultFuture = newFuture[R](future.logger, future.metrics)
  let resultPromise = Promise[R](future: resultFuture)
  
  discard future.onSuccess(
    proc(value: T) =
      try:
        let transformedValue = transformer(value)
        resultPromise.resolve(transformedValue)
      except CatchableError as e:
        resultPromise.reject(e)
  ).onError(
    proc(error: ref CatchableError) =
      resultPromise.reject(error)
  )
  
  resultFuture

proc flatMap*[T, R](future: Future[T], transformer: proc(value: T): Future[R]): Future[R] =
  ## Transform the future's value into another future
  let resultFuture = newFuture[R](future.logger, future.metrics)
  let resultPromise = Promise[R](future: resultFuture)
  
  discard future.onSuccess(
    proc(value: T) =
      try:
        let nestedFuture = transformer(value)
        
        discard nestedFuture.onSuccess(
          proc(nestedValue: R) =
            resultPromise.resolve(nestedValue)
        ).onError(
          proc(error: ref CatchableError) =
            resultPromise.reject(error)
        )
      except CatchableError as e:
        resultPromise.reject(e)
  ).onError(
    proc(error: ref CatchableError) =
      resultPromise.reject(error)
  )
  
  resultFuture

proc recover*[T](future: Future[T], recovery: proc(error: ref CatchableError): T): Future[T] =
  ## Recover from an error with a fallback value
  let resultFuture = newFuture[T](future.logger, future.metrics)
  let resultPromise = Promise[T](future: resultFuture)
  
  discard future.onSuccess(
    proc(value: T) =
      resultPromise.resolve(value)
  ).onError(
    proc(error: ref CatchableError) =
      try:
        let recoveredValue = recovery(error)
        resultPromise.resolve(recoveredValue)
      except CatchableError as e:
        resultPromise.reject(e)
  )
  
  resultFuture

# Timeout and cancellation
proc withTimeout*[T](future: Future[T], timeoutMs: int): Future[T] =
  ## Set a timeout for the future
  if future.isCompleted():
    return future
  
  withLock(future.lock):
    if future.isCompleted():
      return future
    
    let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
    future.deadline = some(deadline)
  
  # Start timeout tracking
  asyncCheck (proc() {.async.} =
    await sleepAsync(timeoutMs)
    
    if not future.isCompleted():
      let timeoutError = FutureTimeoutError(
        msg: "Future timed out after " & $timeoutMs & "ms",
        futureId: future.id
      )
      
      withLock(future.lock):
        if not future.isCompleted():
          future.error = some(cast[ref CatchableError](timeoutError))
          future.setState(fsTimedOut)
          future.completionTime = getMonoTime()
      
      # Call error callbacks outside the lock
      for callback in future.errorCallbacks:
        try:
          callback(timeoutError)
        except CatchableError as e:
          if not future.logger.isNil:
            future.logger.error("Exception in future error callback: ", e.msg)
      
      # Call finally callbacks
      for callback in future.finallyCallbacks:
        try:
          callback()
        except CatchableError as e:
          if not future.logger.isNil:
            future.logger.error("Exception in future finally callback: ", e.msg)
      
      if not future.logger.isNil:
        future.logger.debug("Future ", $future.id, " timed out after ", $timeoutMs, "ms")
      
      if not future.metrics.isNil:
        future.metrics.increment("future.timedout")
  )()
  
  future

proc cancel*[T](future: Future[T]) =
  ## Cancel the future explicitly
  if future.isCompleted():
    return
  
  withLock(future.lock):
    if future.isCompleted():
      return
    
    let cancelError = FutureCancelledError(
      msg: "Future was cancelled",
      futureId: future.id
    )
    
    future.error = some(cast[ref CatchableError](cancelError))
    future.setState(fsCancelled)
    future.completionTime = getMonoTime()
  
  # Call error callbacks outside the lock
  for callback in future.errorCallbacks:
    try:
      callback(cast[ref CatchableError](future.error.get()))
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future error callback: ", e.msg)
  
  # Call finally callbacks
  for callback in future.finallyCallbacks:
    try:
      callback()
    except CatchableError as e:
      if not future.logger.isNil:
        future.logger.error("Exception in future finally callback: ", e.msg)
  
  if not future.logger.isNil:
    future.logger.debug("Future ", $future.id, " cancelled")
  
  if not future.metrics.isNil:
    future.metrics.increment("future.cancelled")

# Waiting for futures
proc waitForCompletion*[T](future: Future[T], timeoutMs = -1): bool =
  ## Wait for the future to complete, returns true if completed or false if timed out
  
  if future.isCompleted():
    return true
  
  var 
    completed = false
    completionPromise: Promise[bool] = nil
    completionFuture: Future[bool] = nil
  
  # Set up a callback to notify completion
  completionFuture = newFuture[bool](future.logger, future.metrics)
  completionPromise = Promise[bool](future: completionFuture)
  
  discard future.finally(
    proc() =
      completionPromise.resolve(true)
  )
  
  if timeoutMs < 0:
    # Wait indefinitely
    while not future.isCompleted():
      sleep(10)
    return true
  else:
    # Use timeout
    let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
    
    while not future.isCompleted():
      if getMonoTime() > deadline:
        return false
      sleep(10)
    
    return true

proc waitForResult*[T](future: Future[T], timeoutMs = -1): Option[T] =
  ## Wait for the future's result, returns none if timed out or error occurred
  if not waitForCompletion(future, timeoutMs):
    return none(T)
  
  if future.isResolved():
    return future.value
  else:
    return none(T)

proc waitForResultOrError*[T](future: Future[T], timeoutMs = -1): Result[T, ref CatchableError] =
  ## Wait for the future to complete and return Result
  if not waitForCompletion(future, timeoutMs):
    return Result[T, ref CatchableError].err(
      FutureTimeoutError(
        msg: "Wait timed out after " & $timeoutMs & "ms",
        futureId: future.id
      )
    )
  
  if future.isResolved():
    return Result[T, ref CatchableError].ok(future.value.get())
  else:
    return Result[T, ref CatchableError].err(future.error.get())

# Combinators for multiple futures
proc all*[T](futures: seq[Future[T]], logger: Logger = nil, metrics: MetricsRegistry = nil): Future[seq[T]] =
  ## Wait for all futures to complete, result is a sequence of their values
  let resultFuture = newFuture[seq[T]](logger, metrics)
  let resultPromise = Promise[seq[T]](future: resultFuture)
  
  if futures.len == 0:
    # Empty list completes immediately
    resultPromise.resolve(@[])
    return resultFuture
  
  var 
    results = newSeq[Option[T]](futures.len)
    completedCount = 0
    failed = false
    completeLock: Lock
  
  initLock(completeLock)
  
  for i, future in futures:
    # Set up callbacks for each future
    discard future.onSuccess(
      proc(value: T) =
        withLock(completeLock):
          if failed:
            return
          
          results[i] = some(value)
          inc completedCount
          
          if completedCount == futures.len:
            # All futures completed successfully
            var resultValues = newSeq[T](futures.len)
            for j in 0..<futures.len:
              resultValues[j] = results[j].get()
            
            resultPromise.resolve(resultValues)
    ).onError(
      proc(error: ref CatchableError) =
        withLock(completeLock):
          if failed:
            return
          
          # If any future fails, the combined future fails
          failed = true
          resultPromise.reject(error)
    )
    
    # Check if already completed
    if future.isResolved():
      withLock(completeLock):
        if failed:
          continue
        
        results[i] = future.value
        inc completedCount
    elif future.isCompleted():
      withLock(completeLock):
        if failed:
          continue
        
        # If any future fails, the combined future fails
        failed = true
        resultPromise.reject(future.error.get())
  
  # Check if all already completed
  withLock(completeLock):
    if completedCount == futures.len and not failed:
      var resultValues = newSeq[T](futures.len)
      for j in 0..<futures.len:
        resultValues[j] = results[j].get()
      
      resultPromise.resolve(resultValues)
  
  resultFuture

proc any*[T](futures: seq[Future[T]], logger: Logger = nil, metrics: MetricsRegistry = nil): Future[T] =
  ## Wait for any future to complete successfully, returns the first successful result
  let resultFuture = newFuture[T](logger, metrics)
  let resultPromise = Promise[T](future: resultFuture)
  
  if futures.len == 0:
    # Empty list cannot complete
    resultPromise.reject(
      (ref CatchableError)(msg: "Cannot complete any() with empty future list")
    )
    return resultFuture
  
  var 
    errorCount = 0
    resolved = false
    completeLock: Lock
  
  initLock(completeLock)
  
  for future in futures:
    # Set up callbacks for each future
    discard future.onSuccess(
      proc(value: T) =
        withLock(completeLock):
          if resolved:
            return
          
          resolved = true
          resultPromise.resolve(value)
    ).onError(
      proc(error: ref CatchableError) =
        withLock(completeLock):
          if resolved:
            return
          
          inc errorCount
          if errorCount == futures.len:
            # All futures failed
            resultPromise.reject(
              (ref CatchableError)(msg: "All futures in any() failed")
            )
    )
    
    # Check if already completed
    if future.isResolved():
      withLock(completeLock):
        if resolved:
          continue
        
        resolved = true
        resultPromise.resolve(future.value.get())
        break
    elif future.isCompleted():
      withLock(completeLock):
        if resolved:
          continue
        
        inc errorCount
  
  # Check if all already completed with errors
  withLock(completeLock):
    if errorCount == futures.len and not resolved:
      resultPromise.reject(
        (ref CatchableError)(msg: "All futures in any() failed")
      )
  
  resultFuture

# Factory methods
proc fromValue*[T](value: T, logger: Logger = nil, metrics: MetricsRegistry = nil): Future[T] =
  ## Create a pre-resolved future
  let future = newFuture[T](logger, metrics)
  let promise = Promise[T](future: future)
  promise.resolve(value)
  future

proc fromError*[T](error: ref CatchableError, logger: Logger = nil, metrics: MetricsRegistry = nil): Future[T] =
  ## Create a pre-rejected future
  let future = newFuture[T](logger, metrics)
  let promise = Promise[T](future: future)
  promise.reject(error)
  future

proc fromProc*[T](fn: proc(): T, logger: Logger = nil, metrics: MetricsRegistry = nil): Future[T] =
  ## Create a future from a synchronous function
  let future = newFuture[T](logger, metrics)
  let promise = Promise[T](future: future)
  
  # Execute the function asynchronously
  asyncCheck (proc() {.async.} =
    try:
      let result = fn()
      promise.resolve(result)
    except CatchableError as e:
      promise.reject(e)
  )()
  
  future

proc fromAsyncProc*[T](fn: proc(): Future[T], logger: Logger = nil, metrics: MetricsRegistry = nil): Future[T] =
  ## Create a future from an async function
  let future = newFuture[T](logger, metrics)
  let promise = Promise[T](future: future)
  
  # Execute the async function
  asyncCheck (proc() {.async.} =
    try:
      let asyncFuture = fn()
      let result = await asyncFuture
      promise.resolve(result)
    except CatchableError as e:
      promise.reject(e)
  )()
  
  future

# Nim asyncdispatch integration
proc toNimFuture*[T](future: Future[T]): asyncdispatch.Future[T] =
  ## Convert our Future to Nim's standard Future
  var nimFuture = newFuture[T]("converted")
  
  discard future.onSuccess(
    proc(value: T) =
      nimFuture.complete(value)
  ).onError(
    proc(error: ref CatchableError) =
      nimFuture.fail(error)
  )
  
  nimFuture

proc fromNimFuture*[T](nimFuture: asyncdispatch.Future[T], logger: Logger = nil, metrics: MetricsRegistry = nil): Future[T] =
  ## Convert Nim's standard Future to our Future
  let future = newFuture[T](logger, metrics)
  let promise = Promise[T](future: future)
  
  nimFuture.callback =
    proc() =
      if nimFuture.failed:
        promise.reject(cast[ref CatchableError](nimFuture.error))
      else:
        promise.resolve(nimFuture.read())
  
  future

# Utilities
proc logFuture*[T](future: Future[T], msg: string) =
  ## Log future activity
  if not future.logger.isNil:
    future.logger.debug("Future ", $future.id, ": ", msg)

proc metrics*[T](future: Future[T], name: string, value: float) =
  ## Record metrics for future
  if not future.metrics.isNil:
    future.metrics.gauge("future." & name, value)