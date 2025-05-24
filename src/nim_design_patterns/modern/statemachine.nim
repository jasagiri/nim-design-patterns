## Modern State Machine Pattern implementation
##
## This implementation provides a flexible state machine with support for:
## - Type-safe state transitions
## - Guards and conditions
## - Entry/exit actions
## - Event-driven transitions
## - Hierarchical states
## - History states
## - State machine visualization

import std/[tables, sets, strformat, options, strutils, hashes]
import nim_libaspects/[logging, events, errors]
import ../core/base

type
  StateId* = distinct string
  EventId* = distinct string
  TransitionId* = distinct string
  
  StateKind* = enum
    ## Types of state in hierarchy
    skSimple    # Simple state
    skComposite # Contains sub-states
    skFinal     # Terminal state
    skInitial   # Starting state
    skHistory   # Remembers previous state
    skChoice    # Decision point
    
  TransitionKind* = enum
    ## Types of transitions
    tkInternal  # No state change, just action execution
    tkExternal  # Normal transition between states
    tkLocal     # Transition to sub-state without exit/entry actions
    tkSelf      # Transition to same state (triggers exit/entry)
    
  Guard* = proc(): bool
  Action* = proc()
  ParameterizedAction* = proc(params: JsonNode)
  
  State*[T] = ref object of Pattern
    ## State implementation
    id*: StateId
    kind*: StateKind
    parent*: State[T]
    substates*: Table[StateId, State[T]]
    entryActions*: seq[Action]
    exitActions*: seq[Action]
    data*: T
    activeSubstate*: Option[StateId]  # For composite states
    historyState*: Option[StateId]    # For history states
    initialState*: Option[StateId]    # For composite states
    
  Transition*[T] = ref object of Pattern
    ## Transition between states
    id*: TransitionId
    kind*: TransitionKind
    sourceId*: StateId
    targetId*: StateId
    eventId*: EventId
    guard*: Guard
    actions*: seq[Action]
    priority*: int
    
  StateMachine*[T] = ref object of Pattern
    ## State machine implementation
    states*: Table[StateId, State[T]]
    transitions*: seq[Transition[T]]
    currentStateId*: StateId
    initialStateId*: StateId
    finalStates*: HashSet[StateId]
    eventTransitions*: Table[EventId, seq[Transition[T]]]
    logger*: Logger
    eventBus*: EventBus
    context*: T  # User context data
    parameterizedActions*: Table[string, ParameterizedAction]
    stateHistory*: seq[StateId]
    
  StateMachineBuilder*[T] = ref object
    ## Builder for state machines
    machine*: StateMachine[T]
    currentState*: State[T]
    currentTransition*: Transition[T]
    
  StateMachineError* = object of CatchableError
    ## Error during state machine operation
    
  StateMachineVisualizer* = object
    ## Generates visualization of state machine
    
  StateMachineEvent* = enum
    ## Events emitted by state machine
    smeStateEntered
    smeStateExited
    smeTransitionTriggered
    smeGuardFailed
    smeActionExecuted
    smeMachineStarted
    smeMachineCompleted

# String conversions
proc `$`*(id: StateId): string = id.string
proc `$`*(id: EventId): string = id.string
proc `$`*(id: TransitionId): string = id.string

# Equality and hashing
proc `==`*(a, b: StateId): bool {.borrow.}
proc `==`*(a, b: EventId): bool {.borrow.}
proc `==`*(a, b: TransitionId): bool {.borrow.}

proc hash*(id: StateId): Hash {.borrow.}
proc hash*(id: EventId): Hash {.borrow.}
proc hash*(id: TransitionId): Hash {.borrow.}

# State implementation
proc newState*[T](id: string, kind = skSimple): State[T] =
  ## Create a new state
  result = State[T](
    id: StateId(id),
    kind: kind,
    name: id,
    description: &"State '{id}'",
    substates: initTable[StateId, State[T]](),
    entryActions: @[],
    exitActions: @[]
  )

proc addEntryAction*[T](state: State[T], action: Action): State[T] =
  ## Add entry action to state
  state.entryActions.add(action)
  state

proc addExitAction*[T](state: State[T], action: Action): State[T] =
  ## Add exit action to state
  state.exitActions.add(action)
  state

proc addSubstate*[T](state: State[T], substate: State[T]): State[T] =
  ## Add substate to composite state
  if state.kind != skComposite:
    raise newException(StateMachineError, 
      &"Cannot add substate to non-composite state '{state.id}'")
  
  state.substates[substate.id] = substate
  substate.parent = state
  
  # If this is the first substate, make it the initial one
  if state.initialState.isNone:
    state.initialState = some(substate.id)
  
  state

