## Proxy Pattern implementation

import std/[macros, strformat]
import results
import nim_libaspects/[logging, events, monitoring]
import ../core/base

type
  ProxyKind* = enum
    pkRemote = "Remote"
    pkVirtual = "Virtual"
    pkProtection = "Protection"
    pkLogging = "Logging"
    pkCaching = "Caching"
  
  Proxy*[T] = ref object of Pattern
    ## Generic proxy implementation
    subject: T
    kind: ProxyKind
    logger: Logger
    events: EventBus
    monitor: MonitoringSystem
    accessChecker: proc(): bool
    
  ProxyFactory*[T] = ref object
    ## Factory for creating proxies
    templates: Table[string, proc(subject: T): Proxy[T]]

proc newProxy*[T](subject: T, kind: ProxyKind, name = ""): Proxy[T] =
  ## Create a new proxy
  result = Proxy[T](
    name: if name.len > 0: name else: &"{kind}Proxy_{$T}",
    kind: pkStructural,
    description: &"{kind} proxy for {$T}",
    subject: subject,
    kind: kind
  )

proc withLogging*[T](proxy: Proxy[T], logger: Logger): Proxy[T] =
  ## Add logging to proxy
  proxy.logger = logger
  proxy

proc withEvents*[T](proxy: Proxy[T], events: EventBus): Proxy[T] =
  ## Add event publishing to proxy
  proxy.events = events
  proxy

proc withMonitoring*[T](proxy: Proxy[T], monitor: MonitoringSystem): Proxy[T] =
  ## Add monitoring to proxy
  proxy.monitor = monitor
  proxy

proc setAccessChecker*[T](proxy: Proxy[T], checker: proc(): bool): Proxy[T] =
  ## Set access control for protection proxy
  proxy.accessChecker = checker
  proxy

proc beforeAccess*[T](proxy: Proxy[T], methodName: string): bool =
  ## Called before method access
  if not proxy.logger.isNil:
    proxy.logger.debug(&"Proxy: Before accessing {methodName}")
  
  if not proxy.events.isNil:
    proxy.events.publish(newEvent(&"proxy.access.{methodName}", %*{
      "proxyKind": $proxy.kind,
      "targetType": $T
    }))
  
  if not proxy.monitor.isNil:
    proxy.monitor.recordEvent(&"proxy.access.{methodName}")
  
  # Access control for protection proxy
  if proxy.kind == pkProtection and not proxy.accessChecker.isNil:
    let allowed = proxy.accessChecker()
    
    if not allowed and not proxy.logger.isNil:
      proxy.logger.warn(&"Access denied to {methodName}")
    
    return allowed
  
  true

proc afterAccess*[T](proxy: Proxy[T], methodName: string, 
                    success: bool, error: string = "") =
  ## Called after method access
  if not proxy.logger.isNil:
    if success:
      proxy.logger.debug(&"Proxy: After accessing {methodName}")
    else:
      proxy.logger.error(&"Proxy: Error accessing {methodName}: {error}")
  
  if not proxy.events.isNil:
    proxy.events.publish(newEvent(
      if success: &"proxy.success.{methodName}" else: &"proxy.error.{methodName}", 
      %*{
        "proxyKind": $proxy.kind,
        "targetType": $T,
        "success": success,
        "error": error
      }
    ))
  
  if not proxy.monitor.isNil:
    proxy.monitor.recordEvent(
      if success: &"proxy.success.{methodName}" else: &"proxy.error.{methodName}"
    )
    
    if success:
      proxy.monitor.gauge("proxy.success.rate", 1.0)
    else:
      proxy.monitor.gauge("proxy.error.rate", 1.0)

# Factory
proc newProxyFactory*[T](): ProxyFactory[T] =
  ## Create a proxy factory
  ProxyFactory[T](templates: initTable[string, proc(subject: T): Proxy[T]]())

proc register*[T](factory: ProxyFactory[T], 
                 name: string, 
                 creator: proc(subject: T): Proxy[T]) =
  ## Register a proxy template
  factory.templates[name] = creator

