## Monad Pattern Example
## 
## This example demonstrates the use of the Monad pattern for managing sequences of operations
## that involve optional values, error handling, and state transformations.

import ../src/nim_design_patterns/functional/monad
import options, sugar
import std/[strutils, strformat, tables]
import std/json except `%`

# ---------------------------------------------------------
# Example 1: Using Maybe monad for handling optional values
# ---------------------------------------------------------

proc example1() =
  echo "==== Example 1: Maybe Monad for Optional Values ===="
  
  # We'll use the Maybe monad to safely process a chain of operations
  # that might return nil/none at any step
  
  type 
    Profile = ref object
      bio: string
      website: string
  
    User = ref object
      id: int
      name: string
      email: string
      profile: Profile
    
  # Create a database of users (in a real app, this would be a database)
  let users = {
    1: User(id: 1, name: "Alice", email: "alice@example.com", 
       profile: Profile(bio: "Software engineer", website: "alice.dev")),
    2: User(id: 2, name: "Bob", email: "bob@example.com", 
       profile: nil),  # Bob has no profile
    3: User(id: 3, name: "Charlie", email: "charlie@example.com", 
       profile: Profile(bio: "Product manager", website: ""))  # Charlie has no website
  }.toTable
  
  # Helper functions that might return None
  proc findUser(userId: int): Maybe[User] =
    if users.hasKey(userId):
      just(users[userId])
    else:
      nothing[User]()
  
  proc getProfile(user: User): Maybe[Profile] =
    if user.profile != nil:
      just(user.profile)
    else:
      nothing[Profile]()
      
  proc getWebsite(profile: Profile): Maybe[string] =
    if profile.website.len > 0:
      just(profile.website)
    else:
      nothing[string]()
  
  # Without monads - verbose nested checks
  proc getUserWebsiteTraditional(userId: int): string =
    if users.hasKey(userId):
      let user = users[userId]
      if user.profile != nil:
        if user.profile.website.len > 0:
          return user.profile.website
    return "No website found"
    
  # With monads - chained operations
  proc getUserWebsiteMonadic(userId: int): string =
    let websiteMaybe = findUser(userId)
      .flatMap(getProfile)
      .flatMap(getWebsite)
    
    websiteMaybe.getOrElse("No website found")
  
  # Using the template combinator for a more readable syntax
  proc getUserWebsiteTemplate(userId: int): string =
    let websiteMaybe = withMaybe[User, string](findUser(userId), user):
      withMaybe[Profile, string](getProfile(user), profile):
        getWebsite(profile)
    
    websiteMaybe.getOrElse("No website found")
    
  # Test with different users
  echo "User 1 website (traditional): ", getUserWebsiteTraditional(1)
  echo "User 1 website (monadic):     ", getUserWebsiteMonadic(1)
  echo "User 1 website (template):    ", getUserWebsiteTemplate(1)
  echo ""
  
  echo "User 2 website (traditional): ", getUserWebsiteTraditional(2)
  echo "User 2 website (monadic):     ", getUserWebsiteMonadic(2)
  echo "User 2 website (template):    ", getUserWebsiteTemplate(2)
  echo ""
  
  echo "User 3 website (traditional): ", getUserWebsiteTraditional(3)
  echo "User 3 website (monadic):     ", getUserWebsiteMonadic(3)
  echo "User 3 website (template):    ", getUserWebsiteTemplate(3)
  echo ""
  
  echo "User 4 website (traditional): ", getUserWebsiteTraditional(4)
  echo "User 4 website (monadic):     ", getUserWebsiteMonadic(4)
  echo "User 4 website (template):    ", getUserWebsiteTemplate(4)

# ---------------------------------------------------------
# Example 2: Using Result monad for error handling
# ---------------------------------------------------------