proc setInitialState*[T](state: State[T], substateId: StateId): State[T] =
  ## Set initial substate for composite state
  if state.kind != skComposite:
    raise newException(StateMachineError, 
      &"Cannot set initial state for non-composite state '{state.id}'")
  
  if substateId notin state.substates:
    raise newException(StateMachineError,
      &"Cannot set unknown state '{substateId}' as initial state for '{state.id}'")
  
  state.initialState = some(substateId)
  state

proc getEffectiveSubstate*[T](state: State[T]): State[T] =
  ## Get active substate or initial substate
  if state.kind != skComposite:
    return state
  
  if state.activeSubstate.isSome:
    return state.substates[state.activeSubstate.get()]
  
  if state.initialState.isSome:
    state.activeSubstate = state.initialState
    return state.substates[state.initialState.get()]
  
  state  # No substates, return self

proc enterState*[T](state: State[T]) =
  ## Execute entry actions
  for action in state.entryActions:
    action()
  
  # If composite state, enter initial substate
  if state.kind == skComposite and state.initialState.isSome:
    state.activeSubstate = state.initialState
    state.substates[state.initialState.get()].enterState()

proc exitState*[T](state: State[T]) =
  ## Execute exit actions
  # If composite state with active substate, exit it first
  if state.kind == skComposite and state.activeSubstate.isSome:
    state.substates[state.activeSubstate.get()].exitState()
    
    # Store in history if parent has a history state
    if state.parent != nil and state.parent.kind == skHistory:
      state.parent.historyState = state.activeSubstate
  
  # Execute own exit actions
  for action in state.exitActions:
    action()

proc isInState*[T](state: State[T], stateId: StateId): bool =
  ## Check if state is active or contains active substate
  if state.id == stateId:
    return true
  
  if state.kind == skComposite and state.activeSubstate.isSome:
    return state.substates[state.activeSubstate.get()].isInState(stateId)
  
  false

# Transition implementation  
proc newTransition*[T](id: string, 
                      sourceId: StateId, 
                      targetId: StateId,
                      eventId: EventId,
                      kind = tkExternal): Transition[T] =
  ## Create a new transition
  result = Transition[T](
    id: TransitionId(id),
    kind: kind,
    name: id,
    description: &"Transition from '{sourceId}' to '{targetId}' on '{eventId}'",
    sourceId: sourceId,
    targetId: targetId,
    eventId: eventId,
    actions: @[],
    priority: 0
  )

proc withGuard*[T](transition: Transition[T], guard: Guard): Transition[T] =
  ## Add guard to transition
  transition.guard = guard
  transition

proc addAction*[T](transition: Transition[T], action: Action): Transition[T] =
  ## Add action to transition
  transition.actions.add(action)
  transition

proc setPriority*[T](transition: Transition[T], priority: int): Transition[T] =
  ## Set transition priority (higher executes first)
  transition.priority = priority
  transition

proc canFire*[T](transition: Transition[T]): bool =
  ## Check if transition can fire (guard condition)
  if transition.guard.isNil:
    return true
  
  transition.guard()

proc execute*[T](transition: Transition[T]) =
  ## Execute transition actions
  for action in transition.actions:
    action()

# State Machine implementation
proc newStateMachine*[T](name: string, context: T = default(T)): StateMachine[T] =
  ## Create a new state machine
  result = StateMachine[T](
    name: name,
    kind: pkBehavioral,
    description: &"State Machine '{name}'",
    states: initTable[StateId, State[T]](),
    transitions: @[],
    finalStates: initHashSet[StateId](),
    eventTransitions: initTable[EventId, seq[Transition[T]]](),
    context: context,
    parameterizedActions: initTable[string, ParameterizedAction](),
    stateHistory: @[]
  )

proc withLogging*[T](machine: StateMachine[T], logger: Logger): StateMachine[T] =
  ## Add logging to state machine
  machine.logger = logger
  machine

proc withEventBus*[T](machine: StateMachine[T], eventBus: EventBus): StateMachine[T] =
  ## Add event bus to state machine
  machine.eventBus = eventBus
  machine

