## Simplified test for the Saga pattern
##
## This test demonstrates the core concepts of the Saga pattern without external dependencies.
## In a real implementation, we would use the full saga.nim module.

import unittest
import std/[tables, options, strformat, random]

# Helper proc to export for test_all.nim
proc runTests*(): int =
  # Return number of failures
  let results = unittest.runTests()
  results.failures

# Initialize random seed for deterministic tests
randomize(42)

# Core type definitions for the Saga pattern
type
  SagaId = distinct string
  SagaStepId = distinct string
  
  SagaStepStatus = enum
    sssNotStarted
    sssExecuting
    sssSucceeded
    sssFailed
    sssCompensating
    sssCompensated
    sssSkipped
  
  SagaStatus = enum
    ssNotStarted
    ssInProgress
    ssCompleted
    ssCompensating
    ssFailed
    ssCompensated
  
  # Generic action and compensation functions
  SagaAction[C, S] = proc(context: C, state: S): bool
  SagaCompensation[C, S] = proc(context: C, state: S): bool
  
  # Step in a saga
  SagaStep[C, S] = ref object
    id: SagaStepId
    name: string
    action: SagaAction[C, S]
    compensation: SagaCompensation[C, S]
    status: SagaStepStatus
    dependencies: seq[SagaStepId]
  
  # Definition of a saga with its steps
  SagaDefinition[C, S] = ref object
    id: SagaId
    name: string
    steps: seq[SagaStep[C, S]]
    stepsByName: Table[string, SagaStep[C, S]]
  
  # Execution instance of a saga
  SagaExecution[C, S] = ref object
    id: SagaId
    definition: SagaDefinition[C, S]
    context: C
    state: S
    status: SagaStatus
    executedSteps: seq[SagaStep[C, S]]
    failedStep: Option[SagaStep[C, S]]

# String conversion for IDs
proc `$`*(id: SagaId): string = string(id)
proc `$`*(id: SagaStepId): string = string(id)

# Helper functions
proc newSagaId(): SagaId = SagaId("saga-" & $rand(100000))
proc newSagaStepId(): SagaStepId = SagaStepId("step-" & $rand(100000))

# Helper for creating steps
proc newSagaStep[C, S](name: string, action: SagaAction[C, S], compensation: SagaCompensation[C, S]): SagaStep[C, S] =
  SagaStep[C, S](
    id: newSagaStepId(),
    name: name,
    action: action,
    compensation: compensation,
    status: sssNotStarted,
    dependencies: @[]
  )

# Helper for creating saga definitions
proc newSagaDefinition[C, S](name: string): SagaDefinition[C, S] =
  SagaDefinition[C, S](
    id: newSagaId(),
    name: name,
    steps: @[],
    stepsByName: initTable[string, SagaStep[C, S]]()
  )

# Add a step to a saga
proc addStep[C, S](saga: SagaDefinition[C, S], step: SagaStep[C, S]): SagaDefinition[C, S] =
  result = saga
  result.steps.add(step)
  result.stepsByName[step.name] = step

# Add dependency to a step
proc dependsOn[C, S](step: SagaStep[C, S], dependency: SagaStep[C, S]): SagaStep[C, S] =
  result = step
  result.dependencies.add(dependency.id)

# Execute saga step
proc execute[C, S](step: SagaStep[C, S], context: C, state: S): bool =
  step.status = sssExecuting
  let success = step.action(context, state)
  
  if success:
    step.status = sssSucceeded
  else:
    step.status = sssFailed
  
  success

# Compensate saga step
proc compensate[C, S](step: SagaStep[C, S], context: C, state: S): bool =
  if step.status != sssSucceeded and step.status != sssFailed:
    step.status = sssSkipped
    return true
  
  step.status = sssCompensating
  let success = step.compensation(context, state)
  
  if success:
    step.status = sssCompensated
  
  success

# Create a new saga execution
proc newSagaExecution[C, S](definition: SagaDefinition[C, S], context: C, state: S): SagaExecution[C, S] =
  SagaExecution[C, S](
    id: newSagaId(),
    definition: definition,
    context: context,
    state: state,
    status: ssNotStarted,
    executedSteps: @[]
  )

