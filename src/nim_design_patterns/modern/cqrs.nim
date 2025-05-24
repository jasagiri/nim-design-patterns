## CQRS (Command Query Responsibility Segregation) Pattern implementation
##
## This implementation provides a clean separation between commands (write operations)
## and queries (read operations) with support for:
## - Command handling and dispatching
## - Query handling and result caching
## - Event sourcing integration
## - Read models and projections
## - Command validation
## - Middleware pipeline

import std/[tables, sets, hashes, strformat, options, times, typetraits, macros]
import nim_libaspects/[logging, errors, events]
import ../core/base

type
  # Command related types
  CommandId* = distinct string
  Command* = ref object of RootObj
    ## Base type for all commands
    id*: CommandId
    timestamp*: DateTime
  
  CommandHandler*[TCommand, TResult] = proc(cmd: TCommand): Result[TResult, ref AppError]
  CommandMiddleware* = proc(cmd: Command, next: proc(): Result[RootRef, ref AppError]): Result[RootRef, ref AppError]
  
  CommandDispatcher* = ref object of Pattern
    ## Dispatches commands to appropriate handlers
    handlers*: Table[string, RootRef]
    middleware*: seq[CommandMiddleware]
    logger*: Logger
    eventBus*: EventBus
  
  # Query related types
  QueryId* = distinct string
  Query*[TResult] = ref object of RootObj
    ## Base type for all queries
    id*: QueryId
    cacheDuration*: Option[Duration]
  
  QueryHandler*[TQuery, TResult] = proc(query: TQuery): Result[TResult, ref AppError]
  QueryMiddleware* = proc(query: RootRef, next: proc(): Result[RootRef, ref AppError]): Result[RootRef, ref AppError]
  
  QueryDispatcher* = ref object of Pattern
    ## Dispatches queries to appropriate handlers
    handlers*: Table[string, RootRef]
    middleware*: seq[QueryMiddleware]
    logger*: Logger
    cache*: QueryCache
  
  # Cache for query results
  CacheKey* = object
    queryType*: string
    queryId*: string
    
  CacheEntry* = object
    result*: Result[RootRef, ref AppError]
    expiration*: DateTime
  
  QueryCache* = ref object
    ## Cache for query results
    entries*: Table[CacheKey, CacheEntry]
    enabled*: bool
    defaultDuration*: Duration
  
  # Event sourcing integration
  EventSourcedRepository*[T] = ref object of Pattern
    ## Repository that uses event sourcing
    eventStore*: EventStore
    snapshotStore*: SnapshotStore
    reconstitutionStrategy*: ReconstitutionStrategy[T]
  
  EventStore* = ref object of Pattern
    ## Stores domain events
    events*: Table[string, seq[DomainEvent]]
    eventBus*: EventBus
  
  SnapshotStore* = ref object of Pattern
    ## Stores aggregate snapshots
    snapshots*: Table[string, RootRef]
  
  ReconstitutionStrategy*[T] = proc(events: seq[DomainEvent]): T
  
  DomainEvent* = ref object of RootObj
    ## Base type for all domain events
    id*: string
    aggregateId*: string
    aggregateType*: string
    timestamp*: DateTime
    version*: int
  
  # Read model and projections
  ReadModel* = ref object of RootObj
    ## Base type for read models
    id*: string
  
  Projection*[T] = ref object of Pattern
    ## Updates read models based on events
    eventBus*: EventBus
    readModels*: Table[string, T]
    handlers*: Table[string, proc(event: DomainEvent, model: T)]
  
  # Validation
  CommandValidationError* = ref object of AppError
    fieldErrors*: Table[string, string]
  
  CommandValidator*[T] = proc(cmd: T): Result[void, CommandValidationError]

# String conversion for IDs
proc `$`*(id: CommandId): string = id.string
proc `$`*(id: QueryId): string = id.string

# Equality and hash operators
proc `==`*(a, b: CommandId): bool {.borrow.}
proc `==`*(a, b: QueryId): bool {.borrow.}