proc addState*[T](machine: StateMachine[T], state: State[T]): StateMachine[T] =
  ## Add state to machine
  machine.states[state.id] = state
  
  # If first state or initial state, set as initial
  if machine.states.len == 1 or state.kind == skInitial:
    machine.initialStateId = state.id
  
  # If final state, add to final states
  if state.kind == skFinal:
    machine.finalStates.incl(state.id)
  
  machine

proc addTransition*[T](machine: StateMachine[T], 
                      transition: Transition[T]): StateMachine[T] =
  ## Add transition to machine
  # Validate states exist
  if transition.sourceId notin machine.states:
    raise newException(StateMachineError,
      &"Source state '{transition.sourceId}' does not exist in state machine")
  
  if transition.targetId notin machine.states:
    raise newException(StateMachineError,
      &"Target state '{transition.targetId}' does not exist in state machine")
  
  machine.transitions.add(transition)
  
  # Add to event map for quick lookup
  if transition.eventId notin machine.eventTransitions:
    machine.eventTransitions[transition.eventId] = @[]
  
  # Insert transition sorted by priority
  var inserted = false
  for i in 0..<machine.eventTransitions[transition.eventId].len:
    if machine.eventTransitions[transition.eventId][i].priority < transition.priority:
      machine.eventTransitions[transition.eventId].insert(transition, i)
      inserted = true
      break
  
  if not inserted:
    machine.eventTransitions[transition.eventId].add(transition)
  
  machine

proc addParameterizedAction*[T](machine: StateMachine[T],
                              name: string,
                              action: ParameterizedAction): StateMachine[T] =
  ## Add named parameterized action
  machine.parameterizedActions[name] = action
  machine

proc start*[T](machine: StateMachine[T]): Result[void, ref CatchableError] =
  ## Start the state machine
  if machine.states.len == 0:
    return Result[void, ref CatchableError].err(
      (ref StateMachineError)(msg: "Cannot start state machine with no states")
    )
  
  if machine.initialStateId notin machine.states:
    return Result[void, ref CatchableError].err(
      (ref StateMachineError)(msg: "Initial state not defined")
    )
  
  if not machine.logger.isNil:
    machine.logger.info(&"Starting state machine '{machine.name}' in state '{machine.initialStateId}'")
  
  if not machine.eventBus.isNil:
    machine.eventBus.publish(newEvent("statemachine.started", %*{
      "machine": machine.name,
      "initialState": $machine.initialStateId
    }))
  
  # Set initial state
  machine.currentStateId = machine.initialStateId
  machine.stateHistory.add(machine.currentStateId)
  
  # Enter the state (and its substates if composite)
  machine.states[machine.currentStateId].enterState()
  
  Result[void, ref CatchableError].ok()

proc getCurrentState*[T](machine: StateMachine[T]): State[T] =
  ## Get current state
  machine.states[machine.currentStateId]

proc isInState*[T](machine: StateMachine[T], stateId: StateId): bool =
  ## Check if machine is in state (including substates)
  machine.states[machine.currentStateId].isInState(stateId)

proc isInFinalState*[T](machine: StateMachine[T]): bool =
  ## Check if machine is in a final state
  machine.currentStateId in machine.finalStates

proc getStateHistory*[T](machine: StateMachine[T]): seq[StateId] =
  ## Get the history of visited states
  machine.stateHistory

proc findLeastCommonAncestor*[T](machine: StateMachine[T], 
                               source: State[T], 
                               target: State[T]): State[T] =
  ## Find the least common ancestor of two states
  if source.id == target.id:
    return source
  
  # Collect ancestors of source
  var sourceAncestors = initHashSet[StateId]()
  var current = source
  
  while current.parent != nil:
    sourceAncestors.incl(current.parent.id)
    current = current.parent
  
  # Find lowest common ancestor
  current = target
  while current.parent != nil:
    if current.parent.id in sourceAncestors:
      return current.parent
    current = current.parent
  
  nil  # No common ancestor

