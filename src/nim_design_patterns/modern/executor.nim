## Modern Executor Pattern implementation
##
## The Executor pattern provides a way to decouple task submission from execution.
## Unlike the classic Command pattern, it focuses on concurrency control, resource
## management, and scheduling policies.

import std/[asyncdispatch, deques, tables, sets, strformat, hashes, options, monotimes]
import std/locks except Lock
import std/atomics
import nim_libaspects/[logging, metrics, errors]
import ../core/base

type
  TaskId* = distinct int64
  
  TaskState* = enum
    tsPending
    tsRunning
    tsSucceeded
    tsFailed
    tsCancelled
    tsRejected
  
  TaskPriority* = enum
    tpLow = 0
    tpNormal = 100
    tpHigh = 200
    tpCritical = 300
  
  ResourceConstraint* = ref object of RootObj
    ## Resource limits and requirements for task execution
    name*: string
  
  CpuConstraint* = ref object of ResourceConstraint
    cores*: int
  
  MemoryConstraint* = ref object of ResourceConstraint
    megabytes*: int
  
  TimeConstraint* = ref object of ResourceConstraint
    milliseconds*: int
  
  Task*[T] = ref object of Pattern
    ## Abstract base for executable tasks
    id*: TaskId
    priority*: TaskPriority
    dependencies*: HashSet[TaskId]
    state*: Atomic[TaskState]
    constraints*: seq[ResourceConstraint]
    creationTime*: MonoTime
    startTime*: MonoTime
    endTime*: MonoTime
    progressCallback*: proc(progress: float)
    result*: Option[T]
    error*: Option[ref CatchableError]
  
  TaskProc*[T] = proc(): Result[T, ref CatchableError]
  
  SimpleTask*[T] = ref object of Task[T]
    ## Task with execution function
    taskProc*: TaskProc[T]
  
  AsyncTask*[T] = ref object of Task[T]
    ## Task with async execution
    asyncTaskProc*: proc(): Future[Result[T, ref CatchableError]]
  
  ExecutionPolicy* = enum
    ## Task execution policies
    epFifo                # First in, first out
    epLifo                # Last in, first out
    epPriority            # Highest priority first
    epDeadline            # Earliest deadline first
    epFair                # Fair scheduling among task sources
    epWorkStealing        # Work stealing between workers
  
  RejectionPolicy* = enum
    ## Policy for handling task rejection
    rpAbort               # Abort task with error
    rpRequeue             # Put task back in queue
    rpCallerRuns          # Execute on caller thread
    rpDiscard             # Discard the task silently
  
  ShutdownPolicy* = enum
    ## Policy for handling executor shutdown
    spAwaitCompletion     # Wait for all tasks to complete
    spAwaitTermination    # Wait for termination timeout
    spForceTermination    # Terminate immediately
  
  ExecutorStats* = object
    ## Executor statistics
    activeWorkers*: int
    queuedTasks*: int
    completedTasks*: int
    failedTasks*: int
    cancelledTasks*: int
    rejectedTasks*: int
    averageWaitTime*: Duration
    averageExecutionTime*: Duration
    currentExecution*: int
  
  Executor*[T] = ref object of Pattern
    ## Task executor with configurable policies
    maxWorkers*: int
    activeWorkers: Atomic[int]
    policy*: ExecutionPolicy
    rejectionPolicy*: RejectionPolicy
    shutdownPolicy*: ShutdownPolicy
    taskQueue: Deque[Task[T]]
    queuedTaskIds: HashSet[TaskId]
    runningTasks: Table[TaskId, Task[T]]
    completedTasks: Table[TaskId, Task[T]]
    lock: Lock
    condition: Cond
    shutdown: Atomic[bool]
    logger: Logger
    metrics: MetricsRegistry
    resourceMonitor: ResourceMonitor
    workerThreadIds: seq[ThreadId]
    cancelRequests: HashSet[TaskId]
    pendingDependencies: Table[TaskId, HashSet[TaskId]]
    taskCreationCounter: Atomic[int64]
  
  ExecutorConfig* = object
    ## Configuration for executor
    maxWorkers*: int
    policy*: ExecutionPolicy
    rejectionPolicy*: RejectionPolicy
    shutdownPolicy*: ShutdownPolicy
    queueCapacity*: int
    monitorInterval*: int
    enablePriority*: bool
    enableWorkStealing*: bool
  
  ResourceMonitor* = ref object
    ## Monitors resource availability
    logger: Logger
    cpuUsage: float
    memoryUsage: float
    lastUpdateTime: MonoTime
    updateIntervalMs: int
  
  ExecutorEvent* = enum
    ## Events emitted by executor
    eeTaskSubmitted
    eeTaskStarted
    eeTaskCompleted
    eeTaskFailed
    eeTaskCancelled
    eeTaskRejected
    eeExecutorShutdown
  
  ExecutorEventCallback* = proc(executor: RootRef, eventType: ExecutorEvent, taskId: TaskId)

