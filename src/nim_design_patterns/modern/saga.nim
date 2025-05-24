## Saga Pattern implementation for distributed transactions
##
## The Saga pattern is used to manage failures in distributed transactions by 
## defining a sequence of compensating actions that can be executed when a step fails.
## 
## This implementation provides:
## - Definition of sagas with multiple steps
## - Compensating actions for each step to ensure rollback on failure
## - Orchestration and choreography approaches
## - Transaction coordination with logging and metrics
## - Event-driven status updates
## - Recovery from interrupted sagas

import std/[tables, sets, strformat, options, sequtils, times, json]
import nim_libaspects/[logging, errors, events, metrics]
import ../core/base

type
  SagaStepId* = distinct string
  SagaId* = distinct string
  
  SagaStepStatus* = enum
    sssNotStarted
    sssExecuting
    sssSucceeded
    sssFailed
    sssCompensating
    sssCompensated
    sssSkipped
  
  SagaStatus* = enum
    ssNotStarted
    ssInProgress
    ssCompleted
    ssCompensating
    ssFailed
    ssCompensated
  
  SagaAction*[C, S] = proc(context: C, state: S): Result[void, ref CatchableError]
  SagaCompensation*[C, S] = proc(context: C, state: S): Result[void, ref CatchableError]
  
  SagaStep*[C, S] = ref object
    ## A step in a saga with action and compensation
    id*: SagaStepId
    name*: string
    action*: SagaAction[C, S]
    compensation*: SagaCompensation[C, S]
    status*: SagaStepStatus
    error*: Option[ref CatchableError]
    dependencies*: seq[SagaStepId]
    startTime*: DateTime
    endTime*: DateTime
  
  SagaDefinition*[C, S] = ref object of Pattern
    ## Definition of a saga with all its steps
    id*: SagaId
    name*: string
    steps*: seq[SagaStep[C, S]]
    stepsByName*: Table[string, SagaStep[C, S]]
    stepsByDependency*: Table[SagaStepId, seq[SagaStep[C, S]]]
    logger*: Logger
    metrics*: MetricsRegistry
    eventBus*: EventBus
  
  SagaExecution*[C, S] = ref object
    ## Execution instance of a saga
    id*: SagaId
    definition*: SagaDefinition[C, S]
    context*: C
    state*: S
    status*: SagaStatus
    executedSteps*: seq[SagaStep[C, S]]
    failedStep*: Option[SagaStep[C, S]]
    startTime*: DateTime
    endTime*: DateTime
    error*: Option[ref CatchableError]
  
  SagaCoordinator*[C, S] = ref object of Pattern
    ## Coordinates execution of sagas
    sagaDefinitions*: Table[string, SagaDefinition[C, S]]
    executions*: Table[SagaId, SagaExecution[C, S]]
    logger*: Logger
    metrics*: MetricsRegistry
    eventBus*: EventBus
  
  SagaExecutionError* = object of CatchableError
    ## Error during saga execution
    sagaId*: string
    stepId*: string
    phase*: string
  
  SagaLog* = ref object
    ## Log for saga execution (for recovery)
    entries*: seq[SagaLogEntry]
  
  SagaLogEntryType* = enum
    sletSagaStarted
    sletStepStarted
    sletStepCompleted
    sletStepFailed
    sletCompensationStarted
    sletCompensationCompleted
    sletCompensationFailed
    sletSagaCompleted
    sletSagaCompensated
    sletSagaFailed
  
  SagaLogEntry* = object
    ## Log entry for saga execution
    entryType*: SagaLogEntryType
    sagaId*: string
    sagaName*: string
    stepId*: string
    stepName*: string
    timestamp*: DateTime
    data*: JsonNode

# String and hash implementations for IDs
proc `$`*(id: SagaStepId): string = id.string
proc `$`*(id: SagaId): string = id.string

proc `==`*(a, b: SagaStepId): bool {.borrow.}
proc `==`*(a, b: SagaId): bool {.borrow.}

proc hash*(id: SagaStepId): Hash {.borrow.}
proc hash*(id: SagaId): Hash {.borrow.}

