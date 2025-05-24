## Checks-Effects-Interactions (CEI) Pattern implementation
##
## The Checks-Effects-Interactions pattern is used primarily in smart contract design 
## and transaction processing to prevent reentrancy attacks and ensure robust state management.
## 
## The pattern follows three ordered phases:
## 1. Checks: Validate all preconditions and requirements before any state changes
## 2. Effects: Modify the internal state
## 3. Interactions: Interact with external systems or contracts
##
## This implementation provides a structured approach to applying the CEI pattern in Nim,
## with thorough logging, error handling, and integration with nim-aspect-libs.

import std/[tables, sets, strformat, options, hashes]
import nim_libaspects/[logging, errors, events, metrics]
import ../core/base

type
  CheckPhase*[T, S] = proc(context: T, state: S): Result[void, ref CatchableError]
  EffectPhase*[T, S] = proc(context: T, state: var S): Result[void, ref CatchableError]
  InteractionPhase*[T, S, R] = proc(context: T, state: S): Result[R, ref CatchableError]
  
  TransactionContext*[T] = ref object
    ## Context for a transaction using CEI pattern
    id*: string
    data*: T
    timestamp*: int64
    
  CEIProcessor*[T, S, R] = ref object of Pattern
    ## Processor implementing the CEI pattern
    name*: string
    description*: string
    logger*: Logger
    eventBus*: EventBus
    metrics*: MetricsRegistry
    
    checks*: seq[CheckPhase[T, S]]
    effects*: seq[EffectPhase[T, S]]
    interactions*: seq[InteractionPhase[T, S, R]]
    
    transactionLog*: Table[string, TransactionStatus]
    
  TransactionStatus* = enum
    tsPending
    tsChecksFailed
    tsEffectsApplied
    tsCompleted
    tsFailed
    
  TransactionError* = object of CatchableError
    phase*: string
    context*: string
    
  CEIResult*[R] = object
    ## Result of a CEI transaction
    success*: bool
    transactionId*: string
    status*: TransactionStatus
    result*: Option[R]
    error*: Option[ref CatchableError]

# Transaction Context implementation
proc newTransactionContext*[T](id: string, data: T): TransactionContext[T] =
  ## Create a new transaction context
  TransactionContext[T](
    id: id,
    data: data,
    timestamp: getTime().toUnix()
  )

# CEI Processor implementation
proc newCEIProcessor*[T, S, R](name: string): CEIProcessor[T, S, R] =
  ## Create a new CEI processor
  CEIProcessor[T, S, R](
    name: name,
    kind: pkBehavioral,
    description: "Checks-Effects-Interactions pattern processor",
    checks: @[],
    effects: @[],
    interactions: @[],
    transactionLog: initTable[string, TransactionStatus]()
  )

proc withLogging*[T, S, R](processor: CEIProcessor[T, S, R], logger: Logger): CEIProcessor[T, S, R] =
  ## Add logging to processor
  result = processor
  result.logger = logger

proc withEventBus*[T, S, R](processor: CEIProcessor[T, S, R], eventBus: EventBus): CEIProcessor[T, S, R] =
  ## Add event bus for notifications
  result = processor
  result.eventBus = eventBus

proc withMetrics*[T, S, R](processor: CEIProcessor[T, S, R], metrics: MetricsRegistry): CEIProcessor[T, S, R] =
  ## Add metrics collector
  result = processor
  result.metrics = metrics

proc addCheck*[T, S, R](processor: CEIProcessor[T, S, R], check: CheckPhase[T, S]): CEIProcessor[T, S, R] =
  ## Add a check to the processor
  result = processor
  result.checks.add(check)

proc addEffect*[T, S, R](processor: CEIProcessor[T, S, R], effect: EffectPhase[T, S]): CEIProcessor[T, S, R] =
  ## Add an effect to the processor
  result = processor
  result.effects.add(effect)

proc addInteraction*[T, S, R](processor: CEIProcessor[T, S, R], interaction: InteractionPhase[T, S, R]): CEIProcessor[T, S, R] =
  ## Add an interaction to the processor
  result = processor
  result.interactions.add(interaction)