# TaskId implementation
proc `$`*(id: TaskId): string = $id.int64
proc `==`*(a, b: TaskId): bool {.borrow.}
proc `<`*(a, b: TaskId): bool {.borrow.}
proc hash*(id: TaskId): Hash {.borrow.}

proc newTaskId*(): TaskId =
  ## Generate a new unique TaskId
  var counter {.global.}: Atomic[int64]
  counter.atomicInc(1, 1)
  TaskId(counter.load)

# Task base implementation
proc newTask*[T](priority = tpNormal): Task[T] =
  ## Create a new base task
  result = Task[T](
    id: newTaskId(),
    priority: priority,
    dependencies: initHashSet[TaskId](),
    state: Atomic[TaskState](tsPending.int),
    constraints: @[],
    creationTime: getMonoTime(),
    startTime: MonoTime(),
    endTime: MonoTime()
  )

proc getState*[T](task: Task[T]): TaskState =
  ## Get current task state
  TaskState(task.state.load(moRelaxed))

proc setState*[T](task: Task[T], state: TaskState) =
  ## Set task state
  task.state.store(state.int, moRelaxed)

proc addDependency*[T](task: Task[T], dependency: TaskId): Task[T] =
  ## Add dependency to task
  task.dependencies.incl(dependency)
  task

proc addConstraint*[T](task: Task[T], constraint: ResourceConstraint): Task[T] =
  ## Add resource constraint
  task.constraints.add(constraint)
  task

proc setProgressCallback*[T](task: Task[T], callback: proc(progress: float)): Task[T] =
  ## Set progress reporting callback
  task.progressCallback = callback
  task

proc reportProgress*[T](task: Task[T], progress: float) =
  ## Report progress
  if not task.progressCallback.isNil:
    task.progressCallback(progress)

proc isComplete*[T](task: Task[T]): bool =
  ## Check if task completed (succeeded, failed or cancelled)
  let state = task.getState()
  state in [tsSucceeded, tsFailed, tsCancelled]

proc hasDependencies*[T](task: Task[T]): bool =
  ## Check if task has dependencies
  task.dependencies.len > 0

# Specific task implementations
proc newSimpleTask*[T](taskProc: TaskProc[T], priority = tpNormal): SimpleTask[T] =
  ## Create a task with execution function
  result = SimpleTask[T](
    id: newTaskId(),
    priority: priority,
    dependencies: initHashSet[TaskId](),
    state: Atomic[TaskState](tsPending.int),
    constraints: @[],
    creationTime: getMonoTime(),
    startTime: MonoTime(),
    endTime: MonoTime(),
    taskProc: taskProc
  )

