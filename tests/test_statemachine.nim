## Test suite for State Machine pattern

import std/[unittest, strformat, tables]
import nim_libaspects/[logging, events]
import nim_design_patterns/modern/statemachine

# Helper proc to export for test_all.nim
proc runTests*(): int =
  # Return number of failures
  let results = unittest.runTests()
  results.failures

suite "State Machine Pattern Tests":
  setup:
    # Create test subject
    var 
      enterRed = 0
      exitRed = 0
      enterYellow = 0
      exitYellow = 0
      enterGreen = 0
      exitGreen = 0
    
    let eventBus = newEventBus()
    var eventsReceived: seq[string] = @[]
    
    discard eventBus.subscribe("statemachine.*", proc(e: Event) =
      eventsReceived.add(e.eventType)
    )
    
    let machine = newStateMachine[void]("TrafficLight")
      .withEventBus(eventBus)
  
  test "State machine transitions between states":
    # Create state machine
    let red = newState[void]("Red")
      .addEntryAction(proc() = inc enterRed)
      .addExitAction(proc() = inc exitRed)
    
    let yellow = newState[void]("Yellow")
      .addEntryAction(proc() = inc enterYellow)
      .addExitAction(proc() = inc exitYellow)
    
    let green = newState[void]("Green")
      .addEntryAction(proc() = inc enterGreen)
      .addExitAction(proc() = inc exitGreen)
    
    # Configure machine
    machine.addState(red)
           .addState(yellow)
           .addState(green)
    
    # Add transitions
    machine.addTransition(
      newTransition[void]("RedToGreen", StateId("Red"), StateId("Green"), EventId("Timer"))
    )
    
    machine.addTransition(
      newTransition[void]("GreenToYellow", StateId("Green"), StateId("Yellow"), EventId("Timer"))
    )
    
    machine.addTransition(
      newTransition[void]("YellowToRed", StateId("Yellow"), StateId("Red"), EventId("Timer"))
    )
    
    # Start machine in Red state
    let startResult = machine.start()
    check startResult.isOk()
    check machine.getCurrentState().id == StateId("Red")
    check enterRed == 1  # Entry action should be called
    
    # Fire events to change states
    let redToGreen = machine.fireEvent(EventId("Timer"))
    check redToGreen
    check machine.getCurrentState().id == StateId("Green")
    check exitRed == 1   # Exit action should be called
    check enterGreen == 1  # Entry action should be called
    
    let greenToYellow = machine.fireEvent(EventId("Timer"))
    check greenToYellow
    check machine.getCurrentState().id == StateId("Yellow")
    check exitGreen == 1
    check enterYellow == 1
    
    let yellowToRed = machine.fireEvent(EventId("Timer"))
    check yellowToRed
    check machine.getCurrentState().id == StateId("Red")
    check exitYellow == 1
    check enterRed == 2  # Second time entering Red
    
    # Events should have been published
    check eventsReceived.len >= 4  # Started + at least 3 transitions
    check "statemachine.started" in eventsReceived
    check "statemachine.transition" in eventsReceived
  
  test "State machine with guards":
    # Create states
    let s1 = newState[void]("S1")
    let s2 = newState[void]("S2")
    
    # Configure machine
    machine.addState(s1)
           .addState(s2)
    
    # Add transition with guard that blocks
    let blockedTransition = newTransition[void](
      "BlockedTransition", StateId("S1"), StateId("S2"), EventId("E1")
    ).withGuard(proc(): bool = false)  # Always blocks
    
    machine.addTransition(blockedTransition)
    
    # Add transition with guard that passes
    let allowedTransition = newTransition[void](
      "AllowedTransition", StateId("S1"), StateId("S2"), EventId("E2")
    ).withGuard(proc(): bool = true)  # Always passes
    
    machine.addTransition(allowedTransition)
    
    # Start machine
    discard machine.start()
    check machine.getCurrentState().id == StateId("S1")
    
    # Try blocked transition
    let blocked = machine.fireEvent(EventId("E1"))
    check not blocked
    check machine.getCurrentState().id == StateId("S1")  # Should not change
    
    # Try allowed transition
    let allowed = machine.fireEvent(EventId("E2"))
    check allowed
    check machine.getCurrentState().id == StateId("S2")  # Should change
  
  test "State machine with actions on transitions":
    var actionExecuted = 0
    
    # Create states
    let s1 = newState[void]("S1")
    let s2 = newState[void]("S2")
    
    # Configure machine
    machine.addState(s1)
           .addState(s2)
    
    # Add transition with action
    let transition = newTransition[void](
      "TransitionWithAction", StateId("S1"), StateId("S2"), EventId("E1")
    ).addAction(proc() = inc actionExecuted)
    
    machine.addTransition(transition)
    
    # Start machine
    discard machine.start()
    
    # Execute transition
    let result = machine.fireEvent(EventId("E1"))
    check result
    
    # Action should be executed
    check actionExecuted == 1
  
  test "State machine with composite states":
    var enterParent = 0
    var exitParent = 0
    var enterChild1 = 0
    var exitChild1 = 0
    var enterChild2 = 0
    var exitChild2 = 0
    
    # Create parent composite state
    let parent = newState[void]("Parent", skComposite)
      .addEntryAction(proc() = inc enterParent)
      .addExitAction(proc() = inc exitParent)
    
    # Create child states
    let child1 = newState[void]("Child1")
      .addEntryAction(proc() = inc enterChild1)
      .addExitAction(proc() = inc exitChild1)
    
    let child2 = newState[void]("Child2")
      .addEntryAction(proc() = inc enterChild2)
      .addExitAction(proc() = inc exitChild2)
    
    # Add children to parent
    parent.addSubstate(child1)
         .addSubstate(child2)
         .setInitialState(StateId("Child1"))
    
    # Create another state outside parent
    let outside = newState[void]("Outside")
    
    # Configure machine
    machine.addState(parent)
           .addState(outside)
    
    # Add transitions
    machine.addTransition(
      newTransition[void]("OutsideToParent", 
                         StateId("Outside"), StateId("Parent"), 
                         EventId("E1"))
    )
    
    machine.addTransition(
      newTransition[void]("Child1ToChild2", 
                         StateId("Child1"), StateId("Child2"), 
                         EventId("E2"))
    )
    
    machine.addTransition(
      newTransition[void]("ParentToOutside", 
                         StateId("Parent"), StateId("Outside"), 
                         EventId("E3"))
    )
    
    # Start machine
    machine.initialStateId = StateId("Outside")
    discard machine.start()
    check machine.getCurrentState().id == StateId("Outside")
    
    # Transition to parent (should enter both parent and initial child)
    let toParent = machine.fireEvent(EventId("E1"))
    check toParent
    check machine.isInState(StateId("Parent"))
    check machine.isInState(StateId("Child1"))
    check enterParent == 1
    check enterChild1 == 1
    
    # Transition between children
    let betweenChildren = machine.fireEvent(EventId("E2"))
    check betweenChildren
    check machine.isInState(StateId("Parent"))
    check machine.isInState(StateId("Child2"))
    check exitChild1 == 1
    check enterChild2 == 1
    check enterParent == 1  # Parent shouldn't be re-entered
    
    # Exit parent
    let exitAllStates = machine.fireEvent(EventId("E3"))
    check exitAllStates
    check machine.getCurrentState().id == StateId("Outside")
    check exitChild2 == 1
    check exitParent == 1
  
  test "State machine history":
    # Create state machine
    let stateA = newState[void]("A")
    let stateB = newState[void]("B")
    let stateC = newState[void]("C")
    
    # Configure machine
    machine.addState(stateA)
           .addState(stateB)
           .addState(stateC)
    
    # Add transitions
    machine.addTransition(
      newTransition[void]("AToB", StateId("A"), StateId("B"), EventId("E1"))
    )
    
    machine.addTransition(
      newTransition[void]("BToC", StateId("B"), StateId("C"), EventId("E2"))
    )
    
    machine.addTransition(
      newTransition[void]("CToA", StateId("C"), StateId("A"), EventId("E3"))
    )
    
    # Start machine
    discard machine.start()
    
    # Execute transitions
    discard machine.fireEvent(EventId("E1"))  # A -> B
    discard machine.fireEvent(EventId("E2"))  # B -> C
    discard machine.fireEvent(EventId("E3"))  # C -> A
    
    # Check history
    let history = machine.getStateHistory()
    check history.len == 4  # Initial state + 3 transitions
    check history[0] == StateId("A")
    check history[1] == StateId("B")
    check history[2] == StateId("C")
    check history[3] == StateId("A")
  
  test "State machine reset":
    # Create states
    let stateA = newState[void]("A")
    let stateB = newState[void]("B")
    
    # Configure machine
    machine.addState(stateA)
           .addState(stateB)
    
    # Add transition
    machine.addTransition(
      newTransition[void]("AToB", StateId("A"), StateId("B"), EventId("E1"))
    )
    
    # Start machine in state A
    discard machine.start()
    check machine.getCurrentState().id == StateId("A")
    
    # Transition to state B
    discard machine.fireEvent(EventId("E1"))
    check machine.getCurrentState().id == StateId("B")
    
    # Reset machine
    let resetResult = machine.reset()
    check resetResult.isOk()
    
    # Should be back at initial state
    check machine.getCurrentState().id == StateId("A")
    
    # History should be reset
    check machine.getStateHistory().len == 1
    check machine.getStateHistory()[0] == StateId("A")