# Helper for generating IDs
proc newSagaId*(): SagaId =
  ## Generate a new unique saga ID
  SagaId($getTime().toUnix() & "-" & $rand(high(int)))

proc newSagaStepId*(): SagaStepId =
  ## Generate a new unique step ID
  SagaStepId($getTime().toUnix() & "-" & $rand(high(int)))

# SagaStep implementation
proc newSagaStep*[C, S](name: string, 
                      action: SagaAction[C, S],
                      compensation: SagaCompensation[C, S]): SagaStep[C, S] =
  ## Create a new saga step
  SagaStep[C, S](
    id: newSagaStepId(),
    name: name,
    action: action,
    compensation: compensation,
    status: sssNotStarted,
    dependencies: @[]
  )

proc dependsOn*[C, S](step: SagaStep[C, S], stepId: SagaStepId): SagaStep[C, S] =
  ## Add a dependency to this step
  result = step
  result.dependencies.add(stepId)

proc execute*[C, S](step: SagaStep[C, S], context: C, state: S): Result[void, ref CatchableError] =
  ## Execute the step's action
  step.status = sssExecuting
  step.startTime = now()
  
  let actionResult = step.action(context, state)
  step.endTime = now()
  
  if actionResult.isOk:
    step.status = sssSucceeded
  else:
    step.status = sssFailed
    step.error = some(actionResult.error)
  
  actionResult

proc compensate*[C, S](step: SagaStep[C, S], context: C, state: S): Result[void, ref CatchableError] =
  ## Execute the step's compensation
  if step.status != sssSucceeded and step.status != sssFailed:
    # Only compensate steps that were executed
    step.status = sssSkipped
    return Result[void, ref CatchableError].ok()
  
  step.status = sssCompensating
  
  let compensationResult = step.compensation(context, state)
  
  if compensationResult.isOk:
    step.status = sssCompensated
  else:
    # Compensation failed, this is serious
    step.error = some(compensationResult.error)
  
  compensationResult

# SagaDefinition implementation
proc newSagaDefinition*[C, S](name: string): SagaDefinition[C, S] =
  ## Create a new saga definition
  SagaDefinition[C, S](
    id: newSagaId(),
    name: name,
    kind: pkBehavioral,
    description: "Saga Pattern for distributed transactions",
    steps: @[],
    stepsByName: initTable[string, SagaStep[C, S]](),
    stepsByDependency: initTable[SagaStepId, seq[SagaStep[C, S]]]()
  )

proc withLogging*[C, S](saga: SagaDefinition[C, S], logger: Logger): SagaDefinition[C, S] =
  ## Add logging to saga
  result = saga
  result.logger = logger

proc withMetrics*[C, S](saga: SagaDefinition[C, S], metrics: MetricsRegistry): SagaDefinition[C, S] =
  ## Add metrics to saga
  result = saga
  result.metrics = metrics

proc withEventBus*[C, S](saga: SagaDefinition[C, S], eventBus: EventBus): SagaDefinition[C, S] =
  ## Add event bus to saga
  result = saga
  result.eventBus = eventBus

proc addStep*[C, S](saga: SagaDefinition[C, S], step: SagaStep[C, S]): SagaDefinition[C, S] =
  ## Add a step to the saga
  result = saga
  result.steps.add(step)
  result.stepsByName[step.name] = step
  
  # Update dependency mapping
  for depId in step.dependencies:
    if depId notin result.stepsByDependency:
      result.stepsByDependency[depId] = @[]
    
    result.stepsByDependency[depId].add(step)

proc getStep*[C, S](saga: SagaDefinition[C, S], name: string): Option[SagaStep[C, S]] =
  ## Get a step by name
  if name in saga.stepsByName:
    return some(saga.stepsByName[name])
  
  none(SagaStep[C, S])

proc getStepById*[C, S](saga: SagaDefinition[C, S], id: SagaStepId): Option[SagaStep[C, S]] =
  ## Get a step by ID
  for step in saga.steps:
    if step.id == id:
      return some(step)
  
  none(SagaStep[C, S])

proc getNextSteps*[C, S](saga: SagaDefinition[C, S], completedStepId: SagaStepId): seq[SagaStep[C, S]] =
  ## Get steps that depend on the completed step
  if completedStepId in saga.stepsByDependency:
    return saga.stepsByDependency[completedStepId]
  
  @[]