proc hash*(id: CommandId): Hash {.borrow.}
proc hash*(id: QueryId): Hash {.borrow.}

# Command related implementations
proc newCommand*(id: string): Command =
  ## Create a new base command
  Command(
    id: CommandId(id),
    timestamp: now()
  )

proc newCommandDispatcher*(): CommandDispatcher =
  ## Create a new command dispatcher
  result = CommandDispatcher(
    name: "CommandDispatcher",
    kind: pkBehavioral,
    description: "CQRS command dispatcher",
    handlers: initTable[string, RootRef](),
    middleware: @[]
  )

proc withLogging*(dispatcher: CommandDispatcher, 
                 logger: Logger): CommandDispatcher =
  ## Add logging to dispatcher
  dispatcher.logger = logger
  dispatcher

proc withEventBus*(dispatcher: CommandDispatcher, 
                  eventBus: EventBus): CommandDispatcher =
  ## Add event bus to dispatcher
  dispatcher.eventBus = eventBus
  dispatcher

proc addMiddleware*(dispatcher: CommandDispatcher,
                   middleware: CommandMiddleware): CommandDispatcher =
  ## Add command middleware
  dispatcher.middleware.add(middleware)
  dispatcher

proc registerHandler*[TCommand, TResult](dispatcher: CommandDispatcher,
                                       handler: CommandHandler[TCommand, TResult]): CommandDispatcher =
  ## Register a command handler
  let commandType = $TCommand
  
  if commandType in dispatcher.handlers:
    if not dispatcher.logger.isNil:
      dispatcher.logger.warn(&"Handler for command type {commandType} is being replaced")
  
  dispatcher.handlers[commandType] = cast[RootRef](handler)
  
  if not dispatcher.logger.isNil:
    dispatcher.logger.debug(&"Registered handler for command type {commandType}")
  
  dispatcher

proc applyMiddleware*[TCommand, TResult](dispatcher: CommandDispatcher,
                                       cmd: TCommand,
                                       handler: CommandHandler[TCommand, TResult]): Result[TResult, ref AppError] =
  ## Apply middleware pipeline to command
  if dispatcher.middleware.len == 0:
    # No middleware, call handler directly
    return handler(cmd)
  
  # Get command type for logging
  let commandType = $TCommand
  
  # Convert to generic types for middleware
  let command = Command(cmd)
  
  # Define recursive middleware runner
  var currentIndex = 0
  var result: Result[RootRef, ref AppError]
  
  proc next(): Result[RootRef, ref AppError] =
    if currentIndex < dispatcher.middleware.len:
      let middleware = dispatcher.middleware[currentIndex]
      inc currentIndex
      middleware(command, next)
    else:
      # End of middleware chain, call handler
      let handlerResult = handler(cmd)
      
      # Convert to RootRef for middleware chain
      if handlerResult.isOk:
        var refResult: RootRef
        when TResult is ref:
          refResult = cast[RootRef](handlerResult.get())
        else:
          # For non-ref types, wrap in a ref object
          type ResultWrapper = ref object
            value: TResult
          
          let wrapper = ResultWrapper(value: handlerResult.get())
          refResult = cast[RootRef](wrapper)
        
        Result[RootRef, ref AppError].ok(refResult)
      else:
        Result[RootRef, ref AppError].err(handlerResult.error)
  
  # Run middleware chain
  result = next()
  
  # Convert result back to specific type
  if result.isOk:
    let refResult = result.get()
    
    when TResult is ref:
      var typedResult = cast[TResult](refResult)
      Result[TResult, ref AppError].ok(typedResult)
    else:
      let wrapper = cast[ref object](refResult)
      let fieldName = "value"
      let value = wrapper.getField(fieldName, TResult)
      Result[TResult, ref AppError].ok(value)
  else:
    Result[TResult, ref AppError].err(result.error)