proc execute*[T](task: SimpleTask[T]): Result[T, ref CatchableError] =
  ## Execute the task
  try:
    if task.getState() == tsCancelled:
      return Result[T, ref CatchableError].err(
        (ref CatchableError)(msg: "Task was cancelled")
      )
    
    task.setState(tsRunning)
    task.startTime = getMonoTime()
    
    let result = task.taskProc()
    task.endTime = getMonoTime()
    
    if result.isOk:
      task.result = some(result.get())
      task.setState(tsSucceeded)
    else:
      task.error = some(result.error)
      task.setState(tsFailed)
    
    result
    
  except CatchableError as e:
    task.error = some(e)
    task.setState(tsFailed)
    task.endTime = getMonoTime()
    
    Result[T, ref CatchableError].err(e)

proc newAsyncTask*[T](taskProc: proc(): Future[Result[T, ref CatchableError]], 
                    priority = tpNormal): AsyncTask[T] =
  ## Create a task with async execution
  result = AsyncTask[T](
    id: newTaskId(),
    priority: priority,
    dependencies: initHashSet[TaskId](),
    state: Atomic[TaskState](tsPending.int),
    constraints: @[],
    creationTime: getMonoTime(),
    startTime: MonoTime(),
    endTime: MonoTime(),
    asyncTaskProc: taskProc
  )

proc execute*[T](task: AsyncTask[T]): Future[Result[T, ref CatchableError]] {.async.} =
  ## Execute the async task
  try:
    if task.getState() == tsCancelled:
      return Result[T, ref CatchableError].err(
        (ref CatchableError)(msg: "Task was cancelled")
      )
    
    task.setState(tsRunning)
    task.startTime = getMonoTime()
    
    let futureResult = await task.asyncTaskProc()
    task.endTime = getMonoTime()
    
    if futureResult.isOk:
      task.result = some(futureResult.get())
      task.setState(tsSucceeded)
    else:
      task.error = some(futureResult.error)
      task.setState(tsFailed)
    
    return futureResult
    
  except CatchableError as e:
    task.error = some(e)
    task.setState(tsFailed)
    task.endTime = getMonoTime()
    
    return Result[T, ref CatchableError].err(e)

# ResourceMonitor implementation
proc newResourceMonitor*(logger: Logger = nil, intervalMs = 1000): ResourceMonitor =
  ## Create resource monitor
  result = ResourceMonitor(
    logger: logger,
    cpuUsage: 0.0,
    memoryUsage: 0.0,
    lastUpdateTime: getMonoTime(),
    updateIntervalMs: intervalMs
  )

proc update*(monitor: ResourceMonitor) =
  ## Update resource usage information
  let now = getMonoTime()
  if now - monitor.lastUpdateTime > initDuration(milliseconds = monitor.updateIntervalMs):
    # In real implementation, get actual CPU and memory usage
    monitor.cpuUsage = 0.5  # Placeholder
    monitor.memoryUsage = 0.4  # Placeholder
    
    if not monitor.logger.isNil:
      monitor.logger.debug(&"Resource usage: CPU {monitor.cpuUsage:.2f}, Memory {monitor.memoryUsage:.2f}")
    
    monitor.lastUpdateTime = now

proc canExecute*(monitor: ResourceMonitor, task: Task): bool =
  ## Check if resources are available for task
  for constraint in task.constraints:
    if constraint of CpuConstraint:
      let cpuConstraint = CpuConstraint(constraint)
      if monitor.cpuUsage > 0.8 and cpuConstraint.cores > 1:
        return false
    
    elif constraint of MemoryConstraint:
      let memConstraint = MemoryConstraint(constraint)
      if monitor.memoryUsage > 0.9 and memConstraint.megabytes > 100:
        return false
  
  true

# Executor implementation
proc defaultConfig*(): ExecutorConfig =
  ## Default executor configuration
  result = ExecutorConfig(
    maxWorkers: 4,
    policy: epPriority,
    rejectionPolicy: rpAbort,
    shutdownPolicy: spAwaitCompletion,
    queueCapacity: 100,
    monitorInterval: 1000,
    enablePriority: true,
    enableWorkStealing: false
  )