proc getInitialSteps*[C, S](saga: SagaDefinition[C, S]): seq[SagaStep[C, S]] =
  ## Get steps with no dependencies
  result = saga.steps.filterIt(it.dependencies.len == 0)

# SagaExecution implementation
proc newSagaExecution*[C, S](definition: SagaDefinition[C, S], 
                           context: C, state: S): SagaExecution[C, S] =
  ## Create a new saga execution
  SagaExecution[C, S](
    id: newSagaId(),
    definition: definition,
    context: context,
    state: state,
    status: ssNotStarted,
    executedSteps: @[]
  )

proc start*[C, S](execution: SagaExecution[C, S]): SagaExecution[C, S] =
  ## Start the saga execution
  result = execution
  result.status = ssInProgress
  result.startTime = now()
  
  # Log start
  if not result.definition.logger.isNil:
    result.definition.logger.info(&"Started saga '{result.definition.name}' with ID {result.id}")
  
  # Publish event
  if not result.definition.eventBus.isNil:
    result.definition.eventBus.publish(newEvent("saga.started", %*{
      "sagaId": $result.id,
      "sagaName": result.definition.name,
      "timestamp": $now()
    }))
  
  # Record metric
  if not result.definition.metrics.isNil:
    result.definition.metrics.increment(&"saga.{result.definition.name}.started")

proc complete*[C, S](execution: SagaExecution[C, S]): SagaExecution[C, S] =
  ## Mark saga as completed
  result = execution
  result.status = ssCompleted
  result.endTime = now()
  
  # Log completion
  if not result.definition.logger.isNil:
    result.definition.logger.info(&"Completed saga '{result.definition.name}' with ID {result.id}")
  
  # Publish event
  if not result.definition.eventBus.isNil:
    result.definition.eventBus.publish(newEvent("saga.completed", %*{
      "sagaId": $result.id,
      "sagaName": result.definition.name,
      "timestamp": $now(),
      "executionTime": $(result.endTime - result.startTime)
    }))
  
  # Record metric
  if not result.definition.metrics.isNil:
    result.definition.metrics.increment(&"saga.{result.definition.name}.completed")
    let duration = (result.endTime - result.startTime).inMilliseconds.int
    result.definition.metrics.recordTime(&"saga.{result.definition.name}.duration", duration)

proc fail*[C, S](execution: SagaExecution[C, S], 
               step: SagaStep[C, S], 
               error: ref CatchableError): SagaExecution[C, S] =
  ## Mark saga as failed
  result = execution
  result.status = ssFailed
  result.endTime = now()
  result.failedStep = some(step)
  result.error = some(error)
  
  # Log failure
  if not result.definition.logger.isNil:
    result.definition.logger.error(&"Failed saga '{result.definition.name}' with ID {result.id} at step '{step.name}': {error.msg}")
  
  # Publish event
  if not result.definition.eventBus.isNil:
    result.definition.eventBus.publish(newEvent("saga.failed", %*{
      "sagaId": $result.id,
      "sagaName": result.definition.name,
      "failedStep": step.name,
      "error": error.msg,
      "timestamp": $now()
    }))
  
  # Record metric
  if not result.definition.metrics.isNil:
    result.definition.metrics.increment(&"saga.{result.definition.name}.failed")

proc beginCompensation*[C, S](execution: SagaExecution[C, S]): SagaExecution[C, S] =
  ## Begin compensation process
  result = execution
  result.status = ssCompensating
  
  # Log compensation start
  if not result.definition.logger.isNil:
    result.definition.logger.info(&"Starting compensation for saga '{result.definition.name}' with ID {result.id}")
  
  # Publish event
  if not result.definition.eventBus.isNil:
    result.definition.eventBus.publish(newEvent("saga.compensating", %*{
      "sagaId": $result.id,
      "sagaName": result.definition.name,
      "timestamp": $now()
    }))