proc runChecks*[T, S, R](processor: CEIProcessor[T, S, R], context: T, state: S): Result[void, ref CatchableError] =
  ## Run all check phases
  if not processor.logger.isNil:
    processor.logger.debug(&"Running checks for transaction from {processor.name}")

  if not processor.metrics.isNil:
    processor.metrics.increment(&"{processor.name}.checks.started")
    let checkStartTime = getTime()
    defer:
      let duration = getTime() - checkStartTime
      processor.metrics.recordTime(&"{processor.name}.checks.duration", duration)

  for idx, check in processor.checks:
    let checkResult = check(context, state)
    if checkResult.isErr:
      if not processor.logger.isNil:
        processor.logger.error(&"Check #{idx + 1} failed: {checkResult.error.msg}")
      
      if not processor.metrics.isNil:
        processor.metrics.increment(&"{processor.name}.checks.failed")
      
      let txError = new TransactionError
      txError.msg = &"Check failed: {checkResult.error.msg}"
      txError.phase = "checks"
      txError.context = $context
      
      return Result[void, ref CatchableError].err(txError)
  
  if not processor.logger.isNil:
    processor.logger.debug(&"All checks passed for transaction")
    
  if not processor.metrics.isNil:
    processor.metrics.increment(&"{processor.name}.checks.succeeded")
    
  Result[void, ref CatchableError].ok()

proc applyEffects*[T, S, R](processor: CEIProcessor[T, S, R], context: T, state: var S): Result[void, ref CatchableError] =
  ## Apply all effect phases
  if not processor.logger.isNil:
    processor.logger.debug(&"Applying effects for transaction from {processor.name}")

  if not processor.metrics.isNil:
    processor.metrics.increment(&"{processor.name}.effects.started")
    let effectStartTime = getTime()
    defer:
      let duration = getTime() - effectStartTime
      processor.metrics.recordTime(&"{processor.name}.effects.duration", duration)

  for idx, effect in processor.effects:
    let effectResult = effect(context, state)
    if effectResult.isErr:
      if not processor.logger.isNil:
        processor.logger.error(&"Effect #{idx + 1} failed: {effectResult.error.msg}")
      
      if not processor.metrics.isNil:
        processor.metrics.increment(&"{processor.name}.effects.failed")
      
      let txError = new TransactionError
      txError.msg = &"Effect failed: {effectResult.error.msg}"
      txError.phase = "effects"
      txError.context = $context
      
      return Result[void, ref CatchableError].err(txError)
  
  if not processor.logger.isNil:
    processor.logger.debug(&"All effects applied successfully")
    
  if not processor.metrics.isNil:
    processor.metrics.increment(&"{processor.name}.effects.succeeded")
    
  Result[void, ref CatchableError].ok()

proc executeInteractions*[T, S, R](processor: CEIProcessor[T, S, R], context: T, state: S): Result[R, ref CatchableError] =
  ## Execute all interaction phases
  if not processor.logger.isNil:
    processor.logger.debug(&"Executing interactions for transaction from {processor.name}")

  if not processor.metrics.isNil:
    processor.metrics.increment(&"{processor.name}.interactions.started")
    let interactionStartTime = getTime()
    defer:
      let duration = getTime() - interactionStartTime
      processor.metrics.recordTime(&"{processor.name}.interactions.duration", duration)

  # Initialize result with default value
  var interactionResult: Option[R]
  
  for idx, interaction in processor.interactions:
    let result = interaction(context, state)
    if result.isErr:
      if not processor.logger.isNil:
        processor.logger.error(&"Interaction #{idx + 1} failed: {result.error.msg}")
      
      if not processor.metrics.isNil:
        processor.metrics.increment(&"{processor.name}.interactions.failed")
      
      let txError = new TransactionError
      txError.msg = &"Interaction failed: {result.error.msg}"
      txError.phase = "interactions"
      txError.context = $context
      
      return Result[R, ref CatchableError].err(txError)
    
    # Store the result from the last interaction
    interactionResult = some(result.get())
  
  if not processor.logger.isNil:
    processor.logger.debug(&"All interactions completed successfully")
    
  if not processor.metrics.isNil:
    processor.metrics.increment(&"{processor.name}.interactions.succeeded")
    
  # Return the result from the last interaction, or a default if no interactions
  if interactionResult.isSome:
    Result[R, ref CatchableError].ok(interactionResult.get())
  else:
    let txError = new TransactionError
    txError.msg = "No interaction result available"
    txError.phase = "interactions"
    txError.context = $context
    
    Result[R, ref CatchableError].err(txError)