proc dispatch*[TCommand, TResult](dispatcher: CommandDispatcher,
                                cmd: TCommand): Result[TResult, ref AppError] =
  ## Dispatch command to appropriate handler
  let commandType = $TCommand
  
  if not dispatcher.logger.isNil:
    dispatcher.logger.debug(&"Dispatching command of type {commandType}")
  
  if commandType notin dispatcher.handlers:
    if not dispatcher.logger.isNil:
      dispatcher.logger.error(&"No handler registered for command type {commandType}")
    
    return Result[TResult, ref AppError].err(
      (ref AppError)(msg: &"No handler registered for command type {commandType}")
    )
  
  # Get handler and convert to correct type
  let handlerRef = dispatcher.handlers[commandType]
  let handler = cast[CommandHandler[TCommand, TResult]](handlerRef)
  
  # Apply middleware and get result
  let startTime = getTime()
  let result = dispatcher.applyMiddleware(cmd, handler)
  let duration = getTime() - startTime
  
  # Log result
  if not dispatcher.logger.isNil:
    if result.isOk:
      dispatcher.logger.info(&"Command {commandType} processed successfully in {duration}")
    else:
      dispatcher.logger.error(&"Command {commandType} failed: {result.error.msg}")
  
  # Publish event
  if not dispatcher.eventBus.isNil:
    let eventData = %*{
      "commandType": commandType,
      "commandId": $Command(cmd).id,
      "success": result.isOk,
      "duration": $duration
    }
    
    if result.isErr:
      eventData["error"] = %result.error.msg
    
    dispatcher.eventBus.publish(newEvent(
      if result.isOk: "command.succeeded" else: "command.failed",
      eventData
    ))
  
  result

# Query related implementations
proc newQuery*[TResult](id: string, cacheDuration: Duration = default(Duration)): Query[TResult] =
  ## Create a new query
  result = Query[TResult](
    id: QueryId(id)
  )
  
  if cacheDuration.microseconds > 0:
    result.cacheDuration = some(cacheDuration)

proc newQueryCache*(defaultDuration = initDuration(minutes = 5)): QueryCache =
  ## Create a new query cache
  QueryCache(
    entries: initTable[CacheKey, CacheEntry](),
    enabled: true,
    defaultDuration: defaultDuration
  )

proc clear*(cache: QueryCache) =
  ## Clear all cache entries
  cache.entries.clear()

proc enable*(cache: QueryCache) =
  ## Enable caching
  cache.enabled = true

proc disable*(cache: QueryCache) =
  ## Disable caching
  cache.enabled = false

proc removeExpiredEntries*(cache: QueryCache) =
  ## Remove expired cache entries
  let now = now()
  var expiredKeys: seq[CacheKey] = @[]
  
  for key, entry in cache.entries:
    if entry.expiration < now:
      expiredKeys.add(key)
  
  for key in expiredKeys:
    cache.entries.del(key)

proc createCacheKey*[T](query: T): CacheKey =
  ## Create cache key from query
  CacheKey(
    queryType: $T,
    queryId: when query is Query: $query.id else: $hash(query)
  )

proc get*[T](cache: QueryCache, query: T): Option[Result[RootRef, ref AppError]] =
  ## Get cached result for query
  if not cache.enabled:
    return none(Result[RootRef, ref AppError])
  
  let key = createCacheKey(query)
  
  if key notin cache.entries:
    return none(Result[RootRef, ref AppError])
  
  let entry = cache.entries[key]
  
  # Check if expired
  if entry.expiration < now():
    cache.entries.del(key)
    return none(Result[RootRef, ref AppError])
  
  some(entry.result)

proc set*[T](cache: QueryCache, query: T, 
            result: Result[RootRef, ref AppError]) =
  ## Set cached result for query
  if not cache.enabled:
    return
  
  # Remove expired entries first to avoid cache bloat
  cache.removeExpiredEntries()
  
  # Create key and determine expiration
  let key = createCacheKey(query)
  
  # Calculate expiration time
  let expirationPeriod = 
    if query is Query and Query(query).cacheDuration.isSome:
      Query(query).cacheDuration.get()
    else:
      cache.defaultDuration
  
  let expiration = now() + expirationPeriod
  
  # Store result
  cache.entries[key] = CacheEntry(
    result: result,
    expiration: expiration
  )

