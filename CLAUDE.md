# nim-design-patterns Guide

This file provides guidance to Claude Code (claude.ai/code) when working with `nim-design-patterns`.

## Repository Overview

`nim-design-patterns` is a comprehensive library of design patterns implemented in Nim, with seamless integration with:

1. **nim-libaspects**: For cross-cutting concerns (logging, metrics, monitoring, etc.)  
   Path: `../nim-libaspects`
2. **nim-core**: For AST manipulation and code generation capabilities  
   Path: `../nim-core`

The library is organized by pattern categories:

- **Creational Patterns**: Object creation mechanisms
- **Structural Patterns**: Object composition and relationships
- **Behavioral Patterns**: Object collaboration and responsibilities

## Project Structure

```
nim-design-patterns/
├── src/nim_design_patterns/
│   ├── core/              # Core abstractions and utilities
│   │   ├── base.nim       # Base types and interfaces
│   │   └── registry.nim   # Pattern registry
│   ├── creational/        # Creational patterns
│   │   ├── factory.nim    # Factory pattern
│   │   ├── builder.nim    # Builder pattern
│   │   └── singleton.nim  # Singleton pattern
│   ├── structural/        # Structural patterns
│   │   ├── adapter.nim    # Adapter pattern
│   │   ├── decorator.nim  # Decorator pattern
│   │   └── proxy.nim      # Proxy pattern
│   ├── behavioral/        # Behavioral patterns
│   │   ├── observer.nim   # Observer pattern
│   │   ├── strategy.nim   # Strategy pattern
│   │   └── command.nim    # Command pattern
│   └── integration/       # Integration with other libraries
│       ├── nim_core_integration.nim
│       └── nim_libs_integration.nim
├── tests/                # Pattern tests
│   ├── test_all.nim      # Main test runner
│   ├── test_factory.nim  # Factory pattern tests
│   └── test_observer.nim # Observer pattern tests
└── examples/             # Usage examples
    └── integration_example.nim
```

## Pattern Usage Guidelines

### 1. Creational Patterns

#### Factory Pattern
- Use for dynamic object creation with proper type encapsulation
- Add logging/metrics with withLogging/withMetrics methods
- Create variations using Builder API for complex configuration

#### Builder Pattern
- Use for step-by-step construction of complex objects
- Add validation to enforce business rules
- Chain methods in fluent API style

#### Singleton Pattern
- Use thread-safe implementation for shared resources
- Consider alternatives (dependency injection) when appropriate
- Add monitoring via withMonitoring method

### 2. Structural Patterns

#### Adapter Pattern
- Use to convert interfaces between incompatible classes
- Create bidirectional adapters when needed
- Consider object vs class adaptation based on needs

#### Decorator Pattern
- Use to add behavior to objects at runtime
- Chain decorators for multiple behaviors
- Use provided presets for common behaviors (logging, timing, etc.)

#### Proxy Pattern
- Use for controlled access to objects
- Add logging/monitoring for observability
- Use different proxy types (remote, virtual, protection) as needed

### 3. Behavioral Patterns

#### Observer Pattern
- Use for publisher-subscriber scenarios
- Add event bus integration for distributed notification
- Consider filtered observers for targeted updates

#### Strategy Pattern
- Use to encapsulate algorithms
- Load strategies from configuration
- Add context with logging for transparent execution

#### Command Pattern
- Use for action encapsulation
- Add command history and undo capability
- Consider composite commands for transactions

## Integration Guidelines

### With nim-libaspects

Always integrate cross-cutting concerns via the nim_libs_integration module:

```nim
# Use the integration module
import nim_design_patterns/integration/nim_libs_integration

# Set up cross-cutting concerns
let logger = newLogger("Patterns")
let metrics = newMetricsCollector()
let monitor = newMonitoringSystem()

# Apply to patterns
let factory = newFactory[Product]()
  .withAspects(logger, monitor, metrics)

let builder = newBuilder[Config]()
  .withLogging(logger)
```

### With nim-core

Use AST analysis and manipulation via the nim_core_integration module:

```nim
import nim_design_patterns/integration/nim_core_integration

# Create analyzer components
let analyzer = newAstAnalyzer()
let typeAnalyzer = newTypeAnalyzer()
let symbolIndex = newSymbolIndex()

# Create pattern detector
let patternDetector = newPatternDetector(analyzer, typeAnalyzer, symbolIndex)

# Detect patterns in code
let patterns = patternDetector.detectPatterns(ast)
```

## Testing Guidelines

- Test each pattern in isolation
- Test integration with cross-cutting concerns
- Use the provided test utilities in tests/ directory
- Run all tests with `nimble test`

## Common Commands

### Building and Testing

```bash
# Build the library
nimble build

# Run tests
nimble test

# Run specific pattern tests
nimble test_creational
nimble test_structural
nimble test_behavioral

# Build examples
nimble examples
```

### Development Workflow

1. Add new patterns to appropriate category directory
2. Update main module exports
3. Add tests for new patterns
4. Update examples as needed
5. Document pattern usage

## Design Principles

When extending the library, follow these principles:

1. **Consistency**: Maintain consistent API across patterns
2. **Integration**: Ensure seamless integration with cross-cutting concerns
3. **Testability**: Write comprehensive tests for all patterns
4. **Documentation**: Document pattern usage with examples
5. **Idiomatic Nim**: Follow Nim idioms and conventions