proc executeStateTransition*[T](machine: StateMachine[T], 
                              transition: Transition[T]): bool =
  ## Execute a transition between states
  # Get states
  let source = machine.states[transition.sourceId]
  let target = machine.states[transition.targetId]
  
  # Check if transition can fire
  if not transition.canFire():
    if not machine.logger.isNil:
      machine.logger.debug(&"Transition '{transition.id}' guard condition failed")
    
    if not machine.eventBus.isNil:
      machine.eventBus.publish(newEvent("statemachine.guard.failed", %*{
        "machine": machine.name,
        "transition": $transition.id
      }))
    
    return false
  
  if not machine.logger.isNil:
    machine.logger.info(&"Executing transition from '{transition.sourceId}' to '{transition.targetId}'")
  
  if not machine.eventBus.isNil:
    machine.eventBus.publish(newEvent("statemachine.transition", %*{
      "machine": machine.name,
      "transition": $transition.id,
      "from": $transition.sourceId,
      "to": $transition.targetId
    }))
  
  # Handle different transition kinds
  case transition.kind:
  of tkInternal:
    # Just execute actions without state change
    transition.execute()
    return true
    
  of tkSelf:
    # Exit and re-enter same state
    source.exitState()
    transition.execute()
    source.enterState()
    return true
    
  of tkLocal:
    # For parent->child transitions without exit/entry actions
    if target.parent != nil and target.parent.id == source.id:
      transition.execute()
      if source.kind == skComposite:
        source.activeSubstate = some(target.id)
        target.enterState()
      return true
    
  of tkExternal:
    # Normal state transition
    
    # Find least common ancestor (LCA)
    let lca = machine.findLeastCommonAncestor(source, target)
    
    # Exit states up to LCA
    var current = source
    while current != nil and (lca.isNil or current.id != lca.id):
      current.exitState()
      current = current.parent
    
    # Execute transition actions
    transition.execute()
    
    # Enter states from LCA to target
    var entryPath: seq[State[T]] = @[]
    current = target
    
    while current != nil and (lca.isNil or current.id != lca.id):
      entryPath.insert(current, 0)
      current = current.parent
    
    # Enter states in path
    for state in entryPath:
      state.enterState()
    
    # Update current state
    machine.currentStateId = target.id
    machine.stateHistory.add(machine.currentStateId)
    
    return true
  
  false

proc fireEvent*[T](machine: StateMachine[T], 
                  eventId: EventId,
                  parameters: JsonNode = nil): bool =
  ## Fire an event in the state machine
  if eventId notin machine.eventTransitions:
    if not machine.logger.isNil:
      machine.logger.debug(&"No transitions defined for event '{eventId}'")
    return false
  
  # Get current state
  let currentState = machine.states[machine.currentStateId]
  
  # Find enabled transitions for this event
  var executed = false
  for transition in machine.eventTransitions[eventId]:
    # Check if source state matches
    if not currentState.isInState(transition.sourceId):
      continue
    
    # Try to execute transition
    executed = machine.executeStateTransition(transition)
    if executed:
      # Execute any parameterized actions
      if not parameters.isNil and parameters.hasKey("action"):
        let actionName = parameters["action"].getStr()
        if actionName in machine.parameterizedActions:
          machine.parameterizedActions[actionName](parameters)
      
      break  # Stop after first successful transition
  
  # Check if now in a final state
  if machine.isInFinalState():
    if not machine.logger.isNil:
      machine.logger.info(&"State machine '{machine.name}' reached final state '{machine.currentStateId}'")
    
    if not machine.eventBus.isNil:
      machine.eventBus.publish(newEvent("statemachine.completed", %*{
        "machine": machine.name,
        "finalState": $machine.currentStateId
      }))
  
  executed

proc fireEventWithString*[T](machine: StateMachine[T], 
                           eventName: string,
                           parameters: JsonNode = nil): bool =
  ## Fire an event by string name
  machine.fireEvent(EventId(eventName), parameters)

proc reset*[T](machine: StateMachine[T]): Result[void, ref CatchableError] =
  ## Reset state machine to initial state
  # Exit current state
  machine.states[machine.currentStateId].exitState()
  
  # Clear history
  machine.stateHistory = @[]
  
  # Start from initial state
  machine.start()

# Builder implementation
proc newStateMachineBuilder*[T](name: string, context: T = default(T)): StateMachineBuilder[T] =
  ## Create a state machine builder
  result = StateMachineBuilder[T](
    machine: newStateMachine[T](name, context)
  )

proc withState*[T](builder: StateMachineBuilder[T], 
                  id: string, 
                  kind = skSimple): StateMachineBuilder[T] =
  ## Add state to machine
  let state = newState[T](id, kind)
  builder.machine.addState(state)
  builder.currentState = state
  builder

proc withInitialState*[T](builder: StateMachineBuilder[T], 
                         id: string): StateMachineBuilder[T] =
  ## Add initial state
  let state = newState[T](id, skInitial)
  builder.machine.addState(state)
  builder.currentState = state
  builder.machine.initialStateId = state.id
  builder