proc newQueryDispatcher*(): QueryDispatcher =
  ## Create a new query dispatcher
  result = QueryDispatcher(
    name: "QueryDispatcher",
    kind: pkBehavioral,
    description: "CQRS query dispatcher",
    handlers: initTable[string, RootRef](),
    middleware: @[],
    cache: newQueryCache()
  )

proc withLogging*(dispatcher: QueryDispatcher, 
                 logger: Logger): QueryDispatcher =
  ## Add logging to dispatcher
  dispatcher.logger = logger
  dispatcher

proc withCache*(dispatcher: QueryDispatcher, 
               cache: QueryCache): QueryDispatcher =
  ## Set custom cache
  dispatcher.cache = cache
  dispatcher

proc addMiddleware*(dispatcher: QueryDispatcher,
                   middleware: QueryMiddleware): QueryDispatcher =
  ## Add query middleware
  dispatcher.middleware.add(middleware)
  dispatcher

proc registerHandler*[TQuery, TResult](dispatcher: QueryDispatcher,
                                     handler: QueryHandler[TQuery, TResult]): QueryDispatcher =
  ## Register a query handler
  let queryType = $TQuery
  
  if queryType in dispatcher.handlers:
    if not dispatcher.logger.isNil:
      dispatcher.logger.warn(&"Handler for query type {queryType} is being replaced")
  
  dispatcher.handlers[queryType] = cast[RootRef](handler)
  
  if not dispatcher.logger.isNil:
    dispatcher.logger.debug(&"Registered handler for query type {queryType}")
  
  dispatcher

proc applyMiddleware*[TQuery, TResult](dispatcher: QueryDispatcher,
                                     query: TQuery,
                                     handler: QueryHandler[TQuery, TResult]): Result[TResult, ref AppError] =
  ## Apply middleware pipeline to query
  if dispatcher.middleware.len == 0:
    # No middleware, call handler directly
    return handler(query)
  
  # Get query type for logging
  let queryType = $TQuery
  
  # Define recursive middleware runner
  var currentIndex = 0
  var result: Result[RootRef, ref AppError]
  
  proc next(): Result[RootRef, ref AppError] =
    if currentIndex < dispatcher.middleware.len:
      let middleware = dispatcher.middleware[currentIndex]
      inc currentIndex
      middleware(cast[RootRef](query), next)
    else:
      # End of middleware chain, call handler
      let handlerResult = handler(query)
      
      # Convert to RootRef for middleware chain
      if handlerResult.isOk:
        var refResult: RootRef
        when TResult is ref:
          refResult = cast[RootRef](handlerResult.get())
        else:
          # For non-ref types, wrap in a ref object
          type ResultWrapper = ref object
            value: TResult
          
          let wrapper = ResultWrapper(value: handlerResult.get())
          refResult = cast[RootRef](wrapper)
        
        Result[RootRef, ref AppError].ok(refResult)
      else:
        Result[RootRef, ref AppError].err(handlerResult.error)
  
  # Run middleware chain
  result = next()
  
  # Convert result back to specific type
  if result.isOk:
    let refResult = result.get()
    
    when TResult is ref:
      let typedResult = cast[TResult](refResult)
      Result[TResult, ref AppError].ok(typedResult)
    else:
      let wrapper = cast[ref object](refResult)
      let fieldName = "value"
      let value = wrapper.getField(fieldName, TResult)
      Result[TResult, ref AppError].ok(value)
  else:
    Result[TResult, ref AppError].err(result.error)

