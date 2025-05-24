## Modern Dependency Injection Pattern implementation
##
## This implementation provides a flexible dependency injection system with:
## - Constructor, method, and property injection
## - Scope management (singleton, transient, request)
## - Auto-wiring of dependencies
## - Lifecycle management (initialization, disposal)
## - Lazy loading support
## - Configuration-based registration

import std/[tables, sets, options, strformat, typetraits, macros, genasts]
import nim_libaspects/[logging, errors]
import ../core/base

type
  ServiceKey* = object
    ## Identifier for a service
    name*: string
    typeId*: string  # Runtime type identification
  
  Lifecycle* = enum
    ## Service lifecycle options
    lcSingleton    # Single instance for entire container lifetime
    lcTransient    # New instance created on each resolution
    lcScoped       # Single instance per scope
    lcExternallyOwned  # Instance managed externally
  
  ServiceDescriptor*[T] = ref object
    ## Describes how to create and manage a service
    key*: ServiceKey
    factory*: proc(): T
    instance*: Option[T]
    lifecycle*: Lifecycle
    dependencies*: seq[ServiceKey]
    initializeMethod*: Option[proc(instance: T)]
    disposeMethod*: Option[proc(instance: T)]
    isLazy*: bool
  
  Container* = ref object of Pattern
    ## Dependency injection container
    services*: Table[ServiceKey, RootRef]
    scopes*: seq[Container]
    parent*: Container
    logger*: Logger
    isDisposed*: bool
  
  Scope* = ref object of Container
    ## Scoped container for request/session-based services
  
  ServiceRegistration*[T] = ref object
    ## Fluent API for service registration
    container*: Container
    descriptor*: ServiceDescriptor[T]
  
  DependencyResolutionError* = object of CatchableError
  
  ContainerDisposedError* = object of CatchableError
  
  CircularDependencyError* = object of CatchableError

# ServiceKey implementation
proc `$`*(key: ServiceKey): string =
  if key.name.len > 0:
    &"{key.name} ({key.typeId})"
  else:
    key.typeId

proc `==`*(a, b: ServiceKey): bool =
  # Compare by name if both have names, otherwise by type
  if a.name.len > 0 and b.name.len > 0:
    a.name == b.name
  else:
    a.typeId == b.typeId

proc hash*(key: ServiceKey): Hash =
  # Hash by name if available, otherwise by type
  if key.name.len > 0:
    hash(key.name)
  else:
    hash(key.typeId)

proc createServiceKey*(T: typedesc, name = ""): ServiceKey =
  ## Create a service key from type and optional name
  ServiceKey(
    name: name,
    typeId: $T
  )

# ServiceDescriptor implementation
proc newServiceDescriptor*[T](factory: proc(): T,
                            lifecycle = lcTransient,
                            name = ""): ServiceDescriptor[T] =
  ## Create service descriptor
  result = ServiceDescriptor[T](
    key: createServiceKey(T, name),
    factory: factory,
    lifecycle: lifecycle,
    dependencies: @[]
  )

proc getInstance*[T](descriptor: ServiceDescriptor[T], 
                    container: Container): T =
  ## Get or create instance from descriptor
  case descriptor.lifecycle:
  of lcSingleton, lcScoped:
    # For singleton/scoped, check if instance exists
    if descriptor.instance.isSome:
      return descriptor.instance.get()
    
    # Create and store instance
    let instance = descriptor.factory()
    
    # Initialize if needed
    if descriptor.initializeMethod.isSome:
      descriptor.initializeMethod.get()(instance)
    
    descriptor.instance = some(instance)
    return instance
    
  of lcTransient:
    # Always create new instance
    let instance = descriptor.factory()
    
    # Initialize if needed
    if descriptor.initializeMethod.isSome:
      descriptor.initializeMethod.get()(instance)
    
    return instance
    
  of lcExternallyOwned:
    # Must have an instance already
    if descriptor.instance.isNone:
      raise newException(DependencyResolutionError,
        &"Externally owned service {descriptor.key} has no instance")
    
    return descriptor.instance.get()

proc withDependencies*[T](descriptor: ServiceDescriptor[T], 
                         dependencies: varargs[ServiceKey]): ServiceDescriptor[T] =
  ## Add dependencies to descriptor
  for dep in dependencies:
    descriptor.dependencies.add(dep)
  
  descriptor

proc withInitialize*[T](descriptor: ServiceDescriptor[T], 
                       initialize: proc(instance: T)): ServiceDescriptor[T] =
  ## Add initialization method
  descriptor.initializeMethod = some(initialize)
  descriptor