proc newExecutor*[T](config = defaultConfig()): Executor[T] =
  ## Create a new executor
  result = Executor[T](
    name: "Executor",
    kind: pkBehavioral,
    description: "Modern Executor pattern for task execution management",
    maxWorkers: config.maxWorkers,
    activeWorkers: Atomic[int](0),
    policy: config.policy,
    rejectionPolicy: config.rejectionPolicy,
    shutdownPolicy: config.shutdownPolicy,
    taskQueue: initDeque[Task[T]](),
    queuedTaskIds: initHashSet[TaskId](),
    runningTasks: initTable[TaskId, Task[T]](),
    completedTasks: initTable[TaskId, Task[T]](),
    cancelRequests: initHashSet[TaskId](),
    pendingDependencies: initTable[TaskId, HashSet[TaskId]](),
    taskCreationCounter: Atomic[int64](0),
    shutdown: Atomic[bool](false)
  )
  
  initLock(result.lock)
  initCond(result.condition)

proc withLogging*[T](executor: Executor[T], logger: Logger): Executor[T] =
  ## Add logging to executor
  executor.logger = logger
  executor

proc withMetrics*[T](executor: Executor[T], metrics: MetricsRegistry): Executor[T] =
  ## Add metrics collection
  executor.metrics = metrics
  executor

proc withResourceMonitor*[T](executor: Executor[T], 
                           monitor: ResourceMonitor): Executor[T] =
  ## Add resource monitoring
  executor.resourceMonitor = monitor
  executor

proc submit*[T](executor: Executor[T], task: Task[T]): Result[TaskId, ref CatchableError] =
  ## Submit a task for execution
  if executor.shutdown.load(moRelaxed):
    return Result[TaskId, ref CatchableError].err(
      (ref CatchableError)(msg: "Executor is shutting down")
    )
  
  if executor.pendingDependencies.hasKey(task.id) or executor.queuedTaskIds.contains(task.id) or
     executor.runningTasks.hasKey(task.id):
    return Result[TaskId, ref CatchableError].err(
      (ref CatchableError)(msg: "Task already submitted")
    )
  
  if task.hasDependencies():
    # Check for unresolved dependencies
    var unresolvedDeps = initHashSet[TaskId]()
    
    for depId in task.dependencies:
      if not executor.completedTasks.hasKey(depId) or 
         executor.completedTasks[depId].getState() != tsSucceeded:
        unresolvedDeps.incl(depId)
    
    if unresolvedDeps.len > 0:
      # Track this task as depending on these tasks
      executor.pendingDependencies[task.id] = unresolvedDeps
      
      if not executor.logger.isNil:
        executor.logger.debug(&"Task {task.id} has unresolved dependencies: {unresolvedDeps}")
      
      return Result[TaskId, ref CatchableError].ok(task.id)
  
  # Task has no dependencies or all resolved
  withLock(executor.lock):
    # Check if queue is full
    if executor.taskQueue.len >= 100 and 
       executor.rejectionPolicy == rpAbort:
      return Result[TaskId, ref CatchableError].err(
        (ref CatchableError)(msg: "Task queue is full")
      )
    
    # Add to queue
    executor.taskQueue.addLast(task)
    executor.queuedTaskIds.incl(task.id)
    
    # Notify worker threads
    executor.condition.signal()
  
  if not executor.logger.isNil:
    executor.logger.debug(&"Task {task.id} submitted for execution")
  
  if not executor.metrics.isNil:
    executor.metrics.increment("executor.tasks.submitted")
  
  Result[TaskId, ref CatchableError].ok(task.id)

proc submitSimpleTask*[T](executor: Executor[T], 
                        taskProc: TaskProc[T],
                        priority = tpNormal): Result[TaskId, ref CatchableError] =
  ## Convenience method to create and submit a simple task
  let task = newSimpleTask[T](taskProc, priority)
  executor.submit(task)