proc dispatch*[TQuery, TResult](dispatcher: QueryDispatcher,
                              query: TQuery): Result[TResult, ref AppError] =
  ## Dispatch query to appropriate handler
  let queryType = $TQuery
  
  if not dispatcher.logger.isNil:
    dispatcher.logger.debug(&"Dispatching query of type {queryType}")
  
  # Check cache first
  let cachedResult = dispatcher.cache.get(query)
  if cachedResult.isSome:
    if not dispatcher.logger.isNil:
      dispatcher.logger.debug(&"Using cached result for query type {queryType}")
    
    let result = cachedResult.get()
    
    # Convert to specific type
    if result.isOk:
      let refResult = result.get()
      
      when TResult is ref:
        let typedResult = cast[TResult](refResult)
        return Result[TResult, ref AppError].ok(typedResult)
      else:
        let wrapper = cast[ref object](refResult)
        let fieldName = "value"
        let value = wrapper.getField(fieldName, TResult)
        return Result[TResult, ref AppError].ok(value)
    else:
      return Result[TResult, ref AppError].err(result.error)
  
  # No cached result, process query
  if queryType notin dispatcher.handlers:
    if not dispatcher.logger.isNil:
      dispatcher.logger.error(&"No handler registered for query type {queryType}")
    
    return Result[TResult, ref AppError].err(
      (ref AppError)(msg: &"No handler registered for query type {queryType}")
    )
  
  # Get handler and convert to correct type
  let handlerRef = dispatcher.handlers[queryType]
  let handler = cast[QueryHandler[TQuery, TResult]](handlerRef)
  
  # Apply middleware and get result
  let startTime = getTime()
  let result = dispatcher.applyMiddleware(query, handler)
  let duration = getTime() - startTime
  
  # Log result
  if not dispatcher.logger.isNil:
    if result.isOk:
      dispatcher.logger.info(&"Query {queryType} processed successfully in {duration}")
    else:
      dispatcher.logger.error(&"Query {queryType} failed: {result.error.msg}")
  
  # Cache result if successful
  if result.isOk:
    # Convert to RootRef for caching
    var refResult: RootRef
    when TResult is ref:
      refResult = cast[RootRef](result.get())
    else:
      # For non-ref types, wrap in a ref object
      type ResultWrapper = ref object
        value: TResult
      
      let wrapper = ResultWrapper(value: result.get())
      refResult = cast[RootRef](wrapper)
    
    dispatcher.cache.set(query, Result[RootRef, ref AppError].ok(refResult))
  
  result

# Event sourcing related implementations
proc newEventStore*(eventBus: EventBus = nil): EventStore =
  ## Create a new event store
  EventStore(
    name: "EventStore",
    kind: pkBehavioral,
    description: "CQRS event store",
    events: initTable[string, seq[DomainEvent]](),
    eventBus: eventBus
  )

proc append*(store: EventStore, event: DomainEvent) =
  ## Append event to store
  let aggregateId = event.aggregateId
  
  if aggregateId notin store.events:
    store.events[aggregateId] = @[]
  
  store.events[aggregateId].add(event)
  
  # Publish event if event bus is configured
  if not store.eventBus.isNil:
    store.eventBus.publish(newEvent(
      &"domain.{event.aggregateType}.{event.id}",
      %*{
        "aggregateId": event.aggregateId,
        "aggregateType": event.aggregateType,
        "eventType": event.id,
        "version": event.version
      }
    ))

proc appendAll*(store: EventStore, events: seq[DomainEvent]) =
  ## Append multiple events to store
  for event in events:
    store.append(event)

proc getEvents*(store: EventStore, aggregateId: string): seq[DomainEvent] =
  ## Get all events for an aggregate
  if aggregateId notin store.events:
    return @[]
  
  store.events[aggregateId]

proc getEventsAfterVersion*(store: EventStore, 
                           aggregateId: string, 
                           version: int): seq[DomainEvent] =
  ## Get events after a specific version
  let events = store.getEvents(aggregateId)
  result = @[]
  
  for event in events:
    if event.version > version:
      result.add(event)

proc newSnapshotStore*(): SnapshotStore =
  ## Create a new snapshot store
  SnapshotStore(
    name: "SnapshotStore",
    kind: pkBehavioral,
    description: "CQRS snapshot store",
    snapshots: initTable[string, RootRef]()
  )

proc saveSnapshot*[T](store: SnapshotStore, 
                     aggregateId: string, 
                     snapshot: T) =
  ## Save aggregate snapshot
  store.snapshots[aggregateId] = cast[RootRef](snapshot)

