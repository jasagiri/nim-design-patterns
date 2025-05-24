## Pattern Detector implementation for AST-based design pattern recognition
##
## This module provides tools to analyze Nim code AST and detect design pattern usage,
## with facilities to automatically apply patterns to code.

import std/[tables, sets, strformat, options, strutils, hashes, algorithm, sequtils]
import macros
import nim_core
import nim_libaspects/[logging, errors]
import ../core/base

type
  PatternDetectionSignature* = object
    ## Signature that identifies a design pattern
    name*: string
    description*: string
    astSignatures*: seq[AstSignature]
    heuristics*: seq[PatternHeuristic]
    minimumConfidence*: float
  
  AstSignature* = object
    ## AST structure that indicates a pattern
    nodeKind*: NimNodeKind
    children*: seq[AstSignature]
    namePattern*: Option[string]
    requiredProperties*: Table[string, string]
    optional*: bool
  
  PatternHeuristic* = object
    ## Heuristic rule for pattern detection
    description*: string
    weight*: float
    checkFunc*: proc(node: NimNode): bool
  
  PatternMatch* = object
    ## Result of pattern detection
    patternName*: string
    node*: NimNode
    confidence*: float
    matchedSignatures*: seq[AstSignature]
    matchedHeuristics*: seq[PatternHeuristic]
    
  PatternDetector* = ref object of Pattern
    ## Detector for design patterns in code
    signatures*: seq[PatternDetectionSignature]
    logger*: Logger
    astAnalyzer*: AstAnalyzer
    typeAnalyzer*: TypeAnalyzer
    symbolIndex*: SymbolIndex
    
  PatternTransformer* = ref object of Pattern
    ## Transforms code to apply design patterns
    detector*: PatternDetector
    templates*: Table[string, NimNode]
    logger*: Logger
    
  PatternUsageStatistics* = object
    ## Statistics on pattern usage in codebase
    patternCounts*: Table[string, int]
    filePatterns*: Table[string, seq[PatternMatch]]
    totalDetections*: int
    avgConfidence*: float
    potentialRefactorings*: int
    
  PatternDetectionConfig* = object
    ## Configuration for pattern detection
    minConfidence*: float
    includeGeneratedCode*: bool
    enableHeuristics*: bool
    enableAstMatching*: bool
    maxDepth*: int
    
  PatternElement* = enum
    ## Elements that make up a pattern
    pePrivateConstructor
    peStaticField
    peAccessMethod
    peFactoryMethod
    peAbstractReturnType
    peConditionalCreation
    peCollectionOfObservers
    peRegisterMethod
    peNotifyMethod
    peStrategyField
    peStrategySwitch
    peCommandInterface
    peInvoker
    peReceiver
    peAdapterInterface
    peAdapteeField
    peMethodForwarding
    peTemplateMethod
    peHook
    peDecorator
    peComponentField
    peProxy
    peRealSubject
    peThreadSafeSingleton

# Forward declarations
proc matchesAstSignature(node: NimNode, signature: AstSignature, depth = 0): bool
proc calcPatternConfidence(node: NimNode, signature: PatternDetectionSignature): float
proc detectPattern(detector: PatternDetector, node: NimNode, 
                  signature: PatternDetectionSignature): Option[PatternMatch]

# AstSignature implementation
proc newAstSignature*(nodeKind: NimNodeKind, 
                    namePattern = none(string), 
                    optional = false): AstSignature =
  ## Create a new AST signature
  result = AstSignature(
    nodeKind: nodeKind,
    children: @[],
    namePattern: namePattern,
    requiredProperties: initTable[string, string](),
    optional: optional
  )

proc withChild*(signature: AstSignature, child: AstSignature): AstSignature =
  ## Add child signature
  result = signature
  result.children.add(child)

proc withChildren*(signature: AstSignature, 
                  children: varargs[AstSignature]): AstSignature =
  ## Add multiple child signatures
  result = signature
  for child in children:
    result.children.add(child)

proc withProperty*(signature: AstSignature, 
                  name: string, value: string): AstSignature =
  ## Add required property
  result = signature
  result.requiredProperties[name] = value