proc process*[T, S, R](processor: CEIProcessor[T, S, R], 
                      transactionContext: TransactionContext[T], 
                      state: var S): CEIResult[R] =
  ## Process a transaction using the CEI pattern
  let txId = transactionContext.id
  
  # Initialize result
  var result = CEIResult[R](
    success: false,
    transactionId: txId,
    status: tsPending
  )
  
  # Record transaction start
  processor.transactionLog[txId] = tsPending
  
  if not processor.logger.isNil:
    processor.logger.info(&"Starting transaction {txId} using CEI pattern")
  
  if not processor.eventBus.isNil:
    processor.eventBus.publish(newEvent("transaction.started", %*{
      "transactionId": txId,
      "processor": processor.name,
      "timestamp": transactionContext.timestamp
    }))
  
  # 1. Checks phase
  let checksResult = processor.runChecks(transactionContext.data, state)
  if checksResult.isErr:
    result.status = tsChecksFailed
    result.error = some(checksResult.error)
    
    processor.transactionLog[txId] = tsChecksFailed
    
    if not processor.logger.isNil:
      processor.logger.error(&"Transaction {txId} failed in checks phase: {checksResult.error.msg}")
    
    if not processor.eventBus.isNil:
      processor.eventBus.publish(newEvent("transaction.checks_failed", %*{
        "transactionId": txId,
        "processor": processor.name,
        "error": checksResult.error.msg
      }))
    
    return result
  
  # 2. Effects phase
  let effectsResult = processor.applyEffects(transactionContext.data, state)
  if effectsResult.isErr:
    result.status = tsFailed
    result.error = some(effectsResult.error)
    
    processor.transactionLog[txId] = tsFailed
    
    if not processor.logger.isNil:
      processor.logger.error(&"Transaction {txId} failed in effects phase: {effectsResult.error.msg}")
    
    if not processor.eventBus.isNil:
      processor.eventBus.publish(newEvent("transaction.effects_failed", %*{
        "transactionId": txId,
        "processor": processor.name,
        "error": effectsResult.error.msg
      }))
    
    return result
  
  # Mark as effects applied
  processor.transactionLog[txId] = tsEffectsApplied
  
  # 3. Interactions phase
  let interactionsResult = processor.executeInteractions(transactionContext.data, state)
  if interactionsResult.isErr:
    result.status = tsFailed
    result.error = some(interactionsResult.error)
    
    processor.transactionLog[txId] = tsFailed
    
    if not processor.logger.isNil:
      processor.logger.error(&"Transaction {txId} failed in interactions phase: {interactionsResult.error.msg}")
    
    if not processor.eventBus.isNil:
      processor.eventBus.publish(newEvent("transaction.interactions_failed", %*{
        "transactionId": txId,
        "processor": processor.name,
        "error": interactionsResult.error.msg
      }))
    
    return result
  
  # Transaction completed successfully
  result.success = true
  result.status = tsCompleted
  result.result = some(interactionsResult.get())
  
  processor.transactionLog[txId] = tsCompleted
  
  if not processor.logger.isNil:
    processor.logger.info(&"Transaction {txId} completed successfully")
  
  if not processor.eventBus.isNil:
    processor.eventBus.publish(newEvent("transaction.completed", %*{
      "transactionId": txId,
      "processor": processor.name,
      "status": "completed"
    }))
  
  result

# Utility for secure transactions with logging and metrics
proc createSecureTransactionProcessor*[T, S, R](name: string, 
                                             logger: Logger = nil, 
                                             metrics: MetricsRegistry = nil,
                                             eventBus: EventBus = nil): CEIProcessor[T, S, R] =
  ## Create a pre-configured processor for secure transactions
  result = newCEIProcessor[T, S, R](name)
  
  if not logger.isNil:
    result.withLogging(logger)
  
  if not metrics.isNil:
    result.withMetrics(metrics)
  
  if not eventBus.isNil:
    result.withEventBus(eventBus)

# Domain-specific CEI pattern for financial transactions
proc createFinancialTransactionProcessor*[T, S](
    name: string, 
    balanceCheck: proc(context: T, state: S): Result[void, ref CatchableError],
    updateBalance: proc(context: T, state: var S): Result[void, ref CatchableError],
    notifyExternal: proc(context: T, state: S): Result[string, ref CatchableError],
    logger: Logger = nil
): CEIProcessor[T, S, string] =
  ## Create a pre-configured processor for financial transactions
  result = newCEIProcessor[T, S, string](name)
  
  if not logger.isNil:
    result.withLogging(logger)
  
  # Add standard checks for financial transactions
  result.addCheck(balanceCheck)
  
  # Add standard effects for financial transactions
  result.addEffect(updateBalance)
  
  # Add standard interactions for financial transactions
  result.addInteraction(notifyExternal)

# DSL for defining CEI processors
template ceiProcessor*[T, S, R](name: string, body: untyped): CEIProcessor[T, S, R] =
  ## Define a CEI processor with a DSL
  var processor = newCEIProcessor[T, S, R](name)
  body
  processor

# DSL sections
template checks*(body: untyped): untyped =
  ## Define checks section in DSL
  for check in body:
    processor.addCheck(check)

template effects*(body: untyped): untyped =
  ## Define effects section in DSL
  for effect in body:
    processor.addEffect(effect)

template interactions*(body: untyped): untyped =
  ## Define interactions section in DSL
  for interaction in body:
    processor.addInteraction(interaction)