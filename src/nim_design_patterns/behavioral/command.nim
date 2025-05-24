## Command Pattern implementation

import std/[tables, strformat, options, deques]
import results
import nim_libaspects/[logging, events]
import ../core/base

type
  Command* = ref object of Pattern
    ## Base command interface
    executed*: bool
    
  Invoker* = ref object of Pattern
    ## Executes commands
    history: Deque[Command]
    undoStack: Deque[Command]
    logger: Logger
    eventBus: EventBus
    maxHistory: int
    historyEnabled: bool
    undoEnabled: bool
  
  CommandResult* = ref object
    ## Result of command execution
    command*: Command
    success*: bool
    error*: string
    data*: RootRef
  
  CommandFactory* = ref object
    ## Factory for creating commands
    creators: Table[string, proc(): Command]
    
  CommandHandler* = ref object
    ## Handles command execution with middleware
    middlewares: seq[proc(cmd: Command, next: proc())]
    
  MacroCommand* = ref object of Command
    ## Composite command containing subcommands
    commands: seq[Command]
    executionStrategy: ExecutionStrategy
    
  ExecutionStrategy* = enum
    ## Command execution strategies
    esSequential, esParallel, esUntilFailure, esUntilSuccess

method execute*(cmd: Command): CommandResult {.base.} =
  ## Execute the command (to be overridden)
  raise newException(CatchableError, "Abstract method called")

method undo*(cmd: Command): CommandResult {.base.} =
  ## Undo the command (to be overridden)
  raise newException(CatchableError, "Abstract method called")

# Create a simple command result
proc newCommandResult*(command: Command, 
                      success = true, 
                      error = "", 
                      data: RootRef = nil): CommandResult =
  CommandResult(
    command: command,
    success: success,
    error: error,
    data: data
  )

# Invoker implementation
proc newInvoker*(name = "CommandInvoker"): Invoker =
  ## Create a new command invoker
  result = Invoker(
    name: name,
    kind: pkBehavioral,
    description: "Command pattern invoker",
    history: initDeque[Command](),
    undoStack: initDeque[Command](),
    maxHistory: 100,
    historyEnabled: true,
    undoEnabled: true
  )

proc withLogging*(invoker: Invoker, logger: Logger): Invoker =
  ## Add logging to invoker
  invoker.logger = logger
  invoker

proc withEventBus*(invoker: Invoker, eventBus: EventBus): Invoker =
  ## Add event publishing
  invoker.eventBus = eventBus
  invoker

proc withHistory*(invoker: Invoker, 
                 enabled = true, 
                 maxSize = 100): Invoker =
  ## Configure command history
  invoker.historyEnabled = enabled
  invoker.maxHistory = maxSize
  invoker

proc withUndo*(invoker: Invoker, enabled = true): Invoker =
  ## Configure undo capability
  invoker.undoEnabled = enabled
  invoker

proc execute*(invoker: Invoker, command: Command): CommandResult =
  ## Execute a command
  if not invoker.logger.isNil:
    invoker.logger.debug(&"Executing command '{command.name}'")
  
  try:
    let result = command.execute()
    
    # Record executed command in history if successful
    if result.success and invoker.historyEnabled:
      invoker.history.addLast(command)
      # Trim history if needed
      while invoker.history.len > invoker.maxHistory:
        discard invoker.history.popFirst()
      
      # Add to undo stack if undo is enabled
      if invoker.undoEnabled:
        invoker.undoStack.addLast(command)
    
    if not invoker.logger.isNil:
      if result.success:
        invoker.logger.info(&"Command '{command.name}' executed successfully")
      else:
        invoker.logger.error(&"Command '{command.name}' failed: {result.error}")
    
    if not invoker.eventBus.isNil:
      invoker.eventBus.publish(newEvent(
        if result.success: "command.success" else: "command.failure",
        %*{
          "command": command.name,
          "success": result.success,
          "error": result.error
        }
      ))
    
    result
    
  except CatchableError as e:
    if not invoker.logger.isNil:
      invoker.logger.error(&"Command '{command.name}' threw exception: {e.msg}")
    
    if not invoker.eventBus.isNil:
      invoker.eventBus.publish(newEvent("command.exception", %*{
        "command": command.name,
        "error": e.msg
      }))
    
    newCommandResult(command, false, e.msg)