# Common AST signatures for design patterns
proc singletonSignature*(): PatternDetectionSignature =
  ## Create signature for Singleton pattern
  let privateConstructorSig = newAstSignature(nnkProcDef)
    .withProperty("private", "true")
  
  let staticInstanceSig = newAstSignature(nnkVarSection)
    .withChild(
      newAstSignature(nnkIdentDefs)
        .withChild(newAstSignature(nnkIdent, some".*[Ii]nstance.*"))
    )
  
  let getInstanceSig = newAstSignature(nnkProcDef)
    .withChild(newAstSignature(nnkIdent, some".*[Gg]et.*[Ii]nstance.*"))
    .withChild(newAstSignature(nnkStmtList)
      .withChild(newAstSignature(nnkIfStmt)) # Check for null instance
      .withChild(newAstSignature(nnkReturnStmt)) # Return instance
    )
  
  # Define heuristics
  let classNameHeuristic = PatternHeuristic(
    description: "Class name suggests Singleton",
    weight: 0.2,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Singleton" in typeName
      false
  )
  
  let privateConstructorHeuristic = PatternHeuristic(
    description: "Has private constructor",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeSection:
        # Check if there's a constructor marked private
        for child in node:
          if child.kind == nnkProcDef and child[0].kind == nnkPostfix and $child[0][0] == "*":
            return false # Public constructor
        return true
      false
  )
  
  let staticInstanceHeuristic = PatternHeuristic(
    description: "Has static instance field",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkVarSection:
        for child in node:
          if child.kind == nnkIdentDefs and 
             child[0].kind == nnkIdent and 
             "instance" in $child[0]:
            return true
      false
  )
  
  PatternDetectionSignature(
    name: "Singleton",
    description: "Singleton pattern ensures a class has only one instance",
    astSignatures: @[privateConstructorSig, staticInstanceSig, getInstanceSig],
    heuristics: @[classNameHeuristic, privateConstructorHeuristic, staticInstanceHeuristic],
    minimumConfidence: 0.7
  )

proc factorySignature*(): PatternDetectionSignature =
  ## Create signature for Factory pattern
  let factoryMethodSig = newAstSignature(nnkProcDef)
    .withChild(newAstSignature(nnkIdent, some".*[Cc]reate.*|.*[Mm]ake.*|.*[Nn]ew.*|.*[Gg]et.*"))
    .withChild(newAstSignature(nnkStmtList)
      .withChild(newAstSignature(nnkIfStmt, none(string), true)) # Optional conditional creation
      .withChild(newAstSignature(nnkCaseStmt, none(string), true))
      .withChild(newAstSignature(nnkReturnStmt)) # Return created object
    )
  
  # Define heuristics
  let classNameHeuristic = PatternHeuristic(
    description: "Class name suggests Factory",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Factory" in typeName
      false
  )
  
  let returnTypeHeuristic = PatternHeuristic(
    description: "Returns abstract/interface type",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkProcDef:
        # Check if return type is a base type
        let returnType = node[3][0]
        if returnType.kind == nnkRefTy:
          return true
      false
  )
  
  let conditionalCreationHeuristic = PatternHeuristic(
    description: "Uses conditional creation logic",
    weight: 0.4,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkProcDef:
        for child in node:
          if child.kind == nnkStmtList:
            for stmt in child:
              if stmt.kind in {nnkIfStmt, nnkCaseStmt}:
                return true
      false
  )
  
  PatternDetectionSignature(
    name: "Factory",
    description: "Factory pattern creates objects without specifying exact class",
    astSignatures: @[factoryMethodSig],
    heuristics: @[classNameHeuristic, returnTypeHeuristic, conditionalCreationHeuristic],
    minimumConfidence: 0.6
  )

