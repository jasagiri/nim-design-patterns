## Test suite for Saga pattern

import unittest
import std/[strformat, tables, options, times, json]
import nim_libaspects/[logging, errors, events, metrics]
import nim_design_patterns/modern/saga

# Helper proc to export for test_all.nim
proc runTests*(): int =
  # Return number of failures
  let results = unittest.runTests()
  results.failures

type
  # Test context and state for saga
  TestContext = object
    resources*: seq[string]
    initialized*: bool
  
  TestState = object
    values*: Table[string, string]
    counter*: int

# Our test errors
type TestSagaError = ref object of CatchableError

suite "Saga Pattern Tests":
  setup:
    # Initialize fresh test objects for each test
    var context = TestContext(resources: @[], initialized: true)
    var state = TestState(values: initTable[string, string](), counter: 0)
    
    # Test metrics and logging
    let metrics = newMetricsRegistry()
    let logger = newLogger("TestLogger")
    let eventBus = newEventBus()
    
    # Capture log messages
    var logMessages: seq[string] = @[]
    logger.addHandler(proc(level: LogLevel, msg: string, ctx: JsonNode) =
      logMessages.add(msg)
    )
    
    # Capture events
    var events: seq[Event] = @[]
    eventBus.subscribe("saga.*", proc(e: Event) =
      events.add(e)
    )
    
    # Create a saga definition
    let sagaDefinition = newSagaDefinition[TestContext, TestState]("TestSaga")
      .withLogging(logger)
      .withMetrics(metrics)
      .withEventBus(eventBus)
    
    # Create steps with actions and compensations
    # Step 1: Reserve resources
    let step1 = newSagaStep[TestContext, TestState](
      "ReserveResources",
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        # Action: reserve a resource
        st.values["resource"] = "reserved"
        ctx.resources.add("database")
        st.counter += 1
        Result[void, ref CatchableError].ok()
      ,
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        # Compensation: release the resource
        st.values["resource"] = "released"
        if ctx.resources.len > 0:
          ctx.resources.delete(ctx.resources.find("database"))
        st.counter -= 1
        Result[void, ref CatchableError].ok()
    )
    
    # Step 2: Process data (depends on step 1)
    let step2 = newSagaStep[TestContext, TestState](
      "ProcessData",
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        # Action: process data
        if "resource" notin st.values or st.values["resource"] != "reserved":
          let error = new TestSagaError
          error.msg = "Cannot process data: resource not reserved"
          return Result[void, ref CatchableError].err(error)
        
        st.values["data"] = "processed"
        st.counter += 1
        Result[void, ref CatchableError].ok()
      ,
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        # Compensation: undo processing
        st.values["data"] = "unprocessed"
        st.counter -= 1
        Result[void, ref CatchableError].ok()
    )
    
    # Add the steps to the saga
    sagaDefinition.addStep(step1)
    sagaDefinition.addStep(step2.dependsOn(step1.id))
    
    # Step 3: Notify (always fails for failure testing)
    let failingStep = newSagaStep[TestContext, TestState](
      "NotifyFailure",
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        # Action: always fails
        let error = new TestSagaError
        error.msg = "Step intentionally failed"
        Result[void, ref CatchableError].err(error)
      ,
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        # Compensation: nothing to do
        Result[void, ref CatchableError].ok()
    )
    
    # Create saga coordinator
    let coordinator = newSagaCoordinator[TestContext, TestState]()
      .withLogging(logger)
      .withMetrics(metrics)
      .withEventBus(eventBus)
      .registerSaga(sagaDefinition)
  
  test "Saga executes steps in order":
    # Execute saga
    let result = coordinator.executeSaga("TestSaga", context, state)
    
    # Check execution succeeded
    check result.isOk()
    let execution = result.get()
    
    # Check status
    check execution.status == ssCompleted
    
    # Check state was updated correctly
    check state.values["resource"] == "reserved"
    check state.values["data"] == "processed"
    check state.counter == 2
    
    # Check metrics and logs were captured
    check events.len > 0
    check logMessages.len > 0
    
    # Verify steps executed in correct order
    let steps = execution.executedSteps
    check steps.len == 2
    check steps[0].name == "ReserveResources"
    check steps[1].name == "ProcessData"
  
  test "Saga compensates on failure":
    # Add failing step to saga
    sagaDefinition.addStep(failingStep.dependsOn(step2.id))
    
    # Reset state
    state = TestState(values: initTable[string, string](), counter: 0)
    events = @[]
    logMessages = @[]
    
    # Execute saga (should fail at step 3)
    let result = coordinator.executeSaga("TestSaga", context, state)
    
    # Check saga failed but returned
    check result.isOk() # Saga execution returns OK even if saga failed
    let execution = result.get()
    
    # Check status is compensated
    check execution.status == ssCompensated
    
    # Check state was compensated correctly
    check state.values["resource"] == "released"
    check state.values["data"] == "unprocessed"
    check state.counter == 0
    
    # Check failing step was recorded
    check execution.failedStep.isSome()
    check execution.failedStep.get().name == "NotifyFailure"
    
    # Check events were published for failure and compensation
    var hasFailed = false
    var hasCompensated = false
    
    for event in events:
      if event.name == "saga.failed":
        hasFailed = true
      if event.name == "saga.compensated":
        hasCompensated = true
    
    check hasFailed
    check hasCompensated
  
  test "SagaDefinition correctly resolves dependencies":
    # Get initial steps (those with no dependencies)
    let initialSteps = sagaDefinition.getInitialSteps()
    
    # Should only have one initial step (ReserveResources)
    check initialSteps.len == 1
    check initialSteps[0].name == "ReserveResources"
    
    # Get next steps after step1
    let nextSteps = sagaDefinition.getNextSteps(step1.id)
    
    # Should find step2 (ProcessData)
    check nextSteps.len == 1
    check nextSteps[0].name == "ProcessData"
  
  test "Saga step can be retrieved by ID and name":
    let stepByName = sagaDefinition.getStep("ReserveResources")
    check stepByName.isSome()
    check stepByName.get().name == "ReserveResources"
    
    let id = stepByName.get().id
    let stepById = sagaDefinition.getStepById(id)
    check stepById.isSome()
    check stepById.get().name == "ReserveResources"
  
  test "Linear saga with sequential steps":
    # Create a linear saga using helper function
    let linearSaga = createLinearSaga[TestContext, TestState]("LinearSaga")
      .withLogging(logger)
      .withMetrics(metrics)
    
    # Add sequential steps
    linearSaga.addSequentialStep(
      "Step1",
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        st.counter += 1
        Result[void, ref CatchableError].ok()
      ,
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        st.counter -= 1
        Result[void, ref CatchableError].ok()
    )
    
    linearSaga.addSequentialStep(
      "Step2",
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        st.counter += 1
        Result[void, ref CatchableError].ok()
      ,
      proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
        st.counter -= 1
        Result[void, ref CatchableError].ok()
    )
    
    # Register saga with coordinator
    coordinator.registerSaga(linearSaga)
    
    # Reset state
    state = TestState(values: initTable[string, string](), counter: 0)
    
    # Execute linear saga
    let result = coordinator.executeSaga("LinearSaga", context, state)
    
    # Check execution succeeded
    check result.isOk()
    let execution = result.get()
    
    # Check counter incremented twice
    check state.counter == 2
    
    # Check steps executed in order
    check execution.executedSteps.len == 2
    check execution.executedSteps[0].name == "Step1"
    check execution.executedSteps[1].name == "Step2"
  
  test "Saga DSL creates valid saga":
    # Create saga using DSL
    let dslSaga = saga[TestContext, TestState]("DSLSaga"):
      step "StepA", 
        # Action
        proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
          st.counter += 1
          Result[void, ref CatchableError].ok()
        , 
        # Compensation
        proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
          st.counter -= 1
          Result[void, ref CatchableError].ok()
      
      step "StepB",
        # Action 
        proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
          st.counter += 1
          Result[void, ref CatchableError].ok()
        ,
        # Compensation
        proc(ctx: TestContext, st: TestState): Result[void, ref CatchableError] =
          st.counter -= 1
          Result[void, ref CatchableError].ok()
      
      # Set dependency
      dependsOn "StepA"
    
    # Add to coordinator
    coordinator.registerSaga(dslSaga)
    
    # Reset state
    state = TestState(values: initTable[string, string](), counter: 0)
    
    # Execute DSL saga
    let result = coordinator.executeSaga("DSLSaga", context, state)
    
    # Check execution succeeded
    check result.isOk()
    let execution = result.get()
    
    # Check counter incremented twice
    check state.counter == 2
    
    # Check steps executed in order
    check execution.executedSteps.len == 2
    check execution.executedSteps[0].name == "StepA"
    check execution.executedSteps[1].name == "StepB"
  
  test "SagaLog records and retrieves saga execution steps":
    # Create new saga log
    let sagaLog = newSagaLog()
    
    # Log saga execution (simplified example)
    let sagaId = newSagaId()
    let stepId = newSagaStepId()
    
    sagaLog.logSagaStarted(sagaId, "TestSaga")
    sagaLog.logStepStarted(sagaId, "TestSaga", stepId, "TestStep")
    sagaLog.logStepCompleted(sagaId, "TestSaga", stepId, "TestStep")
    
    # Different saga that's unfinished
    let unfinishedSagaId = newSagaId()
    sagaLog.logSagaStarted(unfinishedSagaId, "UnfinishedSaga")
    
    # Get unfinished sagas
    let unfinishedSagas = sagaLog.getUnfinishedSagas()
    
    # Should find the unfinished saga
    check unfinishedSagas.len == 1
    check unfinishedSagas[0] == $unfinishedSagaId
    
    # Get completed steps for the first saga
    let completedSteps = sagaLog.getCompletedSteps($sagaId)
    
    # Should find the completed step
    check completedSteps.len == 1
    check completedSteps[0] == $stepId

when isMainModule:
  unittest.run()