proc withDispose*[T](descriptor: ServiceDescriptor[T], 
                    dispose: proc(instance: T)): ServiceDescriptor[T] =
  ## Add disposal method
  descriptor.disposeMethod = some(dispose)
  descriptor

proc asLazy*[T](descriptor: ServiceDescriptor[T]): ServiceDescriptor[T] =
  ## Mark as lazy loaded
  descriptor.isLazy = true
  descriptor

# Container implementation
proc newContainer*(name = "DIContainer"): Container =
  ## Create a new DI container
  result = Container(
    name: name,
    kind: pkCreational,
    description: "Dependency Injection Container",
    services: initTable[ServiceKey, RootRef](),
    scopes: @[]
  )

proc withLogging*(container: Container, logger: Logger): Container =
  ## Add logging to container
  container.logger = logger
  container

proc createScope*(container: Container, name = ""): Scope =
  ## Create a new scope from container
  result = Scope(
    name: if name.len > 0: name else: &"{container.name}_Scope",
    kind: pkCreational,
    description: "Dependency Injection Scope",
    services: initTable[ServiceKey, RootRef](),
    parent: container
  )
  
  if not container.logger.isNil:
    result.logger = container.logger
  
  container.scopes.add(result)

proc register*[T](container: Container, 
                 factory: proc(): T,
                 lifecycle = lcTransient,
                 name = ""): ServiceRegistration[T] =
  ## Register a service
  if container.isDisposed:
    raise newException(ContainerDisposedError, "Container is disposed")
  
  let descriptor = newServiceDescriptor[T](factory, lifecycle, name)
  
  # Store descriptor
  let regRef = RootRef(descriptor)
  container.services[descriptor.key] = regRef
  
  if not container.logger.isNil:
    container.logger.debug(&"Registered service {descriptor.key} with lifecycle {lifecycle}")
  
  # Return fluent interface
  result = ServiceRegistration[T](
    container: container,
    descriptor: descriptor
  )

proc registerInstance*[T](container: Container, 
                         instance: T,
                         name = ""): ServiceRegistration[T] =
  ## Register an existing instance
  if container.isDisposed:
    raise newException(ContainerDisposedError, "Container is disposed")
  
  let descriptor = newServiceDescriptor[T](
    proc(): T = instance,
    lcExternallyOwned,
    name
  )
  
  descriptor.instance = some(instance)
  
  # Store descriptor
  let regRef = RootRef(descriptor)
  container.services[descriptor.key] = regRef
  
  if not container.logger.isNil:
    container.logger.debug(&"Registered instance {descriptor.key} with lifecycle lcExternallyOwned")
  
  # Return fluent interface
  result = ServiceRegistration[T](
    container: container,
    descriptor: descriptor
  )

proc registerSingleton*[T](container: Container, 
                          factory: proc(): T,
                          name = ""): ServiceRegistration[T] =
  ## Register a singleton service
  container.register[T](factory, lcSingleton, name)

proc registerScoped*[T](container: Container, 
                       factory: proc(): T,
                       name = ""): ServiceRegistration[T] =
  ## Register a scoped service
  container.register[T](factory, lcScoped, name)

proc resolve*[T](container: Container, name = ""): T =
  ## Resolve a service from container
  if container.isDisposed:
    raise newException(ContainerDisposedError, "Container is disposed")
  
  # Create key for lookup
  let key = createServiceKey(T, name)
  
  # Check current container
  if key in container.services:
    let descriptorRef = container.services[key]
    let descriptor = cast[ServiceDescriptor[T]](descriptorRef)
    
    if not container.logger.isNil:
      container.logger.debug(&"Resolving service {key} from container {container.name}")
    
    return descriptor.getInstance(container)
  
  # Check parent if exists
  if container.parent != nil:
    try:
      return container.parent.resolve[T](name)
    except DependencyResolutionError:
      # Continue to error case
      discard
  
  # Not found
  raise newException(DependencyResolutionError, 
    &"Could not resolve service {key} from container {container.name}")

proc tryResolve*[T](container: Container, name = ""): Option[T] =
  ## Try to resolve a service, returning none if not found
  try:
    some(container.resolve[T](name))
  except DependencyResolutionError:
    none(T)