proc observerSignature*(): PatternDetectionSignature =
  ## Create signature for Observer pattern
  let observerCollectionSig = newAstSignature(nnkVarSection)
    .withChild(
      newAstSignature(nnkIdentDefs)
        .withChild(newAstSignature(nnkIdent, some".*[Oo]bservers.*|.*[Ll]isteners.*"))
    )
  
  let registerMethodSig = newAstSignature(nnkProcDef)
    .withChild(newAstSignature(nnkIdent, some".*[Aa]dd.*|.*[Rr]egister.*|.*[Ss]ubscribe.*|.*[Aa]ttach.*"))
  
  let notifyMethodSig = newAstSignature(nnkProcDef)
    .withChild(newAstSignature(nnkIdent, some".*[Nn]otify.*|.*[Uu]pdate.*|.*[Pp]ublish.*"))
    .withChild(newAstSignature(nnkStmtList)
      .withChild(newAstSignature(nnkForStmt)) # Loop through observers
    )
  
  # Define heuristics
  let subjectNameHeuristic = PatternHeuristic(
    description: "Class name suggests Subject",
    weight: 0.2,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Subject" in typeName or "Observable" in typeName
      false
  )
  
  let observerNameHeuristic = PatternHeuristic(
    description: "Class name suggests Observer",
    weight: 0.2,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Observer" in typeName or "Listener" in typeName
      false
  )
  
  let observerCollectionHeuristic = PatternHeuristic(
    description: "Has collection of observers",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkRecList:
        for child in node:
          if child.kind == nnkIdentDefs:
            let fieldName = $child[0]
            let fieldType = $child[1]
            if ("observers" in fieldName.toLowerAscii or 
                "listeners" in fieldName.toLowerAscii) and
               ("seq" in fieldType or "array" in fieldType or 
                "set" in fieldType or "table" in fieldType):
              return true
      false
  )
  
  let notificationHeuristic = PatternHeuristic(
    description: "Has notification loop",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkProcDef:
        let procName = $node[0]
        if "notify" in procName.toLowerAscii or 
           "update" in procName.toLowerAscii or 
           "publish" in procName.toLowerAscii:
          # Check for a loop in the body
          for child in node:
            if child.kind == nnkStmtList:
              for stmt in child:
                if stmt.kind in {nnkForStmt, nnkWhileStmt}:
                  return true
      false
  )
  
  PatternDetectionSignature(
    name: "Observer",
    description: "Observer pattern defines one-to-many dependency between objects",
    astSignatures: @[observerCollectionSig, registerMethodSig, notifyMethodSig],
    heuristics: @[subjectNameHeuristic, observerNameHeuristic, 
                 observerCollectionHeuristic, notificationHeuristic],
    minimumConfidence: 0.6
  )

proc strategySignature*(): PatternDetectionSignature =
  ## Create signature for Strategy pattern
  let strategyFieldSig = newAstSignature(nnkRecList)
    .withChild(
      newAstSignature(nnkIdentDefs)
        .withChild(newAstSignature(nnkIdent, some".*[Ss]trategy.*|.*[Aa]lgorithm.*"))
    )
  
  let strategySetterSig = newAstSignature(nnkProcDef)
    .withChild(newAstSignature(nnkIdent, some".*[Ss]et.*[Ss]trategy.*|.*[Cc]hange.*[Ss]trategy.*"))
  
  let strategyUseSig = newAstSignature(nnkProcDef)
    .withChild(newAstSignature(nnkStmtList)
      .withChild(newAstSignature(nnkDotExpr, none(string), true)) # strategy.execute()
    )
  
  # Define heuristics
  let contextNameHeuristic = PatternHeuristic(
    description: "Class name suggests Context",
    weight: 0.2,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Context" in typeName
      false
  )
  
  let strategyNameHeuristic = PatternHeuristic(
    description: "Interface/class name suggests Strategy",
    weight: 0.2,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Strategy" in typeName or "Algorithm" in typeName
      false
  )
  
  let strategyFieldHeuristic = PatternHeuristic(
    description: "Has strategy field",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkRecList:
        for child in node:
          if child.kind == nnkIdentDefs:
            let fieldName = $child[0]
            if "strategy" in fieldName.toLowerAscii or "algorithm" in fieldName.toLowerAscii:
              return true
      false
  )
  
  let strategyDelegationHeuristic = PatternHeuristic(
    description: "Delegates work to strategy",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkProcDef:
        for child in node:
          if child.kind == nnkStmtList:
            for stmt in child:
              if stmt.kind == nnkCall and stmt[0].kind == nnkDotExpr:
                let dotExpr = stmt[0]
                let objName = $dotExpr[0]
                if "strategy" in objName.toLowerAscii or "algorithm" in objName.toLowerAscii:
                  return true
      false
  )
  
  PatternDetectionSignature(
    name: "Strategy",
    description: "Strategy pattern defines a family of algorithms, encapsulates each one",
    astSignatures: @[strategyFieldSig, strategySetterSig, strategyUseSig],
    heuristics: @[contextNameHeuristic, strategyNameHeuristic, 
                strategyFieldHeuristic, strategyDelegationHeuristic],
    minimumConfidence: 0.6
  )