proc cancelTask*[T](executor: Executor[T], taskId: TaskId): bool =
  ## Request task cancellation
  # Check completed tasks first
  if executor.completedTasks.hasKey(taskId):
    if executor.completedTasks[taskId].getState() == tsCancelled:
      return true
    return false  # Can't cancel completed task
  
  # Check running tasks
  if executor.runningTasks.hasKey(taskId):
    # Mark for cancellation
    executor.cancelRequests.incl(taskId)
    return true
  
  # Check queued tasks
  withLock(executor.lock):
    for i in 0..<executor.taskQueue.len:
      if executor.taskQueue[i].id == taskId:
        executor.taskQueue[i].setState(tsCancelled)
        return true
  
  false  # Task not found

proc getTask*[T](executor: Executor[T], taskId: TaskId): Option[Task[T]] =
  ## Get task by ID
  if executor.completedTasks.hasKey(taskId):
    return some(executor.completedTasks[taskId])
  
  if executor.runningTasks.hasKey(taskId):
    return some(executor.runningTasks[taskId])
  
  withLock(executor.lock):
    for task in executor.taskQueue:
      if task.id == taskId:
        return some(task)
  
  none(Task[T])

proc getTaskState*[T](executor: Executor[T], taskId: TaskId): Option[TaskState] =
  ## Get task state by ID
  let taskOpt = executor.getTask(taskId)
  if taskOpt.isSome:
    return some(taskOpt.get().getState())
  
  none(TaskState)

proc getTaskResult*[T](executor: Executor[T], taskId: TaskId): Option[T] =
  ## Get completed task result
  if executor.completedTasks.hasKey(taskId):
    return executor.completedTasks[taskId].result
  
  none(T)

proc getStats*[T](executor: Executor[T]): ExecutorStats =
  ## Get executor statistics
  result = ExecutorStats(
    activeWorkers: executor.activeWorkers.load(moRelaxed),
    queuedTasks: 0,
    completedTasks: executor.completedTasks.len,
    failedTasks: 0,
    cancelledTasks: 0,
    rejectedTasks: 0
  )
  
  withLock(executor.lock):
    result.queuedTasks = executor.taskQueue.len
  
  # Count task states
  for _, task in executor.completedTasks:
    let state = task.getState()
    case state:
    of tsFailed: inc result.failedTasks
    of tsCancelled: inc result.cancelledTasks
    else: discard
  
  # Calculate times
  var 
    totalWaitTime = initDuration()
    totalExecTime = initDuration()
    count = 0
  
  for _, task in executor.completedTasks:
    if task.endTime.ticks > 0:
      totalExecTime += task.endTime - task.startTime
      totalWaitTime += task.startTime - task.creationTime
      inc count
  
  if count > 0:
    result.averageWaitTime = initDuration(
      (totalWaitTime.inNanoseconds div count).int64
    )
    result.averageExecutionTime = initDuration(
      (totalExecTime.inNanoseconds div count).int64
    )

proc processCompletedTask*[T](executor: Executor[T], task: Task[T]) =
  ## Process a completed task and update dependencies
  if task.id in executor.pendingDependencies:
    executor.pendingDependencies.del(task.id)
  
  # Update tasks that depend on this one
  var readyTasks: seq[Task[T]] = @[]
  
  for taskId, dependencies in executor.pendingDependencies:
    if task.id in dependencies:
      dependencies.excl(task.id)
      
      if dependencies.len == 0:
        # All dependencies satisfied, task is ready for execution
        let taskOpt = executor.getTask(taskId)
        if taskOpt.isSome:
          readyTasks.add(taskOpt.get())
          executor.pendingDependencies.del(taskId)
  
  # Submit ready tasks
  for task in readyTasks:
    discard executor.submit(task)