proc example2() =
  echo "==== Example 2: Result Monad for Error Handling ===="
  
  # We'll use the Result monad to handle errors in a chain of operations
  
  type 
    ErrorKind = enum
      InvalidInput, NotFound, ParseError, DivisionByZero
      
    Calculator = ref object
      memory: Table[string, float]
  
  # Helper functions that might return errors
  proc parseNumber(input: string): Result[float, ErrorKind] =
    try:
      success[float, ErrorKind](parseFloat(input))
    except ValueError:
      failure[float, ErrorKind](ParseError)
  
  proc divide(a, b: float): Result[float, ErrorKind] =
    if b == 0:
      failure[float, ErrorKind](DivisionByZero)
    else:
      success[float, ErrorKind](a / b)
      
  proc getMemoryValue(calc: Calculator, key: string): Result[float, ErrorKind] =
    if calc.memory.hasKey(key):
      success[float, ErrorKind](calc.memory[key])
    else:
      failure[float, ErrorKind](NotFound)
  
  proc setMemoryValue(calc: Calculator, key: string, value: float): Calculator =
    calc.memory[key] = value
    calc
  
  # Without monads - verbose error handling
  proc calculateTraditional(calc: Calculator, a, b, c: string): string =
    # Attempt to perform (a / b) * c
    var aValue: float
    try:
      aValue = parseFloat(a)
    except ValueError:
      return fmt"Error: Could not parse '{a}'"
      
    var bValue: float
    try:
      bValue = parseFloat(b)
    except ValueError:
      return fmt"Error: Could not parse '{b}'"
      
    if bValue == 0:
      return "Error: Division by zero"
      
    var cValue: float
    try:
      cValue = parseFloat(c)
    except ValueError:
      return fmt"Error: Could not parse '{c}'"
      
    let result = (aValue / bValue) * cValue
    calc.memory["last"] = result
    return fmt"Result: {result}"
  
  # With monads - cleaner error handling
  proc calculateMonadic(calc: Calculator, a, b, c: string): string =
    let resultWithDivision = 
      parseNumber(a).flatMap(proc(aValue: float): Result[float, ErrorKind] =
        parseNumber(b).flatMap(proc(bValue: float): Result[float, ErrorKind] =
          divide(aValue, bValue)
        )
      )
      
    let finalResult = resultWithDivision.flatMap(proc(divResult: float): Result[float, ErrorKind] =
      parseNumber(c).map(proc(cValue: float): float =
        divResult * cValue
      )
    )
    
    # Handle the result
    let output = finalResult.fold(
      proc(value: float): string =
        discard setMemoryValue(calc, "last", value)
        fmt"Result: {value}",
      proc(error: ErrorKind): string =
        fmt"Error: {error}"
    )
    
    return output
  
  # Using the template combinator for a more readable syntax
  proc calculateTemplate(calc: Calculator, a, b, c: string): string =
    let finalResult = withResult[float, ErrorKind, float](parseNumber(a), aValue):
      withResult[float, ErrorKind, float](parseNumber(b), bValue):
        withResult[float, ErrorKind, float](divide(aValue, bValue), divResult):
          withResult[float, ErrorKind, float](parseNumber(c), cValue):
            success[float, ErrorKind](divResult * cValue)
    
    # Handle the result
    let output = finalResult.fold(
      proc(value: float): string =
        discard setMemoryValue(calc, "last", value)
        fmt"Result: {value}",
      proc(error: ErrorKind): string =
        fmt"Error: {error}"
    )
    
    return output
  
  # Test with different inputs
  var calculator = Calculator(memory: initTable[string, float]())
  
  echo "Calculate 10 / 2 * 3 (traditional): ", calculateTraditional(calculator, "10", "2", "3")
  echo "Calculate 10 / 2 * 3 (monadic):     ", calculateMonadic(calculator, "10", "2", "3")
  echo "Calculate 10 / 2 * 3 (template):    ", calculateTemplate(calculator, "10", "2", "3")
  echo ""
  
  echo "Calculate 10 / 0 * 3 (traditional): ", calculateTraditional(calculator, "10", "0", "3")
  echo "Calculate 10 / 0 * 3 (monadic):     ", calculateMonadic(calculator, "10", "0", "3")
  echo "Calculate 10 / 0 * 3 (template):    ", calculateTemplate(calculator, "10", "0", "3")
  echo ""
  
  echo "Calculate 10 / 2 * x (traditional): ", calculateTraditional(calculator, "10", "2", "x")
  echo "Calculate 10 / 2 * x (monadic):     ", calculateMonadic(calculator, "10", "2", "x")
  echo "Calculate 10 / 2 * x (template):    ", calculateTemplate(calculator, "10", "2", "x")
  echo ""

# ---------------------------------------------------------
# Example 3: Using State monad for managing state transformations
# ---------------------------------------------------------