proc commandSignature*(): PatternDetectionSignature =
  ## Create signature for Command pattern
  let commandInterfaceSig = newAstSignature(nnkTypeDef)
    .withChild(newAstSignature(nnkIdent, some".*[Cc]ommand.*"))
    .withChild(
      newAstSignature(nnkObjectTy)
        .withChild(newAstSignature(nnkRefTy))
    )
  
  let executeMethodSig = newAstSignature(nnkProcDef)
    .withChild(newAstSignature(nnkIdent, some".*[Ee]xecute.*|.*[Rr]un.*|.*[Pp]erform.*"))
  
  let invokerSig = newAstSignature(nnkTypeDef)
    .withChild(
      newAstSignature(nnkRecList)
        .withChild(
          newAstSignature(nnkIdentDefs)
            .withChild(newAstSignature(nnkIdent, some".*[Cc]ommands?.*"))
        )
    )
  
  # Define heuristics
  let commandNameHeuristic = PatternHeuristic(
    description: "Class name suggests Command",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Command" in typeName or 
               "Action" in typeName or 
               "Operation" in typeName
      false
  )
  
  let executeMethodHeuristic = PatternHeuristic(
    description: "Has execute method",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkProcDef:
        let procName = $node[0]
        return "execute" in procName.toLowerAscii or 
               "run" in procName.toLowerAscii or 
               "perform" in procName.toLowerAscii
      false
  )
  
  let commandCollectionHeuristic = PatternHeuristic(
    description: "Has command collection",
    weight: 0.3,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkRecList:
        for child in node:
          if child.kind == nnkIdentDefs:
            let fieldName = $child[0]
            let fieldType = $child[1]
            if ("command" in fieldName.toLowerAscii) and
               ("seq" in fieldType or "array" in fieldType or 
                "list" in fieldType or "queue" in fieldType):
              return true
      false
  )
  
  let invokerHeuristic = PatternHeuristic(
    description: "Has invoker role",
    weight: 0.1,
    checkFunc: proc(node: NimNode): bool =
      if node.kind == nnkTypeDef:
        let typeName = $node[0]
        return "Invoker" in typeName or "Executor" in typeName
      false
  )
  
  PatternDetectionSignature(
    name: "Command",
    description: "Command pattern encapsulates a request as an object",
    astSignatures: @[commandInterfaceSig, executeMethodSig, invokerSig],
    heuristics: @[commandNameHeuristic, executeMethodHeuristic, 
                 commandCollectionHeuristic, invokerHeuristic],
    minimumConfidence: 0.6
  )

# PatternDetector implementation
proc newPatternDetector*(astAnalyzer: AstAnalyzer,
                        typeAnalyzer: TypeAnalyzer,
                        symbolIndex: SymbolIndex): PatternDetector =
  ## Create a new pattern detector
  result = PatternDetector(
    name: "PatternDetector",
    kind: pkBehavioral,
    description: "Detects design patterns in code",
    signatures: @[],
    astAnalyzer: astAnalyzer,
    typeAnalyzer: typeAnalyzer,
    symbolIndex: symbolIndex
  )
  
  # Add standard patterns
  result.signatures.add(singletonSignature())
  result.signatures.add(factorySignature())
  result.signatures.add(observerSignature())
  result.signatures.add(strategySignature())
  result.signatures.add(commandSignature())

proc withLogging*(detector: PatternDetector, logger: Logger): PatternDetector =
  ## Add logging to detector
  detector.logger = logger
  detector

proc addCustomSignature*(detector: PatternDetector, 
                        signature: PatternDetectionSignature): PatternDetector =
  ## Add a custom pattern signature
  detector.signatures.add(signature)
  detector

