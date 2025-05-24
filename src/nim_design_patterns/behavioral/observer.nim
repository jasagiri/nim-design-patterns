## Observer Pattern implementation

import std/[tables, sets, strformat, options, hashes, json, times]
import results
import nim_libaspects/[logging, events]
import ../core/base

type
  Observer* = ref object of RootObj
    ## Base type for all observers
    name*: string
    active*: bool
    
  Subject* = ref object of Pattern
    ## Observable subject that notifies observers
    observers: HashSet[Observer]
    state: RootRef
    logger: Logger
    eventBus: EventBus
  
  UpdateFunc* = proc(observer: Observer, subject: Subject)
  
  ConcreteObserver* = ref object of Observer
    ## Observer with callback function
    updateFunc: UpdateFunc
  
  ObserverRegistry* = ref object
    ## Registry for managing observer relationships
    subjects: Table[string, Subject]
    observers: Table[string, Observer]

# Hash function for Observer to use in HashSet
proc hash*(observer: Observer): Hash =
  ## Hash function for Observer based on name and pointer
  hash((observer.name, cast[uint](observer)))
    
method update*(observer: Observer, subject: Subject) {.base.} =
  ## Base method to be overridden by concrete observers
  raise newException(CatchableError, "Abstract method called")

proc newObserver*(name: string, updateFunc: UpdateFunc): Observer =
  ## Create a new observer with callback function
  result = ConcreteObserver(
    name: name,
    active: true,
    updateFunc: updateFunc
  )

method update*(observer: ConcreteObserver, subject: Subject) =
  ## Update with callback function
  if observer.active and not observer.updateFunc.isNil:
    observer.updateFunc(observer, subject)

proc newSubject*(name = "Subject"): Subject =
  ## Create a new subject
  result = Subject(
    name: name,
    kind: pkBehavioral,
    description: "Observer pattern subject (observable)",
    observers: initHashSet[Observer]()
  )

proc withLogging*(subject: Subject, logger: Logger): Subject =
  ## Add logging to subject
  subject.logger = logger
  subject

proc withEventBus*(subject: Subject, eventBus: EventBus): Subject =
  ## Add event bus integration
  subject.eventBus = eventBus
  subject

proc attach*(subject: Subject, observer: Observer): Subject =
  ## Attach an observer to subject
  subject.observers.incl(observer)
  
  if not subject.logger.isNil:
    subject.logger.debug(&"Observer '{observer.name}' attached to subject '{subject.name}'")
  
  if not subject.eventBus.isNil:
    subject.eventBus.publish(newEvent("observer.attached", %*{
      "subject": subject.name,
      "observer": observer.name
    }))
  
  subject

proc detach*(subject: Subject, observer: Observer): Subject =
  ## Detach observer from subject
  subject.observers.excl(observer)
  
  if not subject.logger.isNil:
    subject.logger.debug(&"Observer '{observer.name}' detached from subject '{subject.name}'")
  
  if not subject.eventBus.isNil:
    subject.eventBus.publish(newEvent("observer.detached", %*{
      "subject": subject.name,
      "observer": observer.name
    }))
  
  subject

proc detachAll*(subject: Subject): Subject =
  ## Detach all observers
  let count = subject.observers.len
  subject.observers.clear()
  
  if not subject.logger.isNil:
    subject.logger.info(&"Detached all observers ({count}) from subject '{subject.name}'")
  
  if not subject.eventBus.isNil:
    subject.eventBus.publish(newEvent("observer.detached.all", %*{
      "subject": subject.name,
      "count": count
    }))
  
  subject

proc getState*(subject: Subject): RootRef =
  ## Get subject state
  subject.state

proc setState*(subject: Subject, state: RootRef): Subject =
  ## Set subject state and notify observers
  subject.state = state
  
  if not subject.logger.isNil:
    subject.logger.debug(&"State changed for subject '{subject.name}'")
  
  # Notify all observers
  let startTime = now()
  var notified = 0
  
  for observer in subject.observers:
    if observer.active:
      try:
        observer.update(subject)
        inc notified
      except CatchableError as e:
        if not subject.logger.isNil:
          subject.logger.error(&"Error notifying observer '{observer.name}': {e.msg}")
  
  if not subject.logger.isNil:
    let duration = now() - startTime
    subject.logger.info(&"Notified {notified} observers in {duration}ms")
  
  if not subject.eventBus.isNil:
    subject.eventBus.publish(newEvent("observer.state.changed", %*{
      "subject": subject.name,
      "observers_notified": notified
    }))
  
  subject