proc undo*(invoker: Invoker): Option[CommandResult] =
  ## Undo last command
  if not invoker.undoEnabled:
    if not invoker.logger.isNil:
      invoker.logger.warn("Undo is disabled")
    return none(CommandResult)
  
  if invoker.undoStack.len == 0:
    if not invoker.logger.isNil:
      invoker.logger.warn("No commands to undo")
    return none(CommandResult)
  
  let command = invoker.undoStack.popLast()
  
  if not invoker.logger.isNil:
    invoker.logger.debug(&"Undoing command '{command.name}'")
  
  try:
    let result = command.undo()
    
    if not invoker.logger.isNil:
      if result.success:
        invoker.logger.info(&"Command '{command.name}' undone successfully")
      else:
        invoker.logger.error(&"Failed to undo command '{command.name}': {result.error}")
    
    if not invoker.eventBus.isNil:
      invoker.eventBus.publish(newEvent(
        if result.success: "command.undo.success" else: "command.undo.failure",
        %*{
          "command": command.name,
          "success": result.success,
          "error": result.error
        }
      ))
    
    some(result)
    
  except CatchableError as e:
    if not invoker.logger.isNil:
      invoker.logger.error(&"Command undo threw exception: {e.msg}")
    
    if not invoker.eventBus.isNil:
      invoker.eventBus.publish(newEvent("command.undo.exception", %*{
        "command": command.name,
        "error": e.msg
      }))
    
    some(newCommandResult(command, false, e.msg))

proc getHistory*(invoker: Invoker): seq[Command] =
  ## Get command execution history
  result = newSeq[Command](invoker.history.len)
  var i = 0
  for cmd in invoker.history:
    result[i] = cmd
    inc i

proc clearHistory*(invoker: Invoker) =
  ## Clear command history
  invoker.history.clear()
  invoker.undoStack.clear()
  
  if not invoker.logger.isNil:
    invoker.logger.info("Command history cleared")
  
  if not invoker.eventBus.isNil:
    invoker.eventBus.publish(newEvent("command.history.cleared", newJObject()))

# Concrete command types
type
  SimpleCommand* = ref object of Command
    ## Simple command with execute/undo functions
    executeFunc: proc(): CommandResult
    undoFunc: proc(): CommandResult
  
  ActionCommand*[T] = ref object of Command
    ## Command that operates on a receiver
    receiver: T
    executeAction: proc(receiver: T): CommandResult
    undoAction: proc(receiver: T): CommandResult

proc newSimpleCommand*(name: string, 
                      executeFunc: proc(): CommandResult,
                      undoFunc: proc(): CommandResult = nil): SimpleCommand =
  ## Create a simple command with functions
  result = SimpleCommand(
    name: name,
    kind: pkBehavioral,
    description: "Simple command",
    executeFunc: executeFunc,
    undoFunc: undoFunc,
    executed: false
  )

method execute*(cmd: SimpleCommand): CommandResult =
  ## Execute with function
  if cmd.executeFunc.isNil:
    return newCommandResult(cmd, false, "No execute function provided")
  
  let result = cmd.executeFunc()
  cmd.executed = result.success
  result

method undo*(cmd: SimpleCommand): CommandResult =
  ## Undo with function
  if not cmd.executed:
    return newCommandResult(cmd, false, "Command has not been executed")
  
  if cmd.undoFunc.isNil:
    return newCommandResult(cmd, false, "No undo function provided")
  
  let result = cmd.undoFunc()
  if result.success:
    cmd.executed = false
  
  result

proc newActionCommand*[T](name: string, 
                        receiver: T,
                        executeAction: proc(receiver: T): CommandResult,
                        undoAction: proc(receiver: T): CommandResult = nil): ActionCommand[T] =
  ## Create command operating on receiver
  result = ActionCommand[T](
    name: name,
    kind: pkBehavioral,
    description: &"Action command on {$T}",
    receiver: receiver,
    executeAction: executeAction,
    undoAction: undoAction,
    executed: false
  )

method execute*[T](cmd: ActionCommand[T]): CommandResult =
  ## Execute on receiver
  if cmd.executeAction.isNil:
    return newCommandResult(cmd, false, "No execute action provided")
  
  let result = cmd.executeAction(cmd.receiver)
  cmd.executed = result.success
  result

method undo*[T](cmd: ActionCommand[T]): CommandResult =
  ## Undo on receiver
  if not cmd.executed:
    return newCommandResult(cmd, false, "Command has not been executed")
  
  if cmd.undoAction.isNil:
    return newCommandResult(cmd, false, "No undo action provided")
  
  let result = cmd.undoAction(cmd.receiver)
  if result.success:
    cmd.executed = false
  
  result

# MacroCommand implementation
proc newMacroCommand*(name: string, 
                     commands: seq[Command],
                     strategy = esSequential): MacroCommand =
  ## Create composite command
  result = MacroCommand(
    name: name,
    kind: pkBehavioral,
    description: "Macro command (composite)",
    commands: commands,
    executionStrategy: strategy,
    executed: false
  )

method execute*(cmd: MacroCommand): CommandResult =
  ## Execute subcommands
  var 
    success = true
    errors = ""
    executed = 0
  
  case cmd.executionStrategy:
  of esSequential:
    # Execute all commands in sequence
    for command in cmd.commands:
      let result = command.execute()
      if not result.success:
        success = false
        errors &= result.error & "; "
      else:
        inc executed
      
  of esParallel:
    # In real implementation, we would use parallelism here
    # For now, just execute sequentially
    for command in cmd.commands:
      let result = command.execute()
      if not result.success:
        success = false
        errors &= result.error & "; "
      else:
        inc executed
  
  of esUntilFailure:
    # Execute until a command fails
    for command in cmd.commands:
      let result = command.execute()
      if not result.success:
        success = false
        errors = result.error
        break
      inc executed
      
  of esUntilSuccess:
    # Execute until a command succeeds
    success = false
    for command in cmd.commands:
      let result = command.execute()
      if result.success:
        success = true
        inc executed
        break
      errors &= result.error & "; "
  
  cmd.executed = success or executed > 0
  newCommandResult(cmd, success, errors, %*{"executed": executed})

method undo*(cmd: MacroCommand): CommandResult =
  ## Undo subcommands in reverse order
  if not cmd.executed:
    return newCommandResult(cmd, false, "Command has not been executed")
  
  var 
    success = true
    errors = ""
    undone = 0
  
  # Always undo in reverse order, regardless of execution strategy
  for i in countdown(cmd.commands.high, 0):
    let command = cmd.commands[i]
    if not command.executed:
      continue
      
    let result = command.undo()
    if not result.success:
      success = false
      errors &= result.error & "; "
    else:
      inc undone
  
  if success:
    cmd.executed = false
    
  newCommandResult(cmd, success, errors, %*{"undone": undone})

# Command Factory
proc newCommandFactory*(): CommandFactory =
  ## Create command factory
  CommandFactory(creators: initTable[string, proc(): Command]())

proc register*(factory: CommandFactory, 
              name: string, 
              creator: proc(): Command) =
  ## Register command creator
  factory.creators[name] = creator

proc create*(factory: CommandFactory, 
            name: string): Result[Command, PatternError] =
  ## Create command by name
  if name notin factory.creators:
    return Result[Command, PatternError].err(
      newPatternError("CommandFactory", &"No creator for command '{name}'")
    )
  
  try:
    let command = factory.creators[name]()
    Result[Command, PatternError].ok(command)
  except CatchableError as e:
    Result[Command, PatternError].err(
      newPatternError("CommandFactory", &"Failed to create command: {e.msg}")
    )

# Command Handler with middleware
proc newCommandHandler*(): CommandHandler =
  ## Create command handler with middleware support
  CommandHandler(middlewares: @[])

proc addMiddleware*(handler: CommandHandler, 
                   middleware: proc(cmd: Command, next: proc())) =
  ## Add command processing middleware
  handler.middlewares.add(middleware)

proc execute*(handler: CommandHandler, command: Command): CommandResult =
  ## Execute command with middleware chain
  var 
    currentIndex = 0
    result: CommandResult
  
  proc next() =
    if currentIndex < handler.middlewares.len:
      let middleware = handler.middlewares[currentIndex]
      inc currentIndex
      middleware(command, next)
    else:
      # End of middleware chain, execute command
      result = command.execute()
  
  next()
  result

# Helper templates
template command*(name: string, body: untyped): Command =
  ## Create command with inline implementation
  var cmd = SimpleCommand(
    name: name,
    kind: pkBehavioral,
    description: "Inline command",
    executed: false
  )
  
  cmd.executeFunc = proc(): CommandResult =
    try:
      body
      newCommandResult(cmd, true)
    except CatchableError as e:
      newCommandResult(cmd, false, e.msg)
  
  cmd

# Command middleware
proc loggingMiddleware*(logger: Logger): proc(cmd: Command, next: proc()) =
  ## Create logging middleware
  result = proc(cmd: Command, next: proc()) =
    logger.debug(&"Before executing command '{cmd.name}'")
    next()
    if cmd.executed:
      logger.info(&"Command '{cmd.name}' executed successfully")
    else:
      logger.warn(&"Command '{cmd.name}' failed")

proc metricsMiddleware*(metrics: MetricsRegistry): proc(cmd: Command, next: proc()) =
  ## Create metrics collection middleware
  result = proc(cmd: Command, next: proc()) =
    let startTime = now()
    metrics.increment("command.execute.count")
    next()
    let duration = now() - startTime
    metrics.recordTime("command.execute.time", duration)
    
    if cmd.executed:
      metrics.increment("command.success")
    else:
      metrics.increment("command.failure")

proc validationMiddleware*(validator: proc(cmd: Command): bool): proc(cmd: Command, next: proc()) =
  ## Create validation middleware
  result = proc(cmd: Command, next: proc()) =
    if validator(cmd):
      next()
    else:
      discard # Skip execution if validation fails