# Pattern detection implementation
proc matchesAstSignature(node: NimNode, signature: AstSignature, depth = 0): bool =
  ## Check if node matches AST signature
  # Optional signature can be missing
  if signature.optional and node.isNil:
    return true
  
  # Nil checks
  if node.isNil:
    return false
  
  # Check node kind
  if node.kind != signature.nodeKind:
    return false
  
  # Check name pattern if provided
  if signature.namePattern.isSome:
    let pattern = signature.namePattern.get()
    if node.kind in {nnkIdent, nnkSym} and not ($node).contains(pattern):
      return false
  
  # Check required properties
  for name, value in signature.requiredProperties:
    # Property checking would be implemented based on specific properties
    # This is a simplified example
    if name == "private" and value == "true":
      # Check if proc is private (no export marker)
      if node.kind == nnkProcDef:
        let nameNode = node[0]
        if nameNode.kind == nnkPostfix and $nameNode[0] == "*":
          return false
  
  # Check children recursively
  if signature.children.len > 0:
    var matchedChildren = 0
    
    for childSig in signature.children:
      var foundMatch = false
      
      # If node is a leaf, it won't have children to check
      if node.len == 0:
        if childSig.optional:
          matchedChildren += 1
        continue
      
      # Look through actual children for matches
      for i in 0..<node.len:
        if matchesAstSignature(node[i], childSig, depth + 1):
          foundMatch = true
          break
      
      # Also look through deeper levels if not found (for certain node kinds)
      if not foundMatch and node.kind in {nnkStmtList, nnkRecList, nnkObjectTy, nnkProcDef}:
        for i in 0..<node.len:
          let child = node[i]
          if not child.isNil and child.kind in {nnkStmtList, nnkRecList, nnkObjectTy}:
            if matchesAstSignature(child, childSig, depth + 1):
              foundMatch = true
              break
      
      if foundMatch or childSig.optional:
        matchedChildren += 1
    
    return matchedChildren == signature.children.len
  
  true # No children to check

proc calcPatternConfidence(node: NimNode, signature: PatternDetectionSignature): float =
  ## Calculate confidence score for pattern match
  var confidence = 0.0
  var maxPossibleScore = 0.0
  
  # Check AST signatures
  var matchedSignatures = 0
  for astSig in signature.astSignatures:
    if matchesAstSignature(node, astSig):
      matchedSignatures += 1
  
  # Calculate AST match score
  if signature.astSignatures.len > 0:
    confidence += 0.5 * (matchedSignatures.float / signature.astSignatures.len.float)
    maxPossibleScore += 0.5
  
  # Apply heuristics
  for heuristic in signature.heuristics:
    maxPossibleScore += heuristic.weight
    if heuristic.checkFunc(node):
      confidence += heuristic.weight
  
  # Normalize to 0-1 range if we have a non-zero denominator
  if maxPossibleScore > 0:
    confidence /= maxPossibleScore
  
  confidence

proc detectPattern(detector: PatternDetector, node: NimNode, 
                  signature: PatternDetectionSignature): Option[PatternMatch] =
  ## Detect if node matches a specific pattern
  let confidence = calcPatternConfidence(node, signature)
  
  if confidence >= signature.minimumConfidence:
    # Create match result
    var matchedSignatures: seq[AstSignature] = @[]
    var matchedHeuristics: seq[PatternHeuristic] = @[]
    
    # Record which signatures matched
    for astSig in signature.astSignatures:
      if matchesAstSignature(node, astSig):
        matchedSignatures.add(astSig)
    
    # Record which heuristics matched
    for heuristic in signature.heuristics:
      if heuristic.checkFunc(node):
        matchedHeuristics.add(heuristic)
    
    let match = PatternMatch(
      patternName: signature.name,
      node: node,
      confidence: confidence,
      matchedSignatures: matchedSignatures,
      matchedHeuristics: matchedHeuristics
    )
    
    if not detector.logger.isNil:
      detector.logger.debug(&"Detected {signature.name} pattern with confidence {confidence:.2f}")
    
    return some(match)
  
  none(PatternMatch)

proc detectPatterns*(detector: PatternDetector, 
                    node: NimNode): seq[PatternMatch] =
  ## Detect all patterns in a node
  result = @[]
  
  # Check each signature
  for signature in detector.signatures:
    let match = detector.detectPattern(node, signature)
    if match.isSome:
      result.add(match.get())
  
  # Sort by confidence (descending)
  result.sort(proc(a, b: PatternMatch): int = 
    cmp(b.confidence, a.confidence))