proc getSnapshot*[T](store: SnapshotStore, 
                    aggregateId: string): Option[T] =
  ## Get aggregate snapshot
  if aggregateId notin store.snapshots:
    return none(T)
  
  let snapshot = store.snapshots[aggregateId]
  some(cast[T](snapshot))

proc newEventSourcedRepository*[T](
    eventStore: EventStore,
    snapshotStore: SnapshotStore,
    reconstitutionStrategy: ReconstitutionStrategy[T]): EventSourcedRepository[T] =
  ## Create event sourced repository
  EventSourcedRepository[T](
    name: "EventSourcedRepository",
    kind: pkBehavioral,
    description: &"CQRS repository for {$T}",
    eventStore: eventStore,
    snapshotStore: snapshotStore,
    reconstitutionStrategy: reconstitutionStrategy
  )

proc getById*[T](repo: EventSourcedRepository[T], 
                aggregateId: string): Option[T] =
  ## Get aggregate by ID
  # Try to get from snapshot first
  let snapshot = repo.snapshotStore.getSnapshot[T](aggregateId)
  
  if snapshot.isSome:
    return snapshot
  
  # No snapshot, reconstitute from events
  let events = repo.eventStore.getEvents(aggregateId)
  
  if events.len == 0:
    return none(T)
  
  let aggregate = repo.reconstitutionStrategy(events)
  
  # Save snapshot for future use if large number of events
  if events.len > 100:
    repo.snapshotStore.saveSnapshot(aggregateId, aggregate)
  
  some(aggregate)

proc save*[T](repo: EventSourcedRepository[T], 
             aggregate: T, 
             newEvents: seq[DomainEvent]) =
  ## Save aggregate with new events
  # Add events to store
  repo.eventStore.appendAll(newEvents)
  
  # Save snapshot if large number of events
  if newEvents.len > 10:
    let aggregateId = newEvents[0].aggregateId
    repo.snapshotStore.saveSnapshot(aggregateId, aggregate)

# Read model and projections
proc newProjection*[T](eventBus: EventBus): Projection[T] =
  ## Create a new projection
  Projection[T](
    name: "Projection",
    kind: pkBehavioral,
    description: &"CQRS projection for {$T}",
    eventBus: eventBus,
    readModels: initTable[string, T](),
    handlers: initTable[string, proc(event: DomainEvent, model: T)]()
  )

proc registerHandler*[T](projection: Projection[T],
                        eventType: string,
                        handler: proc(event: DomainEvent, model: T)) =
  ## Register event handler for projection
  projection.handlers[eventType] = handler

proc getReadModel*[T](projection: Projection[T], id: string): Option[T] =
  ## Get read model by ID
  if id notin projection.readModels:
    return none(T)
  
  some(projection.readModels[id])

proc handleEvent*[T](projection: Projection[T], event: DomainEvent) =
  ## Handle domain event
  if event.id notin projection.handlers:
    return
  
  let handler = projection.handlers[event.id]
  let aggregateId = event.aggregateId
  
  # Get or create read model
  var model: T
  
  if aggregateId in projection.readModels:
    model = projection.readModels[aggregateId]
  else:
    model = new T
    model.id = aggregateId
    projection.readModels[aggregateId] = model
  
  # Update model
  handler(event, model)

proc subscribe*[T](projection: Projection[T]) =
  ## Subscribe to domain events
  discard projection.eventBus.subscribe("domain.*", proc(e: Event) =
    # Extract domain event from event
    let data = e.data
    
    # Create domain event
    let domainEvent = DomainEvent(
      id: data["eventType"].getStr(),
      aggregateId: data["aggregateId"].getStr(),
      aggregateType: data["aggregateType"].getStr(),
      version: data["version"].getInt(),
      timestamp: now()
    )
    
    # Handle event
    projection.handleEvent(domainEvent)
  )

# Command validation
proc newCommandValidationError*(msg: string): CommandValidationError =
  ## Create command validation error
  CommandValidationError(
    msg: msg,
    fieldErrors: initTable[string, string]()
  )