proc create*[T](factory: ProxyFactory[T], 
               name: string, 
               subject: T): Result[Proxy[T], PatternError] =
  ## Create a proxy from template
  if name notin factory.templates:
    return Result[Proxy[T], PatternError].err(
      newPatternError("ProxyFactory", &"Template '{name}' not found")
    )
  
  try:
    let proxy = factory.templates[name](subject)
    Result[Proxy[T], PatternError].ok(proxy)
    
  except CatchableError as e:
    Result[Proxy[T], PatternError].err(
      newPatternError("ProxyFactory", &"Failed to create proxy: {e.msg}")
    )

# Proxy types
proc loggingProxy*[T](subject: T, logger: Logger): Proxy[T] =
  ## Create a logging proxy
  result = newProxy[T](subject, pkLogging)
    .withLogging(logger)

proc remoteProxy*[T](subject: T, 
                    events: EventBus,
                    monitor: MonitoringSystem): Proxy[T] =
  ## Create a remote proxy
  result = newProxy[T](subject, pkRemote)
    .withEvents(events)
    .withMonitoring(monitor)

proc protectionProxy*[T](subject: T, 
                        accessChecker: proc(): bool): Proxy[T] =
  ## Create a protection proxy
  result = newProxy[T](subject, pkProtection)
    .setAccessChecker(accessChecker)

proc cachingProxy*[T](subject: T, monitor: MonitoringSystem): Proxy[T] =
  ## Create a caching proxy
  result = newProxy[T](subject, pkCaching)
    .withMonitoring(monitor)

# Method invocation
template invokeMethod*[T, R](proxy: Proxy[T], methodName: string, body: untyped): R =
  ## Safely invoke method through proxy
  if not proxy.beforeAccess(methodName):
    # Access denied
    proxy.afterAccess(methodName, false, "Access denied")
    raise newException(AccessDeniedError, &"Access to {methodName} denied")
  
  try:
    let result = body
    proxy.afterAccess(methodName, true)
    result
    
  except CatchableError as e:
    proxy.afterAccess(methodName, false, e.msg)
    raise

# Macros for proxy generation
macro createProxy*(subject: typed, body: untyped): untyped =
  ## Create a proxy with custom method interception
  let proxyType = ident($subject.getTypeInst() & "Proxy")
  let subjectType = subject.getTypeInst()
  
  result = quote do:
    type `proxyType` = ref object of `subjectType`
      subject: `subjectType`
    
    # Create instance
    let proxy = `proxyType`(subject: `subject`)
    
    # Add interception methods
    `body`
    
    proxy

# Dynamic proxy with method_missing
type
  DynamicProxy*[T] = ref object of Proxy[T]
    ## Dynamic proxy with method_missing support
    methodMissing: proc(name: string, args: varargs[any]): auto

proc newDynamicProxy*[T](subject: T): DynamicProxy[T] =
  ## Create a dynamic proxy
  DynamicProxy[T](
    name: &"DynamicProxy_{$T}",
    kind: pkStructural,
    description: &"Dynamic proxy for {$T}",
    subject: subject,
    kind: pkRemote
  )

proc setMethodMissing*[T](proxy: DynamicProxy[T], 
                        handler: proc(name: string, args: varargs[any]): auto): DynamicProxy[T] =
  ## Set method_missing handler
  proxy.methodMissing = handler
  proxy

proc methodMissing*[T](proxy: DynamicProxy[T], 
                      name: string, 
                      args: varargs[any]): auto =
  ## Handle undefined methods
  if proxy.beforeAccess(name):
    try:
      let result = proxy.methodMissing(name, args)
      proxy.afterAccess(name, true)
      result
    except CatchableError as e:
      proxy.afterAccess(name, false, e.msg)
      raise
  else:
    proxy.afterAccess(name, false, "Access denied")
    raise newException(AccessDeniedError, &"Access to {name} denied")