proc detectPatternsInFile*(detector: PatternDetector, 
                          filePath: string): seq[PatternMatch] =
  ## Detect patterns in a source file
  result = @[]
  
  if not detector.logger.isNil:
    detector.logger.info(&"Detecting patterns in file: {filePath}")
  
  let ast = detector.astAnalyzer.parseFile(filePath)
  if ast.isNil:
    if not detector.logger.isNil:
      detector.logger.error(&"Failed to parse file: {filePath}")
    return @[]
  
  # Process the AST
  proc processNode(node: NimNode) =
    if node.isNil:
      return
    
    # Check for patterns at this node
    let matches = detector.detectPatterns(node)
    result.add(matches)
    
    # Recursively process children
    for i in 0..<node.len:
      processNode(node[i])
  
  processNode(ast)
  
  if not detector.logger.isNil:
    detector.logger.info(&"Detected {result.len} pattern instances in {filePath}")

proc analyzeProject*(detector: PatternDetector, 
                    projectPath: string): PatternUsageStatistics =
  ## Analyze pattern usage in a project
  var stats = PatternUsageStatistics(
    patternCounts: initTable[string, int](),
    filePatterns: initTable[string, seq[PatternMatch]](),
    totalDetections: 0,
    avgConfidence: 0.0,
    potentialRefactorings: 0
  )
  
  # Get all Nim files in project
  let nimFiles = detector.symbolIndex.getFiles(projectPath, "*.nim")
  
  if not detector.logger.isNil:
    detector.logger.info(&"Analyzing {nimFiles.len} files in project: {projectPath}")
  
  var totalConfidence = 0.0
  
  # Process each file
  for file in nimFiles:
    let matches = detector.detectPatternsInFile(file)
    
    if matches.len > 0:
      stats.filePatterns[file] = matches
      stats.totalDetections += matches.len
      
      # Update pattern counts
      for match in matches:
        if match.patternName notin stats.patternCounts:
          stats.patternCounts[match.patternName] = 0
        
        stats.patternCounts[match.patternName] += 1
        totalConfidence += match.confidence
    
    # Look for potential refactoring opportunities
    # (This is a simplified example - real implementation would be more sophisticated)
    let ast = detector.astAnalyzer.parseFile(file)
    if not ast.isNil:
      proc findRefactoringOpportunities(node: NimNode) =
        if node.isNil:
          return
        
        # Check for potential Factory pattern opportunity
        if node.kind == nnkProcDef:
          let body = node[^1]
          var hasTypeChecks = false
          
          proc findTypeChecks(n: NimNode) =
            if n.isNil:
              return
            
            if n.kind == nnkIfStmt or n.kind == nnkCaseStmt:
              hasTypeChecks = true
              return
            
            for i in 0..<n.len:
              findTypeChecks(n[i])
          
          findTypeChecks(body)
          
          if hasTypeChecks:
            inc stats.potentialRefactorings
        
        # Check other potential refactoring opportunities
        
        # Process children
        for i in 0..<node.len:
          findRefactoringOpportunities(node[i])
      
      findRefactoringOpportunities(ast)
  
  # Calculate average confidence
  if stats.totalDetections > 0:
    stats.avgConfidence = totalConfidence / stats.totalDetections.float
  
  if not detector.logger.isNil:
    detector.logger.info(&"Analysis complete: {stats.totalDetections} patterns detected across {stats.filePatterns.len} files")
    detector.logger.info(&"Average confidence: {stats.avgConfidence:.2f}")
    detector.logger.info(&"Potential refactoring opportunities: {stats.potentialRefactorings}")
  
  stats

# PatternTransformer implementation
proc newPatternTransformer*(detector: PatternDetector): PatternTransformer =
  ## Create a new pattern transformer
  result = PatternTransformer(
    name: "PatternTransformer",
    kind: pkBehavioral,
    description: "Transforms code to apply design patterns",
    detector: detector,
    templates: initTable[string, NimNode]()
  )
  
  # Add standard pattern templates
  # These would be AST templates for pattern implementations
  # Simplified example:
  
  # Singleton pattern template
  let singletonTemplate = quote do:
    type MyType = ref object
      # Fields here
    
    var instance: MyType = nil
    var lock: Lock
    initLock(lock)
    
    proc getInstance(): MyType =
      if isNil(instance):
        withLock(lock):
          if isNil(instance):
            instance = MyType()
      return instance
  
  result.templates["Singleton"] = singletonTemplate