proc withFinalState*[T](builder: StateMachineBuilder[T], 
                       id: string): StateMachineBuilder[T] =
  ## Add final state
  let state = newState[T](id, skFinal)
  builder.machine.addState(state)
  builder.currentState = state
  builder.machine.finalStates.incl(state.id)
  builder

proc withCompositeState*[T](builder: StateMachineBuilder[T], 
                          id: string): StateMachineBuilder[T] =
  ## Add composite state
  let state = newState[T](id, skComposite)
  builder.machine.addState(state)
  builder.currentState = state
  builder

proc withHistoryState*[T](builder: StateMachineBuilder[T], 
                         id: string): StateMachineBuilder[T] =
  ## Add history state
  let state = newState[T](id, skHistory)
  builder.machine.addState(state)
  builder.currentState = state
  builder

proc withChoiceState*[T](builder: StateMachineBuilder[T], 
                        id: string): StateMachineBuilder[T] =
  ## Add choice state
  let state = newState[T](id, skChoice)
  builder.machine.addState(state)
  builder.currentState = state
  builder

proc withEntryAction*[T](builder: StateMachineBuilder[T], 
                        action: Action): StateMachineBuilder[T] =
  ## Add entry action to current state
  if builder.currentState.isNil:
    raise newException(StateMachineError, "No current state selected")
  
  builder.currentState.addEntryAction(action)
  builder

proc withExitAction*[T](builder: StateMachineBuilder[T], 
                       action: Action): StateMachineBuilder[T] =
  ## Add exit action to current state
  if builder.currentState.isNil:
    raise newException(StateMachineError, "No current state selected")
  
  builder.currentState.addExitAction(action)
  builder

proc withSubstate*[T](builder: StateMachineBuilder[T], 
                     id: string, 
                     kind = skSimple): StateMachineBuilder[T] =
  ## Add substate to current state
  if builder.currentState.isNil:
    raise newException(StateMachineError, "No current state selected")
  
  if builder.currentState.kind != skComposite:
    raise newException(StateMachineError, 
      &"Cannot add substate to non-composite state '{builder.currentState.id}'")
  
  let substate = newState[T](id, kind)
  builder.currentState.addSubstate(substate)
  builder.machine.states[substate.id] = substate
  builder.currentState = substate
  builder

proc endSubstate*[T](builder: StateMachineBuilder[T]): StateMachineBuilder[T] =
  ## Return to parent state
  if builder.currentState.isNil:
    raise newException(StateMachineError, "No current state selected")
  
  if builder.currentState.parent.isNil:
    raise newException(StateMachineError, "Current state has no parent")
  
  builder.currentState = builder.currentState.parent
  builder

proc withTransition*[T](builder: StateMachineBuilder[T],
                       sourceId: string,
                       targetId: string,
                       eventId: string,
                       kind = tkExternal): StateMachineBuilder[T] =
  ## Add transition between states
  let transition = newTransition[T](
    &"{sourceId}_to_{targetId}_on_{eventId}",
    StateId(sourceId),
    StateId(targetId),
    EventId(eventId),
    kind
  )
  
  builder.machine.addTransition(transition)
  builder.currentTransition = transition
  builder

proc withGuardCondition*[T](builder: StateMachineBuilder[T], 
                          guard: Guard): StateMachineBuilder[T] =
  ## Add guard to current transition
  if builder.currentTransition.isNil:
    raise newException(StateMachineError, "No current transition selected")
  
  builder.currentTransition.withGuard(guard)
  builder

proc withAction*[T](builder: StateMachineBuilder[T], 
                   action: Action): StateMachineBuilder[T] =
  ## Add action to current transition
  if builder.currentTransition.isNil:
    raise newException(StateMachineError, "No current transition selected")
  
  builder.currentTransition.addAction(action)
  builder

proc withPriority*[T](builder: StateMachineBuilder[T], 
                     priority: int): StateMachineBuilder[T] =
  ## Set priority for current transition
  if builder.currentTransition.isNil:
    raise newException(StateMachineError, "No current transition selected")
  
  builder.currentTransition.setPriority(priority)
  builder

proc withParameterizedAction*[T](builder: StateMachineBuilder[T],
                               name: string,
                               action: ParameterizedAction): StateMachineBuilder[T] =
  ## Register a parameterized action
  builder.machine.addParameterizedAction(name, action)
  builder

proc withLogging*[T](builder: StateMachineBuilder[T], 
                    logger: Logger): StateMachineBuilder[T] =
  ## Add logging to state machine
  builder.machine.withLogging(logger)
  builder