proc completeCompensation*[C, S](execution: SagaExecution[C, S], 
                               success: bool): SagaExecution[C, S] =
  ## Complete compensation process
  result = execution
  
  if success:
    result.status = ssCompensated
    
    # Log compensation completion
    if not result.definition.logger.isNil:
      result.definition.logger.info(&"Completed compensation for saga '{result.definition.name}' with ID {result.id}")
    
    # Publish event
    if not result.definition.eventBus.isNil:
      result.definition.eventBus.publish(newEvent("saga.compensated", %*{
        "sagaId": $result.id,
        "sagaName": result.definition.name,
        "timestamp": $now()
      }))
    
    # Record metric
    if not result.definition.metrics.isNil:
      result.definition.metrics.increment(&"saga.{result.definition.name}.compensated")
  else:
    # Compensation failed, this is serious
    result.status = ssFailed
    
    # Log compensation failure
    if not result.definition.logger.isNil:
      result.definition.logger.error(&"Failed compensation for saga '{result.definition.name}' with ID {result.id}")
    
    # Publish event
    if not result.definition.eventBus.isNil:
      result.definition.eventBus.publish(newEvent("saga.compensation_failed", %*{
        "sagaId": $result.id,
        "sagaName": result.definition.name,
        "timestamp": $now()
      }))
    
    # Record metric
    if not result.definition.metrics.isNil:
      result.definition.metrics.increment(&"saga.{result.definition.name}.compensation_failed")

# SagaCoordinator implementation
proc newSagaCoordinator*[C, S](): SagaCoordinator[C, S] =
  ## Create a new saga coordinator
  SagaCoordinator[C, S](
    name: "SagaCoordinator",
    kind: pkBehavioral,
    description: "Coordinator for Saga pattern",
    sagaDefinitions: initTable[string, SagaDefinition[C, S]](),
    executions: initTable[SagaId, SagaExecution[C, S]]()
  )

proc withLogging*[C, S](coordinator: SagaCoordinator[C, S], logger: Logger): SagaCoordinator[C, S] =
  ## Add logging to coordinator
  result = coordinator
  result.logger = logger

proc withMetrics*[C, S](coordinator: SagaCoordinator[C, S], metrics: MetricsRegistry): SagaCoordinator[C, S] =
  ## Add metrics to coordinator
  result = coordinator
  result.metrics = metrics

proc withEventBus*[C, S](coordinator: SagaCoordinator[C, S], eventBus: EventBus): SagaCoordinator[C, S] =
  ## Add event bus to coordinator
  result = coordinator
  result.eventBus = eventBus

proc registerSaga*[C, S](coordinator: SagaCoordinator[C, S], 
                       saga: SagaDefinition[C, S]): SagaCoordinator[C, S] =
  ## Register a saga definition
  result = coordinator
  result.sagaDefinitions[saga.name] = saga
  
  # Share cross-cutting concerns
  if not result.logger.isNil and saga.logger.isNil:
    saga.logger = result.logger
  
  if not result.metrics.isNil and saga.metrics.isNil:
    saga.metrics = result.metrics
  
  if not result.eventBus.isNil and saga.eventBus.isNil:
    saga.eventBus = result.eventBus
  
  if not result.logger.isNil:
    result.logger.info(&"Registered saga '{saga.name}'")