proc withLogging*(transformer: PatternTransformer, 
                 logger: Logger): PatternTransformer =
  ## Add logging to transformer
  transformer.logger = logger
  transformer

proc registerPatternTemplate*(transformer: PatternTransformer,
                            patternName: string,
                            template: NimNode): PatternTransformer =
  ## Register a custom pattern template
  transformer.templates[patternName] = template
  transformer

proc applyPattern*(transformer: PatternTransformer,
                  node: NimNode,
                  patternName: string): NimNode =
  ## Apply pattern to an AST node
  if patternName notin transformer.templates:
    if not transformer.logger.isNil:
      transformer.logger.error(&"No template registered for pattern: {patternName}")
    return node
  
  let template = transformer.templates[patternName]
  
  # In a real implementation, this would:
  # 1. Analyze the target node
  # 2. Extract relevant parts (field names, method names, etc.)
  # 3. Substitute these into the template
  # 4. Replace or merge with the original node
  
  if not transformer.logger.isNil:
    transformer.logger.info(&"Applied {patternName} pattern to node")
  
  # This is a simplified placeholder - actual implementation would be more complex
  template

proc applyPatternToFile*(transformer: PatternTransformer,
                        filePath: string,
                        patternName: string,
                        outputPath = ""): bool =
  ## Apply pattern to a source file
  if not transformer.logger.isNil:
    transformer.logger.info(&"Applying {patternName} pattern to file: {filePath}")
  
  let ast = transformer.detector.astAnalyzer.parseFile(filePath)
  if ast.isNil:
    if not transformer.logger.isNil:
      transformer.logger.error(&"Failed to parse file: {filePath}")
    return false
  
  let transformedAst = transformer.applyPattern(ast, patternName)
  
  # Write to output file
  let actualOutputPath = if outputPath.len > 0: outputPath else: filePath
  
  try:
    # This is a placeholder - in a real implementation, would properly format and write the AST
    writeFile(actualOutputPath, $transformedAst)
    
    if not transformer.logger.isNil:
      transformer.logger.info(&"Pattern applied successfully to {filePath}, output written to {actualOutputPath}")
    
    return true
    
  except IOError as e:
    if not transformer.logger.isNil:
      transformer.logger.error(&"Failed to write output file: {e.msg}")
    
    return false

# Utilities for pattern analysis
proc getPatternDistribution*(stats: PatternUsageStatistics): Table[string, float] =
  ## Get distribution of pattern usage
  result = initTable[string, float]()
  
  if stats.totalDetections == 0:
    return result
  
  for pattern, count in stats.patternCounts:
    result[pattern] = count.float / stats.totalDetections.float

proc getTopPatterns*(stats: PatternUsageStatistics, limit = 5): seq[tuple[name: string, count: int]] =
  ## Get top used patterns
  result = @[]
  
  for pattern, count in stats.patternCounts:
    result.add((name: pattern, count: count))
  
  result.sort(proc(a, b: tuple[name: string, count: int]): int = 
    cmp(b.count, a.count))
  
  if result.len > limit:
    result.setLen(limit)

proc getFilesWithMostPatterns*(stats: PatternUsageStatistics, limit = 5): seq[tuple[file: string, count: int]] =
  ## Get files with most pattern usages
  result = @[]
  
  for file, matches in stats.filePatterns:
    result.add((file: file, count: matches.len))
  
  result.sort(proc(a, b: tuple[file: string, count: int]): int = 
    cmp(b.count, a.count))
  
  if result.len > limit:
    result.setLen(limit)

proc getPatternQualityMetrics*(stats: PatternUsageStatistics): Table[string, float] =
  ## Get quality metrics for pattern implementations
  result = initTable[string, float]()
  
  for pattern, count in stats.patternCounts:
    var totalConfidence = 0.0
    var matchCount = 0
    
    # Calculate average confidence for each pattern
    for file, matches in stats.filePatterns:
      for match in matches:
        if match.patternName == pattern:
          totalConfidence += match.confidence
          inc matchCount
    
    if matchCount > 0:
      result[pattern] = totalConfidence / matchCount.float