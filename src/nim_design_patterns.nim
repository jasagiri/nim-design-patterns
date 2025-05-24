## Main module for nim-design-patterns library

import nim_design_patterns/core/[base, registry, utils]
import nim_design_patterns/creational/[factory, builder, singleton]
import nim_design_patterns/structural/[adapter, decorator, proxy]
import nim_design_patterns/behavioral/[observer, strategy, command]
import nim_design_patterns/integration/[nim_core_integration, nim_libs_integration]

export base, registry, utils
export factory, builder, singleton
export adapter, decorator, proxy
export observer, strategy, command
export nim_core_integration, nim_libs_integration

proc version*(): string =
  ## Returns the version of nim-design-patterns
  "0.1.0"

proc info*(): string =
  ## Returns information about the library
  """nim-design-patterns v""" & version() & """
  
A comprehensive design patterns library for Nim with seamless integration
for cross-cutting concerns via nim-aspect-libs and AST manipulation via nim-lang-core.

Supported patterns:
- Creational: Factory, Builder, Singleton
- Structural: Adapter, Decorator, Proxy  
- Behavioral: Observer, Strategy, Command
"""

when isMainModule:
  echo info()