# Registry for managing multiple subjects and observers  
proc newObserverRegistry*(): ObserverRegistry =
  ## Create a new observer registry
  ObserverRegistry(
    subjects: initTable[string, Subject](),
    observers: initTable[string, Observer]()
  )

proc registerSubject*(registry: ObserverRegistry, 
                     subject: Subject): ObserverRegistry =
  ## Register a subject
  registry.subjects[subject.name] = subject
  registry

proc registerObserver*(registry: ObserverRegistry, 
                      observer: Observer): ObserverRegistry =
  ## Register an observer
  registry.observers[observer.name] = observer
  registry

proc getSubject*(registry: ObserverRegistry, 
                name: string): Option[Subject] =
  ## Get a subject by name
  if name in registry.subjects:
    some(registry.subjects[name])
  else:
    none(Subject)

proc getObserver*(registry: ObserverRegistry, 
                 name: string): Option[Observer] =
  ## Get an observer by name
  if name in registry.observers:
    some(registry.observers[name])
  else:
    none(Observer)

proc attachObserver*(registry: ObserverRegistry, 
                    subjectName: string, 
                    observerName: string): Result[void, PatternError] =
  ## Attach observer to subject by name
  let subject = registry.getSubject(subjectName)
  if subject.isNone:
    return Result[void, PatternError].err(
      newPatternError("ObserverRegistry", &"Subject '{subjectName}' not found")
    )
  
  let observer = registry.getObserver(observerName)
  if observer.isNone:
    return Result[void, PatternError].err(
      newPatternError("ObserverRegistry", &"Observer '{observerName}' not found")
    )
  
  discard subject.get().attach(observer.get())
  Result[void, PatternError].ok()

# Specialized observers
type
  LoggingObserver* = ref object of Observer
    ## Observer that logs all updates
    logger: Logger
  
  EventObserver* = ref object of Observer
    ## Observer that publishes events
    eventBus: EventBus
    eventType: string
  
  FilteredObserver* = ref object of Observer
    ## Observer that only processes certain updates
    baseObserver: Observer
    filter: proc(subject: Subject): bool

proc newLoggingObserver*(name: string, logger: Logger): LoggingObserver =
  ## Create observer that logs all updates
  result = LoggingObserver(
    name: name,
    active: true,
    logger: logger
  )

method update*(observer: LoggingObserver, subject: Subject) =
  ## Log subject update
  observer.logger.info(&"Subject '{subject.name}' updated", %*{
    "observer": observer.name,
    "subject": subject.name,
    "state": if subject.getState().isNil: "nil" else: "updated"
  })

proc newEventObserver*(name: string, 
                      eventBus: EventBus, 
                      eventType = "observer.update"): EventObserver =
  ## Create observer that publishes events
  result = EventObserver(
    name: name,
    active: true,
    eventBus: eventBus,
    eventType: eventType
  )

method update*(observer: EventObserver, subject: Subject) =
  ## Publish event on update
  observer.eventBus.publish(newEvent(observer.eventType, %*{
    "observer": observer.name,
    "subject": subject.name,
    "state": if subject.getState().isNil: "nil" else: "updated"
  }))

proc newFilteredObserver*(name: string, 
                         baseObserver: Observer,
                         filter: proc(subject: Subject): bool): FilteredObserver =
  ## Create filtered observer
  result = FilteredObserver(
    name: name,
    active: true,
    baseObserver: baseObserver,
    filter: filter
  )

method update*(observer: FilteredObserver, subject: Subject) =
  ## Update only if filter passes
  if observer.filter(subject):
    observer.baseObserver.update(subject)

# Templates for creating observers with closures
template observer*(name: string, body: untyped): Observer =
  ## Create observer with inline update function
  newObserver(name, proc(observer: Observer, subject: Subject) =
    body
  )

# Push-pull variations
type
  PushObserver* = ref object of Observer
    ## Observer that receives data directly (push model)
  
  PullObserver* = ref object of Observer
    ## Observer that retrieves data (pull model)
    getData: proc(subject: Subject): RootRef

proc newPushObserver*(name: string, 
                     updateFunc: proc(observer: Observer, data: RootRef)): PushObserver =
  ## Create push-based observer
  result = PushObserver(
    name: name,
    active: true
  )

proc newPullObserver*(name: string,
                     getData: proc(subject: Subject): RootRef,
                     processData: proc(observer: Observer, data: RootRef)): PullObserver =
  ## Create pull-based observer
  result = PullObserver(
    name: name,
    active: true,
    getData: getData
  )

method update*(observer: PullObserver, subject: Subject) =
  ## Pull data then process
  let data = observer.getData(subject)
  # Process data would be called here in a real implementation