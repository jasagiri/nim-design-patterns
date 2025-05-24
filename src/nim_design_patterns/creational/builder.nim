## Builder Pattern implementation with validation

import std/[macros, strformat, tables, options]
import results
import nim_libaspects/[logging, errors]
import ../core/base

type
  BuilderField = object
    name: string
    value: NimNode
    required: bool
    validator: proc(v: NimNode): bool
  
  Builder*[T] = ref object of Pattern
    ## Generic builder for constructing objects
    fields: Table[string, BuilderField]
    built: bool
    logger: Logger
    validators: seq[proc(builder: Builder[T]): Result[void, PatternError]]
  
  ValidationError* = ref object of PatternError
    field*: string
    value*: string

proc newBuilder*[T](name = "Builder"): Builder[T] =
  ## Create a new builder instance
  result = Builder[T](
    name: name,
    kind: pkCreational,
    description: "Builder pattern for step-by-step object construction",
    fields: initTable[string, BuilderField](),
    built: false,
    validators: @[]
  )

proc withLogging*(builder: Builder, logger: Logger): Builder =
  ## Add logging to builder
  builder.logger = logger
  builder

proc withValidation*(builder: Builder): Builder =
  ## Enable validation for the builder
  # Validation is always enabled, this is for API consistency
  builder

proc field*[T](builder: Builder[T], name: string, value: auto, 
               required = false): Builder[T] =
  ## Set a field value
  if builder.built:
    raise newException(PatternError, "Cannot modify built object")
  
  builder.fields[name] = BuilderField(
    name: name,
    value: newLit(value),
    required: required
  )
  
  if not builder.logger.isNil:
    builder.logger.debug(&"Set field '{name}' = {value}")
  
  builder

proc fieldWithValidator*[T](builder: Builder[T], name: string, value: auto,
                           validator: proc(v: NimNode): bool): Builder[T] =
  ## Set a field with custom validator
  result = builder.field(name, value)
  builder.fields[name].validator = validator
  result

proc addValidator*[T](builder: Builder[T], 
                     validator: proc(b: Builder[T]): Result[void, PatternError]): Builder[T] =
  ## Add a custom validator for the entire builder
  builder.validators.add(validator)
  builder

proc validate*[T](builder: Builder[T]): Result[void, PatternError] =
  ## Validate all fields
  # Check required fields
  for name, field in builder.fields:
    if field.required and field.value.kind == nnkNilLit:
      return Result[void, PatternError].err(
        ValidationError(
          msg: &"Required field '{name}' is not set",
          pattern: builder.name,
          field: name,
          value: "nil"
        )
      )
    
    # Run field validator if present
    if not field.validator.isNil and not field.validator(field.value):
      return Result[void, PatternError].err(
        ValidationError(
          msg: &"Field '{name}' validation failed",
          pattern: builder.name,
          field: name,
          value: $field.value
        )
      )
  
  # Run custom validators
  for validator in builder.validators:
    let result = validator(builder)
    if result.isErr:
      return result
  
  Result[void, PatternError].ok()

proc reset*[T](builder: Builder[T]): Builder[T] =
  ## Reset the builder to initial state
  builder.fields.clear()
  builder.built = false
  
  if not builder.logger.isNil:
    builder.logger.info("Builder reset")
  
  builder

proc build*[T](builder: Builder[T]): Result[T, PatternError] =
  ## Build the object
  if builder.built:
    return Result[T, PatternError].err(
      newPatternError(builder.name, "Object already built")
    )
  
  # Validate before building
  let validationResult = builder.validate()
  if validationResult.isErr:
    return Result[T, PatternError].err(validationResult.error)
  
  # This is a simplified version - in real implementation,
  # we would use macros to generate the actual object construction
  try:
    var obj: T
    # In actual implementation, populate obj from fields
    builder.built = true
    
    if not builder.logger.isNil:
      builder.logger.info(&"Successfully built {$T}")
    
    Result[T, PatternError].ok(obj)
    
  except CatchableError as e:
    Result[T, PatternError].err(
      newPatternError(builder.name, &"Build failed: {e.msg}", "build")
    )

# Macro for generating typed builders
macro generateBuilder*(T: typedesc): untyped =
  ## Generate a builder for a specific type
  let builderName = ident($T & "Builder")
  
  result = quote do:
    type
      `builderName` = ref object of Builder[`T`]
    
    proc `newBuilderName`(): `builderName` =
      result = `builderName`()
      result.name = $`T` & "Builder"
      result.kind = pkCreational
      result.description = "Builder for " & $`T`
      result.fields = initTable[string, BuilderField]()

# Template for fluent API
template builderFor*(T: typedesc, body: untyped): Builder[T] =
  ## DSL for creating builders
  let builder = newBuilder[T]()
  body
  builder

# Integration with nim_libaspects/errors
proc toAppError*(err: ValidationError): ref AppError =
  ## Convert validation error to AppError
  newValidationError(err.msg, err.field)