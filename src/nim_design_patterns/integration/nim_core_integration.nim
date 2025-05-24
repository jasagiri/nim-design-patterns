## Integration with nim-lang-core for AST manipulation

import std/[strformat, options, sets, json]
import macros
import nim_core
import ../core/base
import ../creational/[factory, builder, singleton]
import ../structural/[adapter, decorator, proxy]
import ../behavioral/[observer, strategy, command]

type
  PatternDetector* = ref object
    ## Detects design patterns in AST
    context: AstContext
    typeAnalyzer: TypeAnalyzer
    symbolIndex: SymbolIndex
  
  DetectedPattern* = object
    kind*: PatternKind
    patternType*: string
    node*: AstNode
    confidence*: float
    metadata*: JsonNode

proc newPatternDetector*(context: AstContext, 
                        typeAnalyzer: TypeAnalyzer,
                        symbolIndex: SymbolIndex): PatternDetector =
  PatternDetector(
    context: context,
    typeAnalyzer: typeAnalyzer,
    symbolIndex: symbolIndex
  )

proc detectSingleton(detector: PatternDetector, node: AstNode): Option[DetectedPattern] =
  ## Detect singleton pattern in AST
  if node.kind != nkType:
    return none(DetectedPattern)
  
  # Look for typical singleton characteristics:
  # 1. Private constructor or init
  # 2. Static instance field
  # 3. GetInstance method
  
  var confidence = 0.0
  var hasPrivateInit = false
  var hasStaticInstance = false
  var hasGetInstance = false
  
  # Check for singleton markers
  for child in node:
    case child.kind:
    of nkProc:
      let name = $child.name
      if name in ["init", "new"] and child.isPrivate:
        hasPrivateInit = true
        confidence += 0.3
      elif name in ["getInstance", "instance", "shared"]:
        hasGetInstance = true
        confidence += 0.4
    of nnkVarSection:
      if child.isStatic and child.name.strVal.contains("instance"):
        hasStaticInstance = true
        confidence += 0.3
    else:
      discard
  
  if confidence >= 0.7:
    some(DetectedPattern(
      kind: pkCreational,
      patternType: "Singleton",
      node: node,
      confidence: confidence,
      metadata: %*{
        "hasPrivateInit": hasPrivateInit,
        "hasStaticInstance": hasStaticInstance,
        "hasGetInstance": hasGetInstance
      }
    ))
  else:
    none(DetectedPattern)

proc detectFactory(detector: PatternDetector, node: AstNode): Option[DetectedPattern] =
  ## Detect factory pattern in AST
  if node.kind != nkType:
    return none(DetectedPattern)
  
  var confidence = 0.0
  var createMethods = 0
  var registryFound = false
  
  # Look for factory characteristics:
  # 1. Multiple create/make methods
  # 2. Registry of creators
  # 3. Abstract product type
  
  for child in node:
    case child.kind:
    of nkProc:
      let name = $child.name
      if name.startsWith("create") or name.startsWith("make"):
        createMethods += 1
        confidence += 0.2
    of nnkVarSection:
      if child.typ.strVal.contains("Table") and 
         child.name.strVal.contains("registry"):
        registryFound = true
        confidence += 0.3
    else:
      discard
  
  if createMethods >= 2:
    confidence += 0.3
  
  if confidence >= 0.6:
    some(DetectedPattern(
      kind: pkCreational,
      patternType: "Factory",
      node: node,
      confidence: confidence,
      metadata: %*{
        "createMethods": createMethods,
        "hasRegistry": registryFound
      }
    ))
  else:
    none(DetectedPattern)

proc detectObserver(detector: PatternDetector, node: AstNode): Option[DetectedPattern] =
  ## Detect observer pattern in AST
  if node.kind != nkType:
    return none(DetectedPattern)
  
  var confidence = 0.0
  var hasObservers = false
  var hasNotify = false
  var hasSubscribe = false
  
  for child in node:
    case child.kind:
    of nnkVarSection:
      if child.typ.strVal.contains("seq") and 
         (child.name.strVal.contains("observer") or 
          child.name.strVal.contains("listener")):
        hasObservers = true
        confidence += 0.3
    of nkProc:
      let name = $child.name
      if name in ["notify", "notifyObservers", "broadcast"]:
        hasNotify = true
        confidence += 0.35
      elif name in ["subscribe", "attach", "addObserver"]:
        hasSubscribe = true  
        confidence += 0.35
    else:
      discard
  
  if confidence >= 0.7:
    some(DetectedPattern(
      kind: pkBehavioral,
      patternType: "Observer",
      node: node,
      confidence: confidence,
      metadata: %*{
        "hasObservers": hasObservers,
        "hasNotify": hasNotify,
        "hasSubscribe": hasSubscribe
      }
    ))
  else:
    none(DetectedPattern)