proc workerLoop*[T](executor: Executor[T]) {.thread.} =
  ## Worker thread loop
  while true:
    var task: Task[T]
    
    # Get task from queue
    withLock(executor.lock):
      while executor.taskQueue.len == 0:
        if executor.shutdown.load(moRelaxed):
          executor.activeWorkers.atomicDec()
          return
        executor.condition.wait(executor.lock)
      
      task = executor.taskQueue.popFirst()
      executor.queuedTaskIds.excl(task.id)
      executor.runningTasks[task.id] = task
    
    # Check for cancellation
    if task.id in executor.cancelRequests:
      task.setState(tsCancelled)
      executor.cancelRequests.excl(task.id)
      
      withLock(executor.lock):
        executor.runningTasks.del(task.id)
        executor.completedTasks[task.id] = task
      
      if not executor.logger.isNil:
        executor.logger.debug(&"Task {task.id} cancelled")
      
      if not executor.metrics.isNil:
        executor.metrics.increment("executor.tasks.cancelled")
      
      executor.processCompletedTask(task)
      continue
    
    # Check resource constraints
    if not executor.resourceMonitor.isNil:
      executor.resourceMonitor.update()
      if not executor.resourceMonitor.canExecute(task):
        # Requeue task
        withLock(executor.lock):
          executor.taskQueue.addFirst(task)
          executor.queuedTaskIds.incl(task.id)
          executor.runningTasks.del(task.id)
        continue
    
    # Execute task
    if not executor.logger.isNil:
      executor.logger.debug(&"Executing task {task.id}")
    
    if not executor.metrics.isNil:
      executor.metrics.increment("executor.tasks.started")
    
    if task of SimpleTask[T]:
      let simpleTask = SimpleTask[T](task)
      discard simpleTask.execute()
    
    elif task of AsyncTask[T]:
      let asyncTask = AsyncTask[T](task)
      discard waitFor asyncTask.execute()
    
    # Update task status
    withLock(executor.lock):
      executor.runningTasks.del(task.id)
      executor.completedTasks[task.id] = task
    
    # Log and metrics
    if not executor.logger.isNil:
      let state = task.getState()
      executor.logger.debug(&"Task {task.id} completed with state {state}")
    
    if not executor.metrics.isNil:
      let state = task.getState()
      case state:
      of tsSucceeded:
        executor.metrics.increment("executor.tasks.succeeded")
      of tsFailed:
        executor.metrics.increment("executor.tasks.failed")
      else:
        discard
    
    # Process dependencies
    executor.processCompletedTask(task)

proc start*[T](executor: Executor[T]): Result[void, ref CatchableError] =
  ## Start the executor
  if executor.shutdown.load(moRelaxed):
    return Result[void, ref CatchableError].err(
      (ref CatchableError)(msg: "Executor is shutting down or already shutdown")
    )
  
  if executor.activeWorkers.load(moRelaxed) > 0:
    return Result[void, ref CatchableError].ok()  # Already started
  
  if not executor.logger.isNil:
    executor.logger.info(&"Starting executor with {executor.maxWorkers} workers")
  
  # Create and start worker threads
  executor.workerThreadIds = newSeq[ThreadId](executor.maxWorkers)
  
  for i in 0..<executor.maxWorkers:
    var thread: Thread[Executor[T]]
    createThread(thread, workerLoop[T], executor)
    executor.workerThreadIds[i] = thread.threadId
    executor.activeWorkers.atomicInc()
  
  if not executor.metrics.isNil:
    executor.metrics.gauge("executor.workers.active", executor.maxWorkers.float)
  
  Result[void, ref CatchableError].ok()

proc shutdown*[T](executor: Executor[T], 
                 policy = spAwaitCompletion): Result[void, ref CatchableError] =
  ## Shutdown the executor
  if executor.shutdown.load(moRelaxed):
    return Result[void, ref CatchableError].ok()  # Already shutdown
  
  if not executor.logger.isNil:
    executor.logger.info(&"Shutting down executor with policy {policy}")
  
  executor.shutdown.store(true, moRelease)
  
  case policy:
  of spAwaitCompletion:
    # Wait for all tasks to complete
    while true:
      let stats = executor.getStats()
      if stats.queuedTasks == 0 and stats.activeWorkers == 0:
        break
      sleep(100)
  
  of spAwaitTermination:
    # Wait with timeout
    for i in 0..10:  # Wait max 1 second
      let stats = executor.getStats()
      if stats.queuedTasks == 0 and stats.activeWorkers == 0:
        break
      sleep(100)
  
  of spForceTermination:
    # Force immediate shutdown
    discard
  
  # Signal all threads
  withLock(executor.lock):
    executor.condition.broadcast()
  
  if not executor.logger.isNil:
    executor.logger.info("Executor shutdown complete")
  
  if not executor.metrics.isNil:
    executor.metrics.gauge("executor.workers.active", 0)
  
  Result[void, ref CatchableError].ok()

