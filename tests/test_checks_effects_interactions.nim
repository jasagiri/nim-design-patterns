## Tests for the Checks-Effects-Interactions pattern

import unittest
import std/[strformat, tables, options]
import nim_libaspects/[logging, errors, events, metrics]
import nim_design_patterns/modern/checks_effects_interactions

# Helper proc to export for test_all.nim
proc runTests*(): int =
  # Return number of failures
  let results = unittest.runTests()
  results.failures

suite "Checks-Effects-Interactions Pattern Tests":
  # Define test types
  type 
    Account = object
      id: string
      balance: float
    
    Transaction = object
      amount: float
      fromAccount: string
      toAccount: string
    
    TransferContext = TransactionContext[Transaction]
    TransferState = Table[string, Account]
    TransferProcessor = CEIProcessor[Transaction, TransferState, string]

  # Setup common test objects
  setup:
    # Create a logger for testing
    let logger = newConsoleLogger()
    
    # Create test accounts
    var accounts = {
      "alice": Account(id: "alice", balance: 100.0),
      "bob": Account(id: "bob", balance: 50.0)
    }.toTable
    
    # Define check phase
    let checkBalance = proc(tx: Transaction, state: TransferState): Result[void, ref CatchableError] =
      if tx.amount <= 0:
        return Result[void, ref CatchableError].err(
          (ref CatchableError)(msg: "Amount must be positive")
        )
      
      if tx.fromAccount notin state:
        return Result[void, ref CatchableError].err(
          (ref CatchableError)(msg: "Source account not found")
        )
      
      if tx.toAccount notin state:
        return Result[void, ref CatchableError].err(
          (ref CatchableError)(msg: "Destination account not found")
        )
      
      if state[tx.fromAccount].balance < tx.amount:
        return Result[void, ref CatchableError].err(
          (ref CatchableError)(msg: "Insufficient funds")
        )
      
      Result[void, ref CatchableError].ok()
    
    # Define effect phase
    let updateBalances = proc(tx: Transaction, state: var TransferState): Result[void, ref CatchableError] =
      state[tx.fromAccount].balance -= tx.amount
      state[tx.toAccount].balance += tx.amount
      
      Result[void, ref CatchableError].ok()
    
    # Define interaction phase
    let notifyTransfer = proc(tx: Transaction, state: TransferState): Result[string, ref CatchableError] =
      let confirmationId = "TX" & $getTime().toUnix()
      
      Result[string, ref CatchableError].ok(confirmationId)
    
    # Create processor
    let processor = newCEIProcessor[Transaction, TransferState, string]("TransferProcessor")
      .withLogging(logger)
      .addCheck(checkBalance)
      .addEffect(updateBalances)
      .addInteraction(notifyTransfer)

  test "Successful transaction processes all phases":
    # Create transaction context
    let tx = Transaction(
      amount: 30.0,
      fromAccount: "alice",
      toAccount: "bob"
    )
    let txContext = newTransactionContext("tx-123", tx)
    
    # Process transaction
    var state = accounts
    let result = processor.process(txContext, state)
    
    # Verify results
    check result.success == true
    check result.status == tsCompleted
    check result.result.isSome
    check result.transactionId == "tx-123"
    
    # Verify state changes
    check state["alice"].balance == 70.0  # 100 - 30
    check state["bob"].balance == 80.0    # 50 + 30

  test "Failed check prevents effects and interactions":
    # Create invalid transaction (insufficient funds)
    let tx = Transaction(
      amount: 150.0,  # Alice only has 100
      fromAccount: "alice",
      toAccount: "bob"
    )
    let txContext = newTransactionContext("tx-456", tx)
    
    # Process transaction
    var state = accounts
    let result = processor.process(txContext, state)
    
    # Verify results
    check result.success == false
    check result.status == tsChecksFailed
    check result.error.isSome
    check result.error.get().msg.contains("Insufficient funds")
    
    # Verify no state changes occurred
    check state["alice"].balance == 100.0  # Unchanged
    check state["bob"].balance == 50.0     # Unchanged

  test "Failed effects prevent interactions but not checks":
    # Create a processor with a failing effect
    let failingEffect = proc(tx: Transaction, state: var TransferState): Result[void, ref CatchableError] =
      return Result[void, ref CatchableError].err(
        (ref CatchableError)(msg: "Effect failed for testing")
      )
    
    let processorWithFailingEffect = newCEIProcessor[Transaction, TransferState, string]("FailingProcessor")
      .addCheck(checkBalance)
      .addEffect(failingEffect)
      .addInteraction(notifyTransfer)
    
    # Create valid transaction
    let tx = Transaction(
      amount: 30.0,
      fromAccount: "alice",
      toAccount: "bob"
    )
    let txContext = newTransactionContext("tx-789", tx)
    
    # Process transaction
    var state = accounts
    let result = processorWithFailingEffect.process(txContext, state)
    
    # Verify results
    check result.success == false
    check result.status == tsFailed
    check result.error.isSome
    check result.error.get().msg.contains("Effect failed")
    
    # Verify no state changes (should be rolled back)
    check state["alice"].balance == 100.0  # Unchanged
    check state["bob"].balance == 50.0     # Unchanged

  test "DSL creates correct processor":
    # Create processor using DSL
    let dslProcessor = ceiProcessor[Transaction, TransferState, string]("DSLProcessor"):
      checks:
        checkBalance
      
      effects:
        updateBalances
      
      interactions:
        notifyTransfer
    
    # Create transaction
    let tx = Transaction(
      amount: 25.0,
      fromAccount: "alice",
      toAccount: "bob"
    )
    let txContext = newTransactionContext("tx-dsl", tx)
    
    # Process transaction
    var state = accounts
    let result = dslProcessor.process(txContext, state)
    
    # Verify results
    check result.success == true
    check result.status == tsCompleted
    check state["alice"].balance == 75.0  # 100 - 25
    check state["bob"].balance == 75.0    # 50 + 25

  test "Financial transaction processor template":
    # Create financial processor
    let financialProcessor = createFinancialTransactionProcessor[Transaction, TransferState](
      "FinancialProcessor",
      checkBalance,
      updateBalances,
      notifyTransfer
    )
    
    # Create transaction
    let tx = Transaction(
      amount: 10.0,
      fromAccount: "alice",
      toAccount: "bob"
    )
    let txContext = newTransactionContext("tx-financial", tx)
    
    # Process transaction
    var state = accounts
    let result = financialProcessor.process(txContext, state)
    
    # Verify results
    check result.success == true
    check result.status == tsCompleted
    check state["alice"].balance == 90.0  # 100 - 10
    check state["bob"].balance == 60.0    # 50 + 10

when isMainModule:
  unittest.run()