proc detectPatterns*(detector: PatternDetector, 
                    ast: AstNode): seq[DetectedPattern] =
  ## Detect all patterns in AST
  result = @[]
  
  proc visit(node: AstNode) =
    # Try each pattern detector
    let patterns = [
      detector.detectSingleton(node),
      detector.detectFactory(node),
      detector.detectObserver(node)
    ]
    
    for pattern in patterns:
      if pattern.isSome:
        result.add(pattern.get)
    
    # Recurse
    for child in node:
      visit(child)
  
  visit(ast)

proc applySingletonPattern*(node: AstNode): AstNode =
  ## Transform AST to implement singleton pattern
  # This would generate the singleton implementation
  result = node.copy()
  
  # Add private constructor
  let privateInit = quote do:
    proc init(self: typedesc[Self]): Self {.raises: [].} =
      discard
  
  # Add instance field
  let instanceField = quote do:
    var instance {.threadvar.}: Self
    var initialized = false
    var lock: Lock
  
  # Add getInstance method
  let getInstance = quote do:
    proc getInstance(self: typedesc[Self]): Self =
      if not initialized:
        withLock(lock):
          if not initialized:
            instance = Self()
            initialized = true
      instance
  
  # Insert into type definition
  result.add(privateInit)
  result.add(instanceField)  
  result.add(getInstance)

proc applyFactoryPattern*(node: AstNode, productType: AstNode): AstNode =
  ## Transform AST to implement factory pattern
  result = node.copy()
  
  # Add creator registry
  let registry = quote do:
    var creators: Table[string, proc(): `productType`]
  
  # Add register method
  let register = quote do:
    proc register(key: string, creator: proc(): `productType`) =
      creators[key] = creator
  
  # Add create method
  let create = quote do:
    proc create(key: string): `productType` =
      if key in creators:
        creators[key]()
      else:
        raise newException(ValueError, "Unknown product: " & key)
  
  result.add(registry)
  result.add(register)
  result.add(create)

proc generatePatternCode*(pattern: DetectedPattern): AstNode =
  ## Generate code for detected pattern
  case pattern.patternType:
  of "Singleton":
    applySingletonPattern(pattern.node)
  of "Factory":
    # Need to determine product type from context
    let productType = ident("Product")  # Simplified
    applyFactoryPattern(pattern.node, productType)
  of "Observer":
    # Generate observer implementation
    pattern.node  # Placeholder
  else:
    pattern.node

# Integration with symbol index
proc findPatternUsages*(detector: PatternDetector, 
                       patternType: string): seq[SymbolUsage] =
  ## Find all usages of a pattern type
  let symbols = detector.symbolIndex.findByPattern(patternType & "*")
  result = @[]
  
  for symbol in symbols:
    if symbol.kind == SymbolKind.Type:
      let usages = detector.symbolIndex.findUsages(symbol.name)
      result.add(usages)

# Pattern analysis report
proc analyzePatterns*(detector: PatternDetector, 
                     sourceFile: string): JsonNode =
  ## Analyze patterns in source file
  let ast = detector.analyzer.parseFile(sourceFile)
  let patterns = detector.detectPatterns(ast)
  
  result = %*{
    "file": sourceFile,
    "patterns": newJArray(),
    "statistics": %*{
      "total": patterns.len,
      "byKind": newJObject(),
      "byType": newJObject()
    }
  }
  
  var byKind = initCountTable[string]()
  var byType = initCountTable[string]()
  
  for pattern in patterns:
    result["patterns"].add(%*{
      "kind": $pattern.kind,
      "type": pattern.patternType,
      "confidence": pattern.confidence,
      "location": pattern.node.lineInfo,
      "metadata": pattern.metadata
    })
    
    byKind.inc($pattern.kind)
    byType.inc(pattern.patternType)
  
  for kind, count in byKind:
    result["statistics"]["byKind"][kind] = %count
  
  for patternType, count in byType:
    result["statistics"]["byType"][patternType] = %count