proc addFieldError*(error: CommandValidationError,
                   field: string,
                   message: string) =
  ## Add field-specific validation error
  error.fieldErrors[field] = message

# Middleware for common use cases
proc loggingMiddleware*(logger: Logger): CommandMiddleware =
  ## Middleware for logging
  result = proc(cmd: Command, next: proc(): Result[RootRef, ref AppError]): Result[RootRef, ref AppError] =
    logger.debug(&"Processing command {cmd.id} of type {cmd.type}")
    
    let startTime = getTime()
    let result = next()
    let duration = getTime() - startTime
    
    if result.isOk:
      logger.info(&"Command {cmd.id} processed successfully in {duration}")
    else:
      logger.error(&"Command {cmd.id} failed: {result.error.msg}")
    
    result

proc validationMiddleware*[T](validator: CommandValidator[T]): CommandMiddleware =
  ## Middleware for command validation
  result = proc(cmd: Command, next: proc(): Result[RootRef, ref AppError]): Result[RootRef, ref AppError] =
    # Skip if not the correct command type
    if not (cmd of T):
      return next()
    
    # Validate command
    let typedCmd = T(cmd)
    let validationResult = validator(typedCmd)
    
    if validationResult.isErr:
      return Result[RootRef, ref AppError].err(
        cast[ref AppError](validationResult.error)
      )
    
    # Continue processing
    next()

proc transactionMiddleware*(beginTx, commitTx, rollbackTx: proc()): CommandMiddleware =
  ## Middleware for transaction handling
  result = proc(cmd: Command, next: proc(): Result[RootRef, ref AppError]): Result[RootRef, ref AppError] =
    beginTx()
    
    try:
      let result = next()
      
      if result.isOk:
        commitTx()
      else:
        rollbackTx()
      
      result
    except:
      rollbackTx()
      raise

# Convenience templates for defining commands and queries
template defineCommand*(name: untyped, fields: untyped): untyped =
  ## Define a command type
  type
    `name`* = ref object of Command
      `fields`

template defineQuery*(name: untyped, resultType: typedesc, fields: untyped): untyped =
  ## Define a query type
  type
    `name`* = ref object of Query[resultType]
      `fields`

# CQRS framework integration
type
  CqrsFramework* = ref object of Pattern
    ## Main CQRS framework
    commandDispatcher*: CommandDispatcher
    queryDispatcher*: QueryDispatcher
    eventStore*: EventStore
    snapshotStore*: SnapshotStore
    eventBus*: EventBus
    logger*: Logger

proc newCqrsFramework*(): CqrsFramework =
  ## Create a complete CQRS framework
  let eventBus = newEventBus()
  
  result = CqrsFramework(
    name: "CqrsFramework",
    kind: pkBehavioral,
    description: "CQRS framework",
    commandDispatcher: newCommandDispatcher(),
    queryDispatcher: newQueryDispatcher(),
    eventStore: newEventStore(eventBus),
    snapshotStore: newSnapshotStore(),
    eventBus: eventBus
  )

proc withLogging*(framework: CqrsFramework, logger: Logger): CqrsFramework =
  ## Add logging to framework
  framework.logger = logger
  framework.commandDispatcher.withLogging(logger)
  framework.queryDispatcher.withLogging(logger)
  framework

proc sendCommand*[TCommand, TResult](framework: CqrsFramework,
                                   cmd: TCommand): Result[TResult, ref AppError] =
  ## Send command to framework
  framework.commandDispatcher.dispatch[TCommand, TResult](cmd)

proc executeQuery*[TQuery, TResult](framework: CqrsFramework,
                                  query: TQuery): Result[TResult, ref AppError] =
  ## Execute query in framework
  framework.queryDispatcher.dispatch[TQuery, TResult](query)

proc createRepository*[T](framework: CqrsFramework,
                         reconstitutionStrategy: ReconstitutionStrategy[T]): EventSourcedRepository[T] =
  ## Create repository with framework services
  newEventSourcedRepository[T](
    framework.eventStore,
    framework.snapshotStore,
    reconstitutionStrategy
  )