proc joinAll*[T](executor: Executor[T]): Result[void, ref CatchableError] =
  ## Wait for all threads to complete
  for i in 0..<executor.workerThreadIds.len:
    joinThread(Thread[Executor[T]](threadId: executor.workerThreadIds[i]))
  
  if not executor.logger.isNil:
    executor.logger.info("All worker threads joined")
  
  Result[void, ref CatchableError].ok()

# Helper templates
template execute*[T](executor: Executor[T], taskProc: untyped): untyped =
  ## Execute a task and wait for result
  let task = newSimpleTask[T](
    proc(): Result[T, ref CatchableError] = taskProc
  )
  discard executor.submit(task)
  # In real implementation, would wait for completion
  # For now, just retrieve the task
  let taskOpt = executor.getTask(task.id)
  if taskOpt.isSome:
    let completedTask = taskOpt.get()
    if completedTask.isComplete() and completedTask.result.isSome:
      completedTask.result.get()
    else:
      raise (ref CatchableError)(msg: "Task execution failed")
  else:
    raise (ref CatchableError)(msg: "Task not found")

# High-level executor utilities
proc mapReduce*[T, R](executor: Executor[R], 
                     items: openArray[T], 
                     mapFn: proc(item: T): R,
                     reduceFn: proc(items: seq[R]): R): R =
  ## Execute map-reduce operation using executor
  var tasks: seq[Task[R]] = @[]
  var results: seq[R] = @[]
  
  # Create map tasks
  for item in items:
    let mapTask = newSimpleTask[R](
      proc(): Result[R, ref CatchableError] =
        try:
          Result[R, ref CatchableError].ok(mapFn(item))
        except CatchableError as e:
          Result[R, ref CatchableError].err(e)
    )
    tasks.add(mapTask)
    discard executor.submit(mapTask)
  
  # Wait for all tasks
  for task in tasks:
    # In real implementation, would wait for completion
    let taskOpt = executor.getTask(task.id)
    if taskOpt.isSome:
      let completedTask = taskOpt.get()
      if completedTask.isComplete() and completedTask.result.isSome:
        results.add(completedTask.result.get())
  
  # Reduce results
  reduceFn(results)

# Extension for parallel execution
proc runInParallel*[T](executor: Executor[T],
                     tasks: seq[TaskProc[T]]): seq[Option[T]] =
  ## Run multiple tasks in parallel
  result = newSeq[Option[T]](tasks.len)
  var taskIds = newSeq[TaskId](tasks.len)
  
  # Submit all tasks
  for i, taskProc in tasks:
    let task = newSimpleTask[T](taskProc)
    let taskResult = executor.submit(task)
    if taskResult.isOk:
      taskIds[i] = taskResult.get()
  
  # Collect results
  for i, taskId in taskIds:
    let taskState = executor.getTaskState(taskId)
    if taskState.isSome and taskState.get() == tsSucceeded:
      result[i] = executor.getTaskResult(taskId)

# More advanced scheduling support
proc scheduleAtFixedRate*[T](executor: Executor[T],
                           taskProc: TaskProc[T],
                           initialDelay, period: int): Result[TaskId, ref CatchableError] =
  ## Schedule task to run at a fixed rate
  # This is a simplified version without real scheduling
  # In a real implementation, would create a timer
  let task = newSimpleTask[T](taskProc)
  executor.submit(task)