proc withEventBus*[T](builder: StateMachineBuilder[T], 
                     eventBus: EventBus): StateMachineBuilder[T] =
  ## Add event bus to state machine
  builder.machine.withEventBus(eventBus)
  builder

proc build*[T](builder: StateMachineBuilder[T]): StateMachine[T] =
  ## Build the state machine
  builder.machine

# Visualization (simplified)
proc generatePlantUml*[T](machine: StateMachine[T]): string =
  ## Generate PlantUML diagram of state machine
  result = "@startuml\n\n"
  
  # Title
  result &= &"title State Machine: {machine.name}\n\n"
  
  # States
  for id, state in machine.states:
    case state.kind:
    of skInitial:
      result &= &"[*] --> {state.id}\n"
    of skFinal:
      result &= &"state \"{state.id}\" as {state.id} <<end>>\n"
    of skComposite:
      result &= &"state \"{state.id}\" as {state.id} {{\n"
      for subId, substate in state.substates:
        result &= &"  state \"{subId}\"\n"
      result &= "}\n"
    of skHistory:
      result &= &"state \"{state.id}\" as {state.id} <<history>>\n"
    of skChoice:
      result &= &"state \"{state.id}\" as {state.id} <<choice>>\n"
    else:
      result &= &"state \"{state.id}\"\n"
  
  # Transitions
  for transition in machine.transitions:
    var label = $transition.eventId
    
    if not transition.guard.isNil:
      label &= " [guard]"
    
    if transition.actions.len > 0:
      label &= " / action"
    
    result &= &"{transition.sourceId} --> {transition.targetId} : {label}\n"
  
  result &= "@enduml\n"

proc generateMermaid*[T](machine: StateMachine[T]): string =
  ## Generate Mermaid diagram of state machine
  result = "stateDiagram-v2\n"
  
  # States
  for id, state in machine.states:
    # Special states
    case state.kind:
    of skInitial:
      result &= &"[*] --> {state.id}\n"
    of skFinal:
      result &= &"state \"{state.id}\" as {state.id}\n"
      result &= &"{state.id} --> [*]\n"
    of skComposite:
      result &= &"state {state.id} {{\n"
      for subId, substate in state.substates:
        result &= &"  {subId}\n"
      result &= "}\n"
    else:
      result &= &"state \"{state.id}\" as {state.id}\n"
  
  # Transitions
  for transition in machine.transitions:
    var label = $transition.eventId
    
    if not transition.guard.isNil:
      label &= " [guard]"
    
    if transition.actions.len > 0:
      label &= " / action"
    
    result &= &"{transition.sourceId} --> {transition.targetId} : {label}\n"

# Templates for concise state machine creation
template stateMachine*[T](name: string, context: T, body: untyped): StateMachine[T] =
  ## Create state machine with DSL
  var builder = newStateMachineBuilder[T](name, context)
  body
  builder.build()

# Template for defining entry/exit actions in DSL
template onEntry*(actions: untyped): untyped =
  ## Define entry actions in DSL
  for action in actions:
    discard builder.withEntryAction(action)

template onExit*(actions: untyped): untyped =
  ## Define exit actions in DSL
  for action in actions:
    discard builder.withExitAction(action)

# Convenience methods for common state machine patterns
proc createSimpleStateMachine*[T](states: seq[string], 
                                transitions: seq[tuple[from, to, event: string]]): StateMachine[T] =
  ## Create a simple flat state machine
  var builder = newStateMachineBuilder[T]("SimpleMachine")
  
  # Add states
  for state in states:
    discard builder.withState(state)
  
  # Add transitions
  for trans in transitions:
    discard builder.withTransition(trans.from, trans.to, trans.event)
  
  builder.build()

proc createTrafficLightStateMachine*(): StateMachine[void] =
  ## Create a traffic light state machine example
  stateMachine("TrafficLight", default(void)):
    discard builder.withInitialState("Red")
      .withEntryAction(proc() = echo "Red light on")
      .withExitAction(proc() = echo "Red light off")
      
    discard builder.withState("Yellow")
      .withEntryAction(proc() = echo "Yellow light on")
      .withExitAction(proc() = echo "Yellow light off")
      
    discard builder.withState("Green")
      .withEntryAction(proc() = echo "Green light on")
      .withExitAction(proc() = echo "Green light off")
      
    # Transitions
    discard builder.withTransition("Red", "Green", "timer")
    discard builder.withTransition("Green", "Yellow", "timer")
    discard builder.withTransition("Yellow", "Red", "timer")