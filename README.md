# nim-design-patterns

A comprehensive collection of design patterns implemented in Nim, with seamless integration with nim-core and nim-libaspects for cross-cutting concerns.

## Overview

This library provides idiomatic Nim implementations of common design patterns, categorized into:

- **Creational Patterns**: Object creation mechanisms
- **Structural Patterns**: Object composition and relationships
- **Behavioral Patterns**: Object collaboration and responsibilities
- **Modern Patterns**: Contemporary patterns for concurrent and distributed systems

## Features

- Clean, idiomatic Nim implementations
- Integration with nim-libaspects for logging, monitoring, and metrics
- Integration with nim-core for AST manipulation and code generation
- Automatic design pattern detection and application
- Compile-time pattern application via macros
- Runtime pattern adaptation
- Comprehensive test coverage and examples

## Installation

### Prerequisites

This library depends on two other libraries that need to be available:
- [nim-lang-core](https://github.com/jasagiri/nim-lang-core)
- [nim-libaspects](https://github.com/jasagiri/nim-libaspects)

### Setup Instructions

1. Clone the repository:
```bash
git clone https://github.com/jasagiri/nim-design-patterns.git
cd nim-design-patterns
```

2. Install dependencies:
```bash
# Install Mercurial if not already installed (required by some Nimble packages)
# On macOS: brew install mercurial
# On Ubuntu: sudo apt-get install mercurial

# Install Nim dependencies
nimble install -d
```

3. Create symbolic links for local dependencies (if needed):
```bash
# The project expects these libraries to be available at ../nim-libaspects and ../nim-lang-core
# If they were installed via nimble, create symbolic links:
ln -s ~/.nimble/pkgcache/githubcom_jasagirinimlibaspects_* ../nim-libaspects
ln -s ~/.nimble/pkgcache/githubcom_jasagirinimlangcoregit_* ../nim-lang-core
```

4. Run tests to verify installation:
```bash
nimble test
```

### Alternative Installation

If you encounter issues with the automatic installation, you can manually clone the dependencies:

```bash
cd ..  # Go to parent directory of nim-design-patterns
git clone https://github.com/jasagiri/nim-lang-core.git
git clone https://github.com/jasagiri/nim-libaspects.git
cd nim-design-patterns
nimble test
```

## Classic Design Patterns

### Creational Patterns

#### Factory Pattern
```nim
import nim_design_patterns/creational/factory
import nim_libaspects/logging

type
  Product = ref object of RootObj
    name: string
  
  ConcreteProductA = ref object of Product
  ConcreteProductB = ref object of Product

# Create factory with logging
let factory = newFactory[Product]()
  .withLogging(newLogger("ProductFactory"))
  .register("A", proc(): Product = ConcreteProductA(name: "Product A"))
  .register("B", proc(): Product = ConcreteProductB(name: "Product B"))

let product = factory.create("A")
```

#### Builder Pattern
```nim
import nim_design_patterns/creational/builder
import nim_libaspects/validation

type
  Config = object
    host: string
    port: int
    debug: bool

# Create builder with validation
let builder = newBuilder[Config]()
  .withValidation()
  .field("host", "localhost")
  .field("port", 8080)
  .field("debug", false)
  .validate()

let config = builder.build()
```

#### Singleton Pattern
```nim
import nim_design_patterns/creational/singleton
import nim_libaspects/monitoring

type
  Database = ref object
    connection: string

# Thread-safe singleton with monitoring
let db = singleton(Database):
  proc(): Database =
    result = Database(connection: "connected")
    monitor("database.instances", 1)
```

### Structural Patterns

#### Adapter Pattern
```nim
import nim_design_patterns/structural/adapter
import nim_libaspects/transport

type
  OldApi = object
  NewApi = object

# Adapt old API to new interface
let adapter = adapt[OldApi, NewApi](oldApi):
  proc(old: OldApi): NewApi =
    # Adaptation logic
    NewApi()
```

#### Decorator Pattern
```nim
import nim_design_patterns/structural/decorator
import nim_libaspects/metrics

type
  Component = ref object of RootObj
    method operation(): string {.base.}

# Add metrics to existing component
let decorated = decorate(component):
  proc(self: Component): string =
    let start = now()
    result = self.operation()
    recordMetric("operation.duration", now() - start)
```

#### Proxy Pattern
```nim
import nim_design_patterns/structural/proxy
import nim_libaspects/logging

type
  Service = ref object of RootObj
    method execute(cmd: string): string {.base.}

# Create logging proxy
let proxy = createProxy(service):
  proc(self: Service, cmd: string): string =
    info("Executing command", %*{"cmd": cmd})
    result = self.execute(cmd)
    info("Command completed", %*{"result": result})
```

### Behavioral Patterns

#### Observer Pattern
```nim
import nim_design_patterns/behavioral/observer
import nim_libaspects/events

type
  Subject = ref object
    observers: seq[Observer]
    state: int

# Use with event bus
let subject = newSubject()
  .withEventBus(globalEventBus)
  .attach(observer1)
  .attach(observer2)

subject.setState(42)  # Notifies all observers
```

#### Strategy Pattern
```nim
import nim_design_patterns/behavioral/strategy
import nim_libaspects/config

type
  Algorithm = proc(data: seq[int]): seq[int]

# Configure strategy from config
let config = getConfig()
let strategy = newContext[Algorithm]()
  .fromConfig(config, "algorithm")
  .execute(@[3, 1, 4, 1, 5])
```

#### Command Pattern
```nim
import nim_design_patterns/behavioral/command
import nim_libaspects/logging

type
  Command = ref object of RootObj
    method execute() {.base.}
    method undo() {.base.}

# Command with logging and undo
let invoker = newInvoker()
  .withLogging()
  .withUndo()
  .execute(command1)
  .execute(command2)
  .undo()  # Undoes command2
```

### Functional Patterns

#### Lens Pattern
```nim
import nim_design_patterns/functional/lens
import options

# Define some example data types
type
  Address = object
    street: string
    city: string
    zipCode: string
    
  Person = object
    name: string
    age: int
    address: Address

# Create lenses for Person fields
let nameLens = field[Person, string](
  "name", 
  (p: Person) => p.name,
  (p: Person, name: string) => Person(name: name, age: p.age, address: p.address)
)

let addressLens = field[Person, Address](
  "address",
  (p: Person) => p.address,
  (p: Person, addr: Address) => Person(name: p.name, age: p.age, address: addr)
)

# Create lens for nested field
let streetLens = field[Address, string](
  "street",
  (a: Address) => a.street,
  (a: Address, s: string) => Address(street: s, city: a.city, zipCode: a.zipCode)
)

# Compose lenses for deep access
let personStreetLens = compose(addressLens, streetLens)

# Use lenses to read and update data immutably
let person = Person(
  name: "John", 
  age: 30, 
  address: Address(street: "123 Main St", city: "Anytown", zipCode: "12345")
)

# Get values
echo nameLens.get(person)  # "John"
echo personStreetLens.get(person)  # "123 Main St"

# Create new immutable copy with updates
let updatedPerson = person
  .modify(nameLens, proc(n: string): string = n & " Doe")
  .modify(personStreetLens, proc(s: string): string = "456 " & s)

echo updatedPerson.name  # "John Doe"
echo updatedPerson.address.street  # "456 123 Main St"
# Original person remains unchanged
```

The Lens pattern provides composable getters and setters for working with immutable data structures. It makes it easy to read and modify deeply nested data without mutation and without writing verbose copying code.

## Modern Design Patterns

### Executor Pattern
```nim
import nim_design_patterns/modern/executor
import nim_libaspects/logging

# Create executor with multiple workers
let executor = newExecutor[string]()
  .withLogging(newLogger("TaskExecutor"))
  .withMetrics(newMetricsCollector())

# Add tasks
let task1 = newSimpleTask[string](
  proc(): Result[string, ref CatchableError] = 
    Result[string, ref CatchableError].ok("Task 1 result")
)

let task2 = newSimpleTask[string](
  proc(): Result[string, ref CatchableError] = 
    Result[string, ref CatchableError].ok("Task 2 result")
)

# Submit tasks with dependencies
discard executor.submit(task1)
task2.addDependency(task1.id)
discard executor.submit(task2)

# Start executor
discard executor.start()

# Get task result when completed
if task2.isComplete():
  echo executor.getTaskResult(task2.id).get()
```

### State Machine Pattern
```nim
import nim_design_patterns/modern/statemachine
import nim_libaspects/events

# Create state machine with builder
let machine = newStateMachineBuilder[void]("TrafficLight")
  .withInitialState("Red")
  .withEntryAction(proc() = echo "Red light on")
  .withState("Yellow")
  .withEntryAction(proc() = echo "Yellow light on")
  .withState("Green")
  .withEntryAction(proc() = echo "Green light on")
  .withTransition("Red", "Green", "timer")
  .withTransition("Green", "Yellow", "timer")
  .withTransition("Yellow", "Red", "timer")
  .withEventBus(newEventBus())
  .build()

discard machine.start()
machine.fireEvent(EventId("timer"))  # Red -> Green
machine.fireEvent(EventId("timer"))  # Green -> Yellow
machine.fireEvent(EventId("timer"))  # Yellow -> Red
```

### Dependency Injection Pattern
```nim
import nim_design_patterns/modern/dependency_injection
import nim_libaspects/logging

type
  UserService = ref object
    logger: Logger
  
  UserController = ref object
    userService: UserService

# Create DI container
let container = newContainer()
  .withLogging(newLogger("DIContainer"))

# Register services
container.registerSingleton(
  proc(): Logger = newLogger("AppLogger")
)

container.register(
  proc(): UserService = 
    UserService(logger: container.resolve[Logger]())
)

container.register(
  proc(): UserController = 
    UserController(userService: container.resolve[UserService]())
)

# Resolve controller with all dependencies
let controller = container.resolve[UserController]()
```

### CQRS Pattern
```nim
import nim_design_patterns/modern/cqrs
import nim_libaspects/events

# Define command and query
type
  CreateUserCommand = ref object of Command
    username: string
    email: string
  
  GetUserQuery = ref object of Query[UserDto]
    userId: string
  
  UserDto = ref object
    id: string
    username: string
    email: string

# Create CQRS framework
let framework = newCqrsFramework()
  .withLogging(newLogger("CQRS"))
  .withEventBus(newEventBus())

# Register command handler
framework.commandDispatcher.registerHandler(
  proc(cmd: CreateUserCommand): Result[string, ref AppError] =
    # Create user logic
    Result[string, ref AppError].ok("user123")
)

# Register query handler
framework.queryDispatcher.registerHandler(
  proc(query: GetUserQuery): Result[UserDto, ref AppError] =
    # Get user logic
    Result[UserDto, ref AppError].ok(
      UserDto(id: query.userId, username: "john", email: "john@example.com")
    )
)

# Send command and query
let createCmd = CreateUserCommand(username: "john", email: "john@example.com")
let userId = framework.sendCommand[CreateUserCommand, string](createCmd).get()

let query = GetUserQuery(userId: userId)
let user = framework.executeQuery[GetUserQuery, UserDto](query).get()
```

## Design Pattern Analysis and Application

### Pattern Detection

```nim
import nim_design_patterns/analysis/pattern_detector
import nim_core/[ast_analyzer, type_analyzer, symbol_index]

# Create detector
let analyzer = newAstAnalyzer()
let typeAnalyzer = newTypeAnalyzer()
let symbolIndex = newSymbolIndex()

let detector = newPatternDetector(analyzer, typeAnalyzer, symbolIndex)
  .withLogging(newLogger("PatternDetector"))

# Detect patterns in file
let patterns = detector.detectPatternsInFile("path/to/file.nim")
for pattern in patterns:
  echo pattern.patternName, " detected with ", pattern.confidence, " confidence"

# Analyze entire project
let stats = detector.analyzeProject("path/to/project")
echo "Most used patterns: ", stats.getTopPatterns()
```

### Pattern Application

```nim
import nim_design_patterns/analysis/pattern_detector

# Create transformer
let transformer = newPatternTransformer(detector)
  .withLogging(newLogger("PatternTransformer"))

# Apply pattern to file
discard transformer.applyPatternToFile(
  "path/to/file.nim", 
  "Singleton",
  "path/to/output.nim"
)
```

## Integration Examples

### With nim-core

```nim
import nim_design_patterns/integration/ast_patterns
import nim_core/ast_analyzer

# Apply patterns to AST nodes
let analyzer = newAstAnalyzer()
let patterns = findPatterns(analyzer, sourceFile)

for pattern in patterns:
  case pattern.kind:
  of pkSingleton:
    applySingletonPattern(pattern.node)
  of pkFactory:
    applyFactoryPattern(pattern.node)
  else:
    discard
```

### With nim-libaspects

```nim
import nim_design_patterns/integration/aspects
import nim_libaspects/monitoring
import nim_libaspects/logging

# Combine patterns with cross-cutting concerns
let factory = newFactory[Service]()
  .withLogging(getLogger("ServiceFactory"))
  .withMonitoring("service.creation")
  .withMetrics("factory.performance")
  .register("api", createApiService)
  .register("db", createDbService)

let service = factory.create("api")
```

## Architecture

```
nim-design-patterns/
├── src/nim_design_patterns/
│   ├── core/              # Core abstractions and utilities
│   ├── creational/        # Factory, Builder, Singleton, etc.
│   ├── structural/        # Adapter, Decorator, Proxy, etc.  
│   ├── behavioral/        # Observer, Strategy, Command, etc.
│   ├── modern/            # Executor, StateMachine, DI, CQRS
│   ├── analysis/          # Pattern detection and application
│   └── integration/       # Integration with other libraries
├── tests/                 # Comprehensive test suite
└── examples/              # Usage examples
```

## Documentation

See the [docs](docs/) directory for detailed documentation on:

- [Pattern Detection Theory](docs/pattern_detection_theory.md)
- [Pattern Application Techniques](docs/pattern_application.md)
- [Modern Pattern Usage](docs/modern_patterns.md)

## Testing

```bash
# Run all tests
nimble test

# Run specific pattern category tests
nimble test_creational
nimble test_structural
nimble test_behavioral
nimble test_modern

# Run specific pattern tests
nim c -r tests/test_factory.nim
nim c -r tests/test_observer.nim
nim c -r tests/test_executor.nim
```

## Dependencies

- nim >= 2.0.0
- [nim-lang-core](https://github.com/jasagiri/nim-lang-core) (for AST manipulation)
- [nim-libaspects](https://github.com/jasagiri/nim-libaspects) (for cross-cutting concerns)
- results >= 0.5.0 (for error handling)
- chronicles >= 0.10.0 (for structured logging)

## Contributing

Contributions are welcome! Please ensure:
- Pattern implementations follow standard principles
- Integration with nim-libaspects is maintained
- Comprehensive tests are included
- Examples demonstrate real-world usage

## License

MIT

## See Also

- [Design Patterns: Elements of Reusable Object-Oriented Software](https://en.wikipedia.org/wiki/Design_Patterns)
- [nim-core](../nim-core/README.md)
- [nim-libaspects](../nim-libaspects/README.md)