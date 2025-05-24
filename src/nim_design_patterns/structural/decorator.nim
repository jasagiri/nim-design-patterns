## Decorator Pattern implementation

import std/[macros, tables, strformat]
import results
import nim_libaspects/[logging, metrics]
import ../core/base

type
  Decorator*[T] = ref object of Pattern
    ## Generic decorator pattern
    component: T
    operation: proc(self: T): auto
    logger: Logger
    metrics: MetricsRegistry
  
  DecoratorStack*[T] = ref object of Pattern
    ## Stack of decorators to apply in sequence
    decorators: seq[Decorator[T]]

# Single decorator
proc newDecorator*[T](component: T, operation: proc(self: T): auto): Decorator[T] =
  ## Create a new decorator
  result = Decorator[T](
    name: &"Decorator_{$T}",
    kind: pkStructural,
    description: &"Decorator for {$T}",
    component: component,
    operation: operation
  )

proc withLogging*[T](decorator: Decorator[T], logger: Logger): Decorator[T] =
  ## Add logging to decorator
  decorator.logger = logger
  decorator

proc withMetrics*[T](decorator: Decorator[T], 
                    metrics: MetricsRegistry): Decorator[T] =
  ## Add metrics collection to decorator
  decorator.metrics = metrics
  decorator

proc execute*[T](decorator: Decorator[T]): auto =
  ## Execute the decorated operation
  if not decorator.logger.isNil:
    decorator.logger.debug(&"Executing decorator for {$T}")
  
  let startTime = now()
  
  try:
    let result = decorator.operation(decorator.component)
    
    if not decorator.metrics.isNil:
      decorator.metrics.recordTime("decorator.execution", now() - startTime)
      decorator.metrics.increment("decorator.calls")
    
    if not decorator.logger.isNil:
      decorator.logger.info(&"Decorator execution successful")
    
    result
    
  except CatchableError as e:
    if not decorator.metrics.isNil:
      decorator.metrics.increment("decorator.errors")
    
    if not decorator.logger.isNil:
      decorator.logger.error(&"Decorator execution failed: {e.msg}")
    
    raise

# Decorator stack
proc newDecoratorStack*[T](): DecoratorStack[T] =
  ## Create a new decorator stack
  result = DecoratorStack[T](
    name: &"DecoratorStack_{$T}",
    kind: pkStructural,
    description: &"Stack of decorators for {$T}",
    decorators: @[]
  )

proc add*[T](stack: DecoratorStack[T], 
            component: T,
            operation: proc(self: T): auto): DecoratorStack[T] =
  ## Add decorator to stack
  stack.decorators.add(newDecorator(component, operation))
  stack

proc execute*[T](stack: DecoratorStack[T], component: T): auto =
  ## Execute all decorators in the stack
  var current = component
  
  # Execute decorators in sequence
  for decorator in stack.decorators:
    decorator.component = current
    current = decorator.execute()
  
  current

# Convenient template for decoration
template decorate*[T](component: T, body: untyped): auto =
  ## Apply decorator inline
  block:
    let decorator = newDecorator(component, proc(self: T): auto = body)
    decorator.execute()

# Typed decorator with static dispatch
macro createTypedDecorator*(name: untyped, baseType: typedesc, body: untyped): untyped =
  ## Create a statically typed decorator 
  let decoratorName = ident(name.strVal & "Decorator")
  
  result = quote do:
    type
      `decoratorName`* = ref object of `baseType`
        component: `baseType`
    
    # Constructor
    proc `newDecoratorName`*(component: `baseType`): `decoratorName` =
      `decoratorName`(component: component)
    
    # Forward declarations
    `body`

# Common decorator presets
proc loggingDecorator*[T](component: T, logger: Logger): Decorator[T] =
  ## Create a logging decorator
  result = newDecorator[T](component, proc(self: T): auto =
    logger.info("Before method execution")
    let result = procCall self
    logger.info("After method execution")
    result
  )

proc timingDecorator*[T](component: T, metrics: MetricsRegistry): Decorator[T] =
  ## Create a timing decorator
  result = newDecorator[T](component, proc(self: T): auto =
    let startTime = now()
    let result = procCall self
    metrics.recordTime("execution.time", now() - startTime)
    result
  )

proc cachingDecorator*[T, R](component: T, 
                           method: proc(self: T): R): Decorator[T] =
  ## Create a caching decorator
  var cache: Option[R]
  
  result = newDecorator[T](component, proc(self: T): R =
    if cache.isSome:
      return cache.get()
    
    let result = method(self)
    cache = some(result)
    result
  )

proc retryDecorator*[T, R](component: T, 
                         method: proc(self: T): R,
                         maxRetries = 3): Decorator[T] =
  ## Create a retry decorator
  result = newDecorator[T](component, proc(self: T): R =
    var tries = 0
    while tries < maxRetries:
      try:
        return method(self)
      except CatchableError:
        tries += 1
        if tries >= maxRetries:
          raise
        sleep(100 * tries)  # Exponential backoff
  )