proc executeSaga*[C, S](coordinator: SagaCoordinator[C, S],
                      sagaName: string,
                      context: C,
                      state: S): Result[SagaExecution[C, S], ref CatchableError] =
  ## Execute a saga
  if sagaName notin coordinator.sagaDefinitions:
    let error = new CatchableError
    error.msg = &"No saga found with name '{sagaName}'"
    return Result[SagaExecution[C, S], ref CatchableError].err(error)
  
  let sagaDefinition = coordinator.sagaDefinitions[sagaName]
  
  # Create and start execution
  var execution = newSagaExecution(sagaDefinition, context, state)
  execution.start()
  
  # Store execution
  coordinator.executions[execution.id] = execution
  
  if not coordinator.logger.isNil:
    coordinator.logger.info(&"Started execution of saga '{sagaName}' with ID {execution.id}")
  
  # Get initial steps (those with no dependencies)
  let initialSteps = sagaDefinition.getInitialSteps()
  
  if initialSteps.len == 0:
    let error = new CatchableError
    error.msg = &"Saga '{sagaName}' has no initial steps"
    return Result[SagaExecution[C, S], ref CatchableError].err(error)
  
  # Execute initial steps
  for step in initialSteps:
    if not coordinator.logger.isNil:
      coordinator.logger.debug(&"Executing step '{step.name}' of saga '{sagaName}'")
    
    # Execute step
    let stepResult = step.execute(context, state)
    
    # Add to executed steps
    execution.executedSteps.add(step)
    
    if stepResult.isErr:
      # Step failed, start compensation
      if not coordinator.logger.isNil:
        coordinator.logger.error(&"Step '{step.name}' of saga '{sagaName}' failed: {stepResult.error.msg}")
      
      execution.fail(step, stepResult.error)
      
      # Compensate all executed steps in reverse order
      let compensationResult = coordinator.compensateExecution(execution)
      
      if compensationResult.isErr:
        if not coordinator.logger.isNil:
          coordinator.logger.error(&"Compensation for saga '{sagaName}' failed: {compensationResult.error.msg}")
      
      return Result[SagaExecution[C, S], ref CatchableError].ok(execution)
    
    # Step succeeded, get dependent steps
    let nextSteps = sagaDefinition.getNextSteps(step.id)
    
    # Check if all dependencies are satisfied for each next step
    for nextStep in nextSteps:
      var canExecute = true
      
      # Check all dependencies are completed
      for depId in nextStep.dependencies:
        let depStep = sagaDefinition.getStepById(depId)
        
        if depStep.isNone or depStep.get().status != sssSucceeded:
          canExecute = false
          break
      
      if canExecute:
        # Execute step
        if not coordinator.logger.isNil:
          coordinator.logger.debug(&"Executing dependent step '{nextStep.name}' of saga '{sagaName}'")
        
        let nextStepResult = nextStep.execute(context, state)
        
        # Add to executed steps
        execution.executedSteps.add(nextStep)
        
        if nextStepResult.isErr:
          # Step failed, start compensation
          if not coordinator.logger.isNil:
            coordinator.logger.error(&"Step '{nextStep.name}' of saga '{sagaName}' failed: {nextStepResult.error.msg}")
          
          execution.fail(nextStep, nextStepResult.error)
          
          # Compensate all executed steps in reverse order
          let compensationResult = coordinator.compensateExecution(execution)
          
          if compensationResult.isErr:
            if not coordinator.logger.isNil:
              coordinator.logger.error(&"Compensation for saga '{sagaName}' failed: {compensationResult.error.msg}")
          
          return Result[SagaExecution[C, S], ref CatchableError].ok(execution)
  
  # All steps completed successfully
  execution.complete()
  
  if not coordinator.logger.isNil:
    coordinator.logger.info(&"Successfully completed saga '{sagaName}' with ID {execution.id}")
  
  Result[SagaExecution[C, S], ref CatchableError].ok(execution)

proc compensateExecution*[C, S](coordinator: SagaCoordinator[C, S], 
                              execution: SagaExecution[C, S]): Result[void, ref CatchableError] =
  ## Compensate all steps in a saga execution
  # Begin compensation
  execution.beginCompensation()
  
  # Reverse the steps to compensate in opposite order
  var stepsToCompensate = execution.executedSteps
  stepsToCompensate.reverse()
  
  var compensationSuccess = true
  
  # Compensate each step
  for step in stepsToCompensate:
    if not coordinator.logger.isNil:
      coordinator.logger.debug(&"Compensating step '{step.name}' of saga '{execution.definition.name}'")
    
    let compensationResult = step.compensate(execution.context, execution.state)
    
    if compensationResult.isErr:
      # Compensation failed, but continue with others
      compensationSuccess = false
      
      if not coordinator.logger.isNil:
        coordinator.logger.error(&"Compensation for step '{step.name}' failed: {compensationResult.error.msg}")
      
      # Metrics for compensation failure
      if not coordinator.metrics.isNil:
        coordinator.metrics.increment(&"saga.{execution.definition.name}.step_compensation_failed")
  
  # Complete compensation
  execution.completeCompensation(compensationSuccess)
  
  if compensationSuccess:
    Result[void, ref CatchableError].ok()
  else:
    let error = new CatchableError
    error.msg = "Saga compensation failed"
    Result[void, ref CatchableError].err(error)

proc getExecution*[C, S](coordinator: SagaCoordinator[C, S], id: SagaId): Option[SagaExecution[C, S]] =
  ## Get a saga execution by ID
  if id in coordinator.executions:
    return some(coordinator.executions[id])
  
  none(SagaExecution[C, S])

# SagaLog implementation for recovery
proc newSagaLog*(): SagaLog =
  ## Create a new saga log
  SagaLog(
    entries: @[]
  )

proc logSagaStarted*(log: SagaLog, sagaId: SagaId, sagaName: string) =
  ## Log saga started
  log.entries.add(SagaLogEntry(
    entryType: sletSagaStarted,
    sagaId: $sagaId,
    sagaName: sagaName,
    timestamp: now()
  ))

proc logStepStarted*(log: SagaLog, sagaId: SagaId, sagaName: string, 
                   stepId: SagaStepId, stepName: string) =
  ## Log step started
  log.entries.add(SagaLogEntry(
    entryType: sletStepStarted,
    sagaId: $sagaId,
    sagaName: sagaName,
    stepId: $stepId,
    stepName: stepName,
    timestamp: now()
  ))

proc logStepCompleted*(log: SagaLog, sagaId: SagaId, sagaName: string, 
                     stepId: SagaStepId, stepName: string) =
  ## Log step completed
  log.entries.add(SagaLogEntry(
    entryType: sletStepCompleted,
    sagaId: $sagaId,
    sagaName: sagaName,
    stepId: $stepId,
    stepName: stepName,
    timestamp: now()
  ))

proc getUnfinishedSagas*(log: SagaLog): seq[string] =
  ## Get IDs of sagas that were started but not completed
  var startedSagas = initHashSet[string]()
  var completedSagas = initHashSet[string]()
  
  for entry in log.entries:
    case entry.entryType:
    of sletSagaStarted:
      startedSagas.incl(entry.sagaId)
    of sletSagaCompleted, sletSagaCompensated, sletSagaFailed:
      completedSagas.incl(entry.sagaId)
    else:
      discard
  
  # Return sagas that were started but not completed
  result = toSeq(startedSagas - completedSagas)

proc getCompletedSteps*(log: SagaLog, sagaId: string): seq[string] =
  ## Get IDs of steps that were completed for a saga
  var completedSteps = initHashSet[string]()
  
  for entry in log.entries:
    if entry.sagaId == sagaId and entry.entryType == sletStepCompleted:
      completedSteps.incl(entry.stepId)
  
  toSeq(completedSteps)

# Helper functions for creating common sagas
proc createLinearSaga*[C, S](name: string): SagaDefinition[C, S] =
  ## Create a saga with steps that execute in sequence
  result = newSagaDefinition[C, S](name)

proc addSequentialStep*[C, S](saga: SagaDefinition[C, S], 
                            name: string,
                            action: SagaAction[C, S],
                            compensation: SagaCompensation[C, S]): SagaDefinition[C, S] =
  ## Add a step that executes after all previous steps
  result = saga
  
  let step = newSagaStep(name, action, compensation)
  
  # If there are previous steps, depend on the last one
  if result.steps.len > 0:
    let previousStep = result.steps[^1]
    step.dependsOn(previousStep.id)
  
  result.addStep(step)

# DSL for defining sagas
template saga*[C, S](name: string, body: untyped): SagaDefinition[C, S] =
  ## Define a saga with a DSL
  var sagaDef = newSagaDefinition[C, S](name)
  body
  sagaDef

template step*(name: string, action, compensation: untyped): untyped =
  ## Define a step in DSL
  let stepDef = newSagaStep[C, S](
    name, 
    proc(context: C, state: S): Result[void, ref CatchableError] = action,
    proc(context: C, state: S): Result[void, ref CatchableError] = compensation
  )
  
  # If dependsOn is called, it will modify stepDef
  sagaDef.addStep(stepDef)

template dependsOn*(stepName: string): untyped =
  ## Define a dependency in DSL
  let depStep = sagaDef.getStep(stepName)
  if depStep.isSome:
    stepDef.dependsOn(depStep.get().id)