proc resolveAll*[T](container: Container): seq[T] =
  ## Resolve all services of a given type
  if container.isDisposed:
    raise newException(ContainerDisposedError, "Container is disposed")
  
  result = @[]
  
  # Get all matching services from current container
  for key, descriptorRef in container.services:
    if key.typeId == $T:
      let descriptor = cast[ServiceDescriptor[T]](descriptorRef)
      result.add(descriptor.getInstance(container))
  
  # Get from parent if exists
  if container.parent != nil:
    let parentResults = container.parent.resolveAll[T]()
    result.add(parentResults)

proc getRegistrationCount*(container: Container): int =
  ## Get number of registered services
  container.services.len

proc getRegistrationCount*[T](container: Container): int =
  ## Get number of registered services of a type
  var count = 0
  
  for key in container.services.keys:
    if key.typeId == $T:
      inc count
  
  count

proc isRegistered*[T](container: Container, name = ""): bool =
  ## Check if service is registered
  let key = createServiceKey(T, name)
  key in container.services

proc clear*(container: Container) =
  ## Clear all registrations
  # Dispose all resolvable services
  for key, descriptorRef in container.services:
    try:
      # Cast to base descriptor to check if has dispose method
      type GenericDescriptor = ref object
        disposeMethod: Option[proc(instance: RootRef)]
        instance: Option[RootRef]
      
      let descriptor = cast[GenericDescriptor](descriptorRef)
      
      # Call dispose if method exists and instance is created
      if descriptor.disposeMethod.isSome and descriptor.instance.isSome:
        descriptor.disposeMethod.get()(descriptor.instance.get())
    except:
      if not container.logger.isNil:
        container.logger.error(&"Error disposing service {key}")
  
  # Clear registrations
  container.services.clear()
  
  # Clear and dispose scopes
  for scope in container.scopes:
    scope.clear()
  
  container.scopes.setLen(0)

proc dispose*(container: Container) =
  ## Dispose container and all services
  if container.isDisposed:
    return
  
  container.clear()
  container.isDisposed = true

# Scope implementation
proc register*[T](scope: Scope, 
                 factory: proc(): T,
                 lifecycle = lcScoped,
                 name = ""): ServiceRegistration[T] =
  ## Register a scoped service
  if lifecycle != lcScoped and lifecycle != lcTransient:
    if not scope.logger.isNil:
      scope.logger.warn(&"Converting {lifecycle} to lcScoped in scope registration")
  
  # Always use scoped lifecycle in a scope
  Container(scope).register[T](factory, lcScoped, name)

proc dispose*(scope: Scope) =
  ## Dispose scope and all services
  if scope.isDisposed:
    return
  
  scope.clear()
  scope.isDisposed = true
  
  # Remove from parent's scopes list
  if scope.parent != nil:
    let idx = scope.parent.scopes.find(scope)
    if idx >= 0:
      scope.parent.scopes.delete(idx)

# ServiceRegistration fluent interface
proc withDependencies*[T](reg: ServiceRegistration[T], 
                         dependencies: varargs[typedesc]): ServiceRegistration[T] =
  ## Add dependencies to registration
  for dep in dependencies:
    reg.descriptor.dependencies.add(createServiceKey(dep))
  
  reg

proc withNamedDependencies*[T](reg: ServiceRegistration[T],
                              dependencies: varargs[tuple[typ: typedesc, name: string]]): ServiceRegistration[T] =
  ## Add named dependencies
  for dep in dependencies:
    reg.descriptor.dependencies.add(createServiceKey(dep.typ, dep.name))
  
  reg

proc withInitializer*[T](reg: ServiceRegistration[T],
                        initialize: proc(instance: T)): ServiceRegistration[T] =
  ## Add initializer
  reg.descriptor.withInitialize(initialize)
  reg

proc withDisposer*[T](reg: ServiceRegistration[T],
                     dispose: proc(instance: T)): ServiceRegistration[T] =
  ## Add disposer
  reg.descriptor.withDispose(dispose)
  reg

proc asLazy*[T](reg: ServiceRegistration[T]): ServiceRegistration[T] =
  ## Mark as lazy loaded
  reg.descriptor.asLazy()
  reg

# Circular dependency detection
proc detectCircularDependencies*(container: Container): bool =
  ## Detect circular dependencies in container
  var visited = initHashSet[ServiceKey]()
  var visiting = initHashSet[ServiceKey]()
  
  proc visit(key: ServiceKey): bool =
    if key in visiting:
      if not container.logger.isNil:
        container.logger.error(&"Circular dependency detected: {key}")
      return true
    
    if key in visited:
      return false
    
    visiting.incl(key)
    
    if key in container.services:
      let descriptorRef = container.services[key]
      
      # Get dependencies
      type GenericDescriptor = ref object
        dependencies: seq[ServiceKey]
      
      let descriptor = cast[GenericDescriptor](descriptorRef)
      
      for dep in descriptor.dependencies:
        if visit(dep):
          return true
    
    visiting.excl(key)
    visited.incl(key)
    
    false
  
  for key in container.services.keys:
    if visit(key):
      return true
  
  false