suite "State Machine Builder Tests":
  test "Build state machine with builder pattern":
    var 
      enterRed = 0
      enterYellow = 0
      enterGreen = 0
    
    # Create with builder
    let machine = newStateMachineBuilder[void]("TrafficLight")
      .withInitialState("Red")
      .withEntryAction(proc() = inc enterRed)
      .withState("Yellow")
      .withEntryAction(proc() = inc enterYellow)
      .withState("Green")
      .withEntryAction(proc() = inc enterGreen)
      .withTransition("Red", "Green", "Timer")
      .withTransition("Green", "Yellow", "Timer")
      .withTransition("Yellow", "Red", "Timer")
      .build()
    
    # Start machine
    discard machine.start()
    check machine.getCurrentState().id == StateId("Red")
    check enterRed == 1
    
    # Execute transitions
    discard machine.fireEvent(EventId("Timer"))  # Red -> Green
    check machine.getCurrentState().id == StateId("Green")
    check enterGreen == 1
    
    discard machine.fireEvent(EventId("Timer"))  # Green -> Yellow
    check machine.getCurrentState().id == StateId("Yellow")
    check enterYellow == 1
    
    discard machine.fireEvent(EventId("Timer"))  # Yellow -> Red
    check machine.getCurrentState().id == StateId("Red")
    check enterRed == 2
  
  test "Build state machine with composite states":
    # Create with builder
    let machine = newStateMachineBuilder[void]("CompositeTest")
      .withInitialState("Outside")
      .withCompositeState("Parent")
      .withSubstate("Child1", skInitial)
      .withSubstate("Child2")
      .endSubstate()  # Back to parent
      .withTransition("Outside", "Parent", "Enter")
      .withTransition("Child1", "Child2", "Next")
      .withTransition("Parent", "Outside", "Exit")
      .build()
    
    # Start machine
    discard machine.start()
    check machine.getCurrentState().id == StateId("Outside")
    
    # Enter composite state
    discard machine.fireEvent(EventId("Enter"))
    check machine.isInState(StateId("Parent"))
    check machine.isInState(StateId("Child1"))
    
    # Transition between substates
    discard machine.fireEvent(EventId("Next"))
    check machine.isInState(StateId("Parent"))
    check machine.isInState(StateId("Child2"))
    
    # Exit composite state
    discard machine.fireEvent(EventId("Exit"))
    check machine.getCurrentState().id == StateId("Outside")

suite "State Machine Visualization Tests":
  test "Generate PlantUML diagram":
    # Create simple state machine
    let machine = newStateMachineBuilder[void]("TrafficLight")
      .withInitialState("Red")
      .withState("Yellow")
      .withState("Green")
      .withTransition("Red", "Green", "Timer")
      .withTransition("Green", "Yellow", "Timer")
      .withTransition("Yellow", "Red", "Timer")
      .build()
    
    # Generate diagram
    let diagram = generatePlantUml(machine)
    
    # Check that diagram contains the states and transitions
    check "@startuml" in diagram
    check "state \"Red\"" in diagram
    check "state \"Yellow\"" in diagram
    check "state \"Green\"" in diagram
    check "Red --> Green" in diagram
    check "Green --> Yellow" in diagram
    check "Yellow --> Red" in diagram
    check "@enduml" in diagram

when isMainModule:
  unittest.run()