# Execute a saga
proc execute[C, S](execution: SagaExecution[C, S]): bool =
  execution.status = ssInProgress
  
  # Execute each step in order
  for step in execution.definition.steps:
    let success = step.execute(execution.context, execution.state)
    execution.executedSteps.add(step)
    
    if not success:
      execution.status = ssFailed
      execution.failedStep = some(step)
      
      # Compensate in reverse order
      var stepsToCompensate = execution.executedSteps
      stepsToCompensate.reverse()
      
      execution.status = ssCompensating
      var allCompensated = true
      
      for compensateStep in stepsToCompensate:
        let compensateSuccess = compensateStep.compensate(execution.context, execution.state)
        if not compensateSuccess:
          allCompensated = false
      
      if allCompensated:
        execution.status = ssCompensated
      else:
        execution.status = ssFailed
      
      return false
  
  execution.status = ssCompleted
  true

# Test types
type
  TestContext = object
    resources: seq[string]
  
  TestState = object
    values: Table[string, string]
    counter: int

suite "Simplified Saga Pattern Tests":
  setup:
    # Initialize test objects
    var context = TestContext(resources: @[])
    var state = TestState(values: initTable[string, string](), counter: 0)
    
    # Create a saga definition
    let sagaDefinition = newSagaDefinition[TestContext, TestState]("TestSaga")
    
    # Step 1: Reserve resources
    let step1 = newSagaStep[TestContext, TestState](
      "ReserveResources",
      proc(ctx: TestContext, st: TestState): bool =
        # Action: reserve a resource
        st.values["resource"] = "reserved"
        ctx.resources.add("database")
        st.counter += 1
        true
      ,
      proc(ctx: TestContext, st: TestState): bool =
        # Compensation: release the resource
        st.values["resource"] = "released"
        if ctx.resources.len > 0:
          ctx.resources.delete(ctx.resources.find("database"))
        st.counter -= 1
        true
    )
    
    # Step 2: Process data
    let step2 = newSagaStep[TestContext, TestState](
      "ProcessData",
      proc(ctx: TestContext, st: TestState): bool =
        # Action: process data
        if "resource" notin st.values or st.values["resource"] != "reserved":
          return false
        
        st.values["data"] = "processed"
        st.counter += 1
        true
      ,
      proc(ctx: TestContext, st: TestState): bool =
        # Compensation: undo processing
        st.values["data"] = "unprocessed"
        st.counter -= 1
        true
    )
    
    # Step 3: Notify (always fails for testing compensation)
    let failingStep = newSagaStep[TestContext, TestState](
      "NotifyFailure",
      proc(ctx: TestContext, st: TestState): bool =
        # Action: always fails
        false
      ,
      proc(ctx: TestContext, st: TestState): bool =
        # Compensation: nothing to do
        true
    )
    
    # Add steps to saga
    discard sagaDefinition.addStep(step1)
    discard sagaDefinition.addStep(step2.dependsOn(step1))
  
  test "Saga executes steps successfully":
    # Create execution
    let execution = newSagaExecution(sagaDefinition, context, state)
    
    # Execute saga
    let success = execution.execute()
    
    # Check execution succeeded
    check success == true
    check execution.status == ssCompleted
    
    # Check state was updated correctly
    check state.values["resource"] == "reserved"
    check state.values["data"] == "processed"
    check state.counter == 2
    
    # Check all steps executed
    check execution.executedSteps.len == 2
    check execution.executedSteps[0].name == "ReserveResources"
    check execution.executedSteps[1].name == "ProcessData"
  
  test "Saga compensates on failure":
    # Add failing step to saga
    let failingStep = newSagaStep[TestContext, TestState](
      "FailingStep",
      proc(ctx: TestContext, st: TestState): bool = false,
      proc(ctx: TestContext, st: TestState): bool = true
    )
    
    discard sagaDefinition.addStep(failingStep)
    
    # Reset state
    state = TestState(values: initTable[string, string](), counter: 0)
    
    # Create execution
    let execution = newSagaExecution(sagaDefinition, context, state)
    
    # Execute saga (will fail at the failing step)
    let success = execution.execute()
    
    # Check execution failed
    check success == false
    check execution.status == ssCompensated
    
    # Check state was compensated correctly
    check state.counter == 0  # Back to original value
    
    # Check failing step was recorded
    check execution.failedStep.isSome()
    check execution.failedStep.get().name == "FailingStep"

when isMainModule:
  unittest.run()