proc example3() =
  echo "==== Example 3: State Monad for Managing State ===="
  
  # We'll use the State monad to manage state transformations in a purely functional way
  
  type GameState = object
    player: string
    health: int
    score: int
    level: int
    inventory: seq[string]
  
  # Initialize the game
  let initialState = GameState(
    player: "Hero",
    health: 100,
    score: 0,
    level: 1,
    inventory: @[]
  )
  
  # Helper functions using the State monad
  proc takeDamage(amount: int): State[GameState, EmptyType] =
    modify(proc(s: GameState): GameState =
      result = s
      result.health = max(0, s.health - amount)
    )
  
  proc addScore(points: int): State[GameState, EmptyType] =
    modify(proc(s: GameState): GameState =
      result = s
      result.score += points
    )
  
  proc levelUp(): State[GameState, EmptyType] =
    modify(proc(s: GameState): GameState =
      result = s
      result.level += 1
      # Increase health with each level
      result.health = min(100, s.health + 20)
    )
  
  proc addToInventory(item: string): State[GameState, EmptyType] =
    modify(proc(s: GameState): GameState =
      result = s
      result.inventory.add(item)
    )
  
  proc getStatus(): State[GameState, string] =
    state(proc(s: GameState): tuple[value: string, state: GameState] =
      let status = fmt"""
        Player: {s.player}
        Health: {s.health}
        Score: {s.score}
        Level: {s.level}
        Inventory: {s.inventory}
      """
      (status, s)
    )
  
  # Without monads - explicit state threading
  proc playGameTraditional(initialState: GameState): tuple[status: string, finalState: GameState] =
    # Apply a sequence of game events
    var state = initialState
    
    # Player finds a sword
    state.inventory.add("Sword")
    
    # Player defeats an enemy
    state.score += 100
    
    # Player takes damage
    state.health = max(0, state.health - 30)
    
    # Player finds a potion
    state.inventory.add("Health Potion")
    
    # Player uses the potion
    state.health = min(100, state.health + 20)
    
    # Player levels up
    state.level += 1
    state.health = min(100, state.health + 20)
    
    # Generate status and return
    let status = fmt"""
      Player: {state.player}
      Health: {state.health}
      Score: {state.score}
      Level: {state.level}
      Inventory: {state.inventory}
    """
    
    return (status, state)
  
  # With monads - state transformations are composed
  proc playGameMonadic(initialState: GameState): tuple[status: string, finalState: GameState] =
    # Define the game as a sequence of state transformations
    let gameSequence = 
      # Player finds a sword
      addToInventory("Sword").flatMap(proc(_: EmptyType): State[GameState, EmptyType] =
        # Player defeats an enemy
        addScore(100).flatMap(proc(_: EmptyType): State[GameState, EmptyType] =
          # Player takes damage
          takeDamage(30).flatMap(proc(_: EmptyType): State[GameState, EmptyType] =
            # Player finds a potion
            addToInventory("Health Potion").flatMap(proc(_: EmptyType): State[GameState, EmptyType] =
              # Player uses the potion (would be another state transformation in real game)
              modify(proc(s: GameState): GameState =
                result = s
                result.health = min(100, s.health + 20)
              ).flatMap(proc(_: EmptyType): State[GameState, EmptyType] =
                # Player levels up
                levelUp()
              )
            )
          )
        )
      ).flatMap(proc(_: EmptyType): State[GameState, string] =
        # Get the final game status
        getStatus()
      )
    
    # Run the game sequence with the initial state
    let (value, finalState) = runState(gameSequence, initialState)
    return (value, finalState)
  
  # Using do-notation style with templates would make this cleaner
  # but we'll use a different approach for demonstration
  proc playGameFluent(initialState: GameState): tuple[status: string, finalState: GameState] =
    # Create a sequence of game operations to run in order
    let findSword = addToInventory("Sword")
    let defeatEnemy = addScore(100)
    let takeHit = takeDamage(30)
    let findPotion = addToInventory("Health Potion")
    let usePotion = modify(proc(s: GameState): GameState =
      result = s
      result.health = min(100, s.health + 20)
    )
    let playerLevelUp = levelUp()
    
    # Create a helper to chain operations that return EmptyType
    proc chain[S](s1, s2: State[S, EmptyType]): State[S, EmptyType] =
      s1.flatMap(proc(_: EmptyType): State[S, EmptyType] = s2)
    
    # Chain all operations together
    let gameSequence = 
      chain(findSword, 
        chain(defeatEnemy, 
          chain(takeHit,
            chain(findPotion,
              chain(usePotion, playerLevelUp)))))
      .flatMap(proc(_: EmptyType): State[GameState, string] = getStatus())
    
    # Run the game sequence
    let (value, finalState) = runState(gameSequence, initialState)
    return (value, finalState)
  
  # Test the different implementations
  let (tradStatus, tradState) = playGameTraditional(initialState)
  echo "Traditional approach:"
  echo tradStatus
  
  let (monadStatus, monadState) = playGameMonadic(initialState)
  echo "\nMonadic approach:"
  echo monadStatus
  
  let (fluentStatus, fluentState) = playGameFluent(initialState)
  echo "\nFluent approach:"
  echo fluentStatus