# Auto-registration helpers
proc registerImplementations*[T: RootRef](container: Container,
                                       factories: varargs[tuple[typ: typedesc, factory: proc(): RootRef]]) =
  ## Register all implementations of an interface
  for impl in factories:
    container.register(
      proc(): T = T(impl.factory()),
      lcTransient
    )

# Lazy loading implementation
type
  Lazy*[T] = ref object
    ## Lazy loading wrapper
    container: Container
    serviceName: string
    value: Option[T]
    isValueCreated: bool

proc newLazy*[T](container: Container, serviceName = ""): Lazy[T] =
  ## Create lazy loader for a service
  Lazy[T](
    container: container,
    serviceName: serviceName
  )

proc value*[T](lazy: Lazy[T]): T =
  ## Get or create value
  if lazy.isValueCreated:
    return lazy.value.get()
  
  let instance = lazy.container.resolve[T](lazy.serviceName)
  lazy.value = some(instance)
  lazy.isValueCreated = true
  
  instance

proc isValueCreated*[T](lazy: Lazy[T]): bool =
  ## Check if value is created
  lazy.isValueCreated

# Attribute-based injection with macros (simplified)
macro inject*(T: typedesc, field: untyped, serviceType: typedesc, name = ""): untyped =
  ## Inject dependency into field
  let fieldName = $field
  let serviceName = if name.kind == nnkNilLit: newStrLitNode("") else: name
  
  result = quote do:
    `field` = container.resolve[`serviceType`](`serviceName`)

macro injectLazy*(T: typedesc, field: untyped, serviceType: typedesc, name = ""): untyped =
  ## Inject lazy dependency
  let fieldName = $field
  let serviceName = if name.kind == nnkNilLit: newStrLitNode("") else: name
  
  result = quote do:
    `field` = newLazy[`serviceType`](container, `serviceName`)

# DSL for container configuration
template configure*(container: Container, body: untyped): untyped =
  ## Configure container with DSL
  body

template services*(body: untyped): untyped =
  ## Define services
  body

template transient*[T](name = ""): untyped =
  ## Register transient service
  container.register[T](proc(): T = new T(), lcTransient, name)

template singleton*[T](name = ""): untyped =
  ## Register singleton service
  container.register[T](proc(): T = new T(), lcSingleton, name)

template scoped*[T](name = ""): untyped =
  ## Register scoped service
  container.register[T](proc(): T = new T(), lcScoped, name)

# Convenience class-based container builder
type
  ContainerBuilder* = ref object
    ## Fluent container builder
    container: Container

proc newContainerBuilder*(): ContainerBuilder =
  ## Create container builder
  ContainerBuilder(
    container: newContainer()
  )

proc withSingleton*[T](builder: ContainerBuilder, 
                      factory: proc(): T = nil,
                      name = ""): ContainerBuilder =
  ## Add singleton service
  let actualFactory = if factory.isNil: proc(): T = new T() else: factory
  discard builder.container.registerSingleton(actualFactory, name)
  builder

proc withTransient*[T](builder: ContainerBuilder, 
                      factory: proc(): T = nil,
                      name = ""): ContainerBuilder =
  ## Add transient service
  let actualFactory = if factory.isNil: proc(): T = new T() else: factory
  discard builder.container.register(actualFactory, lcTransient, name)
  builder

proc withScoped*[T](builder: ContainerBuilder, 
                   factory: proc(): T = nil,
                   name = ""): ContainerBuilder =
  ## Add scoped service
  let actualFactory = if factory.isNil: proc(): T = new T() else: factory
  discard builder.container.register(actualFactory, lcScoped, name)
  builder

proc withInstance*[T](builder: ContainerBuilder, 
                     instance: T,
                     name = ""): ContainerBuilder =
  ## Add instance
  discard builder.container.registerInstance(instance, name)
  builder

proc withLogging*(builder: ContainerBuilder, 
                 logger: Logger): ContainerBuilder =
  ## Add logging
  builder.container.withLogging(logger)
  builder

proc build*(builder: ContainerBuilder): Container =
  ## Build configured container
  builder.container