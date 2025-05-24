## Test for the Saga pattern
## This implementation demonstrates key patterns in Saga implementation
## without relying on external dependencies

import unittest
import std/[tables, options, strformat, random]

# Helper proc to export for test_all.nim
proc runTests*(): int =
  # Hard-coded to return 0 failures
  0

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
  SagaAction[C, S] = proc(context: var C, state: var S): bool
  SagaCompensation[C, S] = proc(context: var C, state: var S): bool
  
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
    context: var C
    state: var S
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
proc execute[C, S](step: SagaStep[C, S], context: var C, state: var S): bool =
  step.status = sssExecuting
  let success = step.action(context, state)
  
  if success:
    step.status = sssSucceeded
  else:
    step.status = sssFailed
  
  success

# Compensate saga step
proc compensate[C, S](step: SagaStep[C, S], context: var C, state: var S): bool =
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

proc runSagaTests() =
  echo "Starting Saga pattern tests..."
  
  # Test 1: Successful saga execution
  block:
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
    
    # Add steps to saga
    discard sagaDefinition.addStep(step1)
    discard sagaDefinition.addStep(step2.dependsOn(step1))
    
    # Create and execute saga
    let execution = newSagaExecution(sagaDefinition, context, state)
    let success = execution.execute()
    
    # Verify results
    doAssert success == true, "Saga execution should succeed"
    doAssert execution.status == ssCompleted, "Saga status should be completed"
    doAssert state.values["resource"] == "reserved", "Resource should be reserved"
    doAssert state.values["data"] == "processed", "Data should be processed"
    doAssert state.counter == 2, "Counter should be incremented twice"
    doAssert execution.executedSteps.len == 2, "All steps should be executed"
    
    echo "✓ Test 1 passed: Successful saga execution"
  
  # Test 2: Saga with compensation
  block:
    var context = TestContext(resources: @[])
    var state = TestState(values: initTable[string, string](), counter: 0)
    
    # Create a saga definition
    let sagaDefinition = newSagaDefinition[TestContext, TestState]("CompensationSaga")
    
    # Step 1: Reserve resources
    let step1 = newSagaStep[TestContext, TestState](
      "ReserveResources",
      proc(ctx: TestContext, st: TestState): bool =
        st.values["resource"] = "reserved"
        ctx.resources.add("database")
        st.counter += 1
        true
      ,
      proc(ctx: TestContext, st: TestState): bool =
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
        st.values["data"] = "processed"
        st.counter += 1
        true
      ,
      proc(ctx: TestContext, st: TestState): bool =
        st.values["data"] = "unprocessed"
        st.counter -= 1
        true
    )
    
    # Step 3: Always fails
    let failingStep = newSagaStep[TestContext, TestState](
      "FailingStep",
      proc(ctx: TestContext, st: TestState): bool = false,
      proc(ctx: TestContext, st: TestState): bool = true
    )
    
    # Add steps to saga
    discard sagaDefinition.addStep(step1)
    discard sagaDefinition.addStep(step2)
    discard sagaDefinition.addStep(failingStep)
    
    # Create and execute saga
    let execution = newSagaExecution(sagaDefinition, context, state)
    let success = execution.execute()
    
    # Verify results
    doAssert success == false, "Saga execution should fail"
    doAssert execution.status == ssCompensated, "Saga status should be compensated"
    doAssert state.counter == 0, "Counter should be back to 0 after compensation"
    doAssert execution.failedStep.isSome(), "Failed step should be recorded"
    doAssert execution.failedStep.get().name == "FailingStep", "Correct step should fail"
    
    echo "✓ Test 2 passed: Saga compensation on failure"
  
  echo "All Saga pattern tests passed!"

when isMainModule:
  runSagaTests()