# ---------------------------------------------------------
# Example 4: Combining different monads
# ---------------------------------------------------------

proc example4() =
  echo "==== Example 4: Combining Different Monads ===="
  
  # We'll demonstrate how to work with multiple monads together
  
  # A simple JSON parser that uses Result monad
  proc parseJsonSafe(input: string): Result[JsonNode, string] =
    try:
      let node = parseJson(input)
      success[JsonNode, string](node)
    except JsonParsingError:
      failure[JsonNode, string]("Invalid JSON syntax")
  
  # Extract a field from JSON using Maybe monad
  proc getField(node: JsonNode, field: string): Maybe[JsonNode] =
    if node.kind == JObject and node.hasKey(field):
      just(node[field])
    else:
      nothing[JsonNode]()
  
  # Extract a string value from JSON
  proc getStringValue(node: JsonNode): Maybe[string] =
    if node.kind == JString:
      just(node.getStr)
    else:
      nothing[string]()
  
  # Extract an int value from JSON
  proc getIntValue(node: JsonNode): Maybe[int] =
    if node.kind == JInt:
      just(node.getInt)
    else:
      nothing[int]()
  
  # Process a sequence of JSON strings
  let jsonInputs = @[
    """{"name": "Alice", "age": 30, "city": "New York"}""",
    """{"name": "Bob", "city": "San Francisco"}""",
    """{"name": "Charlie", "age": "twenty-five", "city": "Boston"}""",
    """invalid json""",
    """{"name": "Diana", "age": 28}"""
  ]
  
  # We'll use State monad to accumulate results as we process the JSON strings
  type JsonProcessState = object
    validCount: int
    errorCount: int
    results: seq[string]
    
  proc processJson(input: string): State[JsonProcessState, EmptyType] =
    state(proc(s: JsonProcessState): tuple[value: EmptyType, state: JsonProcessState] =
      var newState = s
      
      # Parse the JSON using Result monad
      let parseResult = parseJsonSafe(input)
      
      # Process the Result monad
      let outputMsg = parseResult.fold(
        proc(json: JsonNode): string =
          # Got valid JSON, now use Maybe monad to extract name and age
          let nameResult = getField(json, "name")
            .flatMap(getStringValue)
          
          let ageResult = getField(json, "age")
            .flatMap(getIntValue)
          
          # Build a message based on what we extracted
          let name = nameResult.getOrElse("Unknown")
          if ageResult.isSome:
            newState.validCount += 1
            fmt"Valid: {name}, Age: {ageResult.get}"
          else:
            newState.errorCount += 1
            fmt"Partial: {name}, missing or invalid age"
        ,
        proc(err: string): string =
          newState.errorCount += 1
          fmt"Error: {err}"
      )
      
      # Add the result to our state
      newState.results.add(outputMsg)
      
      # Return the updated state
      ((), newState)
    )
  
  # Process each JSON string and accumulate results
  let initialState = JsonProcessState(validCount: 0, errorCount: 0, results: @[])
  
  # Create a State monad for the full sequence
  var fullProcess = state(proc(s: JsonProcessState): tuple[value: EmptyType, state: JsonProcessState] = 
    ((), s)
  )
  
  # Chain all the JSON processing operations
  for i in 0..<jsonInputs.len:
    let input = jsonInputs[i]  # Create a copy of the input string
    fullProcess = fullProcess.flatMap(proc(_: EmptyType): State[JsonProcessState, EmptyType] =
      processJson(input)
    )
  
  # Add a final step to get a summary
  let finalProcess = fullProcess.flatMap(proc(_: EmptyType): State[JsonProcessState, string] =
    state(proc(s: JsonProcessState): tuple[value: string, state: JsonProcessState] =
      let summary = fmt"Processed {s.validCount + s.errorCount} JSON inputs: {s.validCount} valid, {s.errorCount} with errors"
      (summary, s)
    )
  )
  
  # Run the full process
  let (summary, finalState) = runState(finalProcess, initialState)
  
  # Print the results
  echo "JSON Processing Results:"
  for i, result in finalState.results:
    echo fmt"[{i+1}] {result}"
  
  echo "\nSummary:"
  echo summary

# Run all examples
when isMainModule:
  example1()
  echo "\n"
  example2()
  echo "\n"
  example3()
  echo "\n"
  example4()