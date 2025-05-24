## Test suite for Executor pattern

import std/[unittest, strformat, os]
import results
import nim_libaspects/[logging, metrics]
import nim_design_patterns/modern/executor

# Helper proc to export for test_all.nim
proc runTests*(): int =
  # Return number of failures
  let results = unittest.runTests()
  results.failures

type CustomError = ref object of CatchableError

suite "Executor Pattern Tests":
  setup:
    # Create test executor
    let executor = newExecutor[string]()
    let logger = newLogger("TestLogger")
    logger.addHandler(proc(level: LogLevel, msg: string, ctx: JsonNode) = discard)
    
    discard executor.withLogging(logger)
      .withMetrics(newMetricsRegistry())
      .withResourceMonitor(newResourceMonitor(logger))
  
  test "Executor creates and manages tasks":
    # Create test task
    let task = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        Result[string, ref CatchableError].ok("Task completed")
    )
    
    # Submit task
    let submitResult = executor.submit(task)
    check submitResult.isOk()
    
    # Start executor
    let startResult = executor.start()
    check startResult.isOk()
    
    # Small delay to let task complete
    sleep(100)
    
    # Check if task completed
    let taskState = executor.getTaskState(task.id)
    check taskState.isSome()
    check taskState.get() == tsSucceeded
    
    # Check result
    let taskResult = executor.getTaskResult(task.id)
    check taskResult.isSome()
    check taskResult.get() == "Task completed"
    
    # Shutdown executor
    let shutdownResult = executor.shutdown()
    check shutdownResult.isOk()
  
  test "Executor handles dependencies between tasks":
    # Task 1 succeeds
    let task1 = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        sleep(10)  # Small delay to ensure ordering
        Result[string, ref CatchableError].ok("Task 1 result")
    )
    
    # Task 2 depends on task 1
    let task2 = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        Result[string, ref CatchableError].ok("Task 2 result")
    )
    
    # Set dependency
    task2.addDependency(task1.id)
    
    # Submit tasks (order shouldn't matter as dependency controls execution)
    discard executor.submit(task2)
    discard executor.submit(task1)
    
    # Start executor
    discard executor.start()
    
    # Wait for completion
    sleep(100)
    
    # Both tasks should complete successfully
    check executor.getTaskState(task1.id).get() == tsSucceeded
    check executor.getTaskState(task2.id).get() == tsSucceeded
    
    # Results should be as expected
    check executor.getTaskResult(task1.id).get() == "Task 1 result"
    check executor.getTaskResult(task2.id).get() == "Task 2 result"
    
    discard executor.shutdown()
  
  test "Executor handles task failure":
    # Task that fails
    let failingTask = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        Result[string, ref CatchableError].err(
          (ref CatchableError)(msg: "Intentional failure")
        )
    )
    
    # Submit and run task
    discard executor.submit(failingTask)
    discard executor.start()
    
    # Wait for completion
    sleep(50)
    
    # Task should be marked as failed
    check executor.getTaskState(failingTask.id).get() == tsFailed
    
    # No result should be available
    check executor.getTaskResult(failingTask.id).isNone()
    
    discard executor.shutdown()
  
  test "Executor handles task cancellation":
    # Long-running task
    let longTask = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        sleep(1000)  # 1 second sleep
        Result[string, ref CatchableError].ok("Long task completed")
    )
    
    # Submit task
    discard executor.submit(longTask)
    discard executor.start()
    
    # Wait a bit
    sleep(10)
    
    # Cancel task
    let cancelled = executor.cancelTask(longTask.id)
    check cancelled
    
    # Wait for cancellation to take effect
    sleep(50)
    
    # Task should be cancelled
    let state = executor.getTaskState(longTask.id)
    check state.isSome()
    check state.get() == tsCancelled
    
    discard executor.shutdown()
  
  test "Executor provides statistics":
    # Create 5 tasks
    var tasks: seq[Task[string]] = @[]
    for i in 1..5:
      let task = newSimpleTask[string](
        proc(): Result[string, ref CatchableError] =
          Result[string, ref CatchableError].ok(&"Task {i} result")
      )
      tasks.add(task)
      discard executor.submit(task)
    
    # Start executor
    discard executor.start()
    
    # Wait for tasks to complete
    sleep(100)
    
    # Get stats
    let stats = executor.getStats()
    
    # Should have 5 completed tasks
    check stats.completedTasks == 5
    check stats.failedTasks == 0
    check stats.queuedTasks == 0
    
    discard executor.shutdown()
  
  test "Executor handles resource constraints":
    # Create task with CPU constraint
    let task = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        Result[string, ref CatchableError].ok("Task with constraints")
    )
    
    let cpuConstraint = CpuConstraint(
      name: "CPU",
      cores: 2
    )
    
    task.addConstraint(cpuConstraint)
    
    # Submit and run
    discard executor.submit(task)
    discard executor.start()
    
    # Wait for completion
    sleep(50)
    
    # Task should complete (in test environment, constraints should be met)
    check executor.getTaskState(task.id).get() == tsSucceeded
    
    discard executor.shutdown()
  
  test "Executor handles async tasks":
    # Using a simulated async task for testing
    let asyncTask = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        # Simulate async behavior
        sleep(20)
        Result[string, ref CatchableError].ok("Async task completed")
    )
    
    # Submit and run
    discard executor.submit(asyncTask)
    discard executor.start()
    
    # Wait for completion
    sleep(50)
    
    # Task should complete successfully
    check executor.getTaskState(asyncTask.id).get() == tsSucceeded
    check executor.getTaskResult(asyncTask.id).get() == "Async task completed"
    
    discard executor.shutdown()
  
  test "Executor supports task priorities":
    # Low priority task with delay
    let lowPriorityTask = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        sleep(30)
        Result[string, ref CatchableError].ok("Low priority")
    )
    lowPriorityTask.priority = tpLow
    
    # High priority task with no delay
    let highPriorityTask = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        Result[string, ref CatchableError].ok("High priority")
    )
    highPriorityTask.priority = tpHigh
    
    # Submit tasks (low priority first, but high should execute first)
    discard executor.submit(lowPriorityTask)
    discard executor.submit(highPriorityTask)
    
    # Start executor
    discard executor.start()
    
    # Small delay to let at least high priority task complete
    sleep(10)
    
    # High priority task should complete first
    check executor.getTaskState(highPriorityTask.id).get() == tsSucceeded
    
    # Complete execution
    sleep(50)
    check executor.getTaskState(lowPriorityTask.id).get() == tsSucceeded
    
    discard executor.shutdown()
  
  test "Executor run in parallel":
    # Create multiple tasks
    var taskProcs: seq[TaskProc[string]] = @[]
    for i in 1..5:
      let idx = i  # Capture loop variable
      let taskProc = proc(): Result[string, ref CatchableError] =
        Result[string, ref CatchableError].ok(&"Result {idx}")
      taskProcs.add(taskProc)
    
    # Run in parallel
    let results = executor.runInParallel(taskProcs)
    
    # Check results
    check results.len == 5
    for i in 0..<5:
      check results[i].isSome()
      check results[i].get() == &"Result {i+1}"
    
    discard executor.shutdown()

suite "MapReduce with Executor Tests":
  test "Executor supports MapReduce pattern":
    # Create executor
    let executor = newExecutor[int]()
    discard executor.start()
    
    # Input data
    let numbers = @[1, 2, 3, 4, 5]
    
    # Map function: square each number
    let mapFn = proc(n: int): int = n * n
    
    # Reduce function: sum the squares
    let reduceFn = proc(items: seq[int]): int =
      var sum = 0
      for item in items:
        sum += item
      sum
    
    # Execute map-reduce
    let result = executor.mapReduce(numbers, mapFn, reduceFn)
    
    # Expected: sum of squares = 1^2 + 2^2 + 3^2 + 4^2 + 5^2 = 55
    check result == 55
    
    discard executor.shutdown()

suite "Executor Configuration Tests":
  test "Executor supports custom configuration":
    # Create custom config
    let config = ExecutorConfig(
      maxWorkers: 2,
      policy: epFifo,  # First in, first out
      rejectionPolicy: rpAbort,
      shutdownPolicy: spAwaitCompletion,
      queueCapacity: 50,
      monitorInterval: 500,
      enablePriority: false,
      enableWorkStealing: false
    )
    
    # Create executor with config
    let executor = newExecutor[string](config)
    
    # Verify configuration
    check executor.maxWorkers == 2
    check executor.policy == epFifo
    check executor.rejectionPolicy == rpAbort
    check executor.shutdownPolicy == spAwaitCompletion
    
    discard executor.start()
    
    # Submit a task to verify it works
    let task = newSimpleTask[string](
      proc(): Result[string, ref CatchableError] =
        Result[string, ref CatchableError].ok("Config test")
    )
    
    discard executor.submit(task)
    
    # Wait for completion
    sleep(50)
    
    # Task should complete
    check executor.getTaskState(task.id).get() == tsSucceeded
    
    discard executor.shutdown()

when isMainModule:
  unittest.run()