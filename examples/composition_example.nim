## Function Composition Pattern Example
## 
## This example demonstrates the use of the Function Composition pattern for
## creating data transformation pipelines and point-free style programming.

import ../src/nim_design_patterns/functional/composition
import sugar
import strutils
import tables
import json
import options
import strformat

# Example 1: Text Processing Pipeline
# ---------------------------------------------------------------------------

proc example1() =
  echo "==== Example 1: Text Processing Pipeline ===="
  
  # Define simple text processing functions
  let 
    trim = (s: string) => s.strip()
    toLowerCase = (s: string) => s.toLowerAscii()
    replaceSpaces = (s: string) => s.replace(" ", "_")
    truncateAt20 = (s: string) => (if s.len > 20: s[0..19] else: s)
  
  # Combine these functions in different ways using composition
  let 
    normalizeText = compose(toLowerCase, trim)
    slugify = compose(replaceSpaces, normalizeText)
    createId = compose(truncateAt20, slugify)
  
  # Process some example text
  let userInput = "   Hello World! This is a Test String   "
  
  echo "Original text: \"", userInput, "\""
  echo "Normalized:    \"", normalizeText(userInput), "\""
  echo "Slugified:     \"", slugify(userInput), "\""
  echo "ID:            \"", createId(userInput), "\""
  
  # Using the pipeline operator for a cleaner syntax
  echo "Pipeline:      \"", userInput |> trim |> toLowerCase |> replaceSpaces |> truncateAt20, "\""

# Example 2: Data Transformation with Records
# ---------------------------------------------------------------------------

proc example2() =
  echo "\n==== Example 2: Data Transformation with Records ===="
  
  # Define a user record type
  type User = object
    id: int
    name: string
    email: string
    age: int
    isActive: bool
  
  # Create some sample users
  let users = @[
    User(id: 1, name: "Alice Smith", email: "alice@example.com", age: 32, isActive: true),
    User(id: 2, name: "Bob Johnson", email: "bob@example.com", age: 45, isActive: false),
    User(id: 3, name: "Charlie Brown", email: "charlie@example.com", age: 27, isActive: true),
    User(id: 4, name: "Diana Williams", email: "diana@example.com", age: 19, isActive: true),
    User(id: 5, name: "Edward Davis", email: "edward@example.com", age: 52, isActive: false)
  ]
  
  # Define transformation functions
  let 
    isActive = (user: User) => user.isActive
    isAdult = (user: User) => user.age >= 18
    formatName = (user: User) => fmt"{user.name} ({user.age})"
    getEmail = (user: User) => user.email
  
  # Create composed predicates
  let 
    isActiveAdult = all(isActive, isAdult)
    isInactiveOrMinor = negate(isActiveAdult)
  
  # Create data transformations
  let 
    getActiveUsers = filter(isActive)
    getAdultUsers = filter(isAdult)
    getActiveAdultUsers = filter(isActiveAdult)
    getInactiveOrMinorUsers = filter(isInactiveOrMinor)
    
    formatUserNames = map(formatName)
    getUserEmails = map(getEmail)
  
  # Apply transformations to the data
  echo "All users: ", users.len
  
  let 
    activeUsers = getActiveUsers(users)
    adultUsers = getAdultUsers(users)
    activeAdultUsers = getActiveAdultUsers(users)
    
    formattedActiveAdults = activeAdultUsers |> formatUserNames
    activeAdultEmails = activeAdultUsers |> getUserEmails
  
  echo "Active users: ", activeUsers.len
  echo "Adult users: ", adultUsers.len
  echo "Active adult users: ", activeAdultUsers.len
  echo "Formatted active adults: ", formattedActiveAdults
  echo "Active adult emails: ", activeAdultEmails
  
  # Complex pipeline: Get names of active adults sorted by length
  let byNameLength = (a, b: string) => a.len < b.len
  
  let sortedNames = users 
    |> getActiveAdultUsers 
    |> formatUserNames
  
  echo "Active adults sorted by name length: ", sortedNames

# Example 3: JSON Processing with Composition
# ---------------------------------------------------------------------------

proc example3() =
  echo "\n==== Example 3: JSON Processing with Composition ===="
  
  # Sample JSON data
  let jsonStr = """
  {
    "users": [
      {"id": 1, "name": "Alice", "roles": ["admin", "user"], "active": true, "score": 95},
      {"id": 2, "name": "Bob", "roles": ["user"], "active": true, "score": 85},
      {"id": 3, "name": "Charlie", "roles": ["moderator", "user"], "active": false, "score": 75},
      {"id": 4, "name": "Diana", "roles": ["user"], "active": true, "score": 92},
      {"id": 5, "name": "Edward", "roles": ["guest"], "active": false, "score": 60}
    ]
  }
  """
  
  # Define helper functions for JSON processing
  proc parseJson(s: string): JsonNode =
    try:
      result = json.parseJson(s)
    except JsonParsingError:
      result = newJObject()
  
  proc getUsers(json: JsonNode): seq[JsonNode] =
    if json.hasKey("users") and json["users"].kind == JArray:
      result = @[]
      for user in json["users"]:
        result.add(user)
    else:
      result = @[]
  
  # Define transformations on JSON users
  let 
    isActive = (user: JsonNode) => 
      user.hasKey("active") and user["active"].getBool
    
    isAdmin = (user: JsonNode) =>
      user.hasKey("roles") and user["roles"].kind == JArray and
      user["roles"].getElems.anyIt(it.getStr == "admin")
    
    highScore = (user: JsonNode) =>
      user.hasKey("score") and user["score"].getInt >= 90
    
    getUserName = (user: JsonNode) =>
      if user.hasKey("name"): user["name"].getStr else: "<unknown>"
    
    getUserScore = (user: JsonNode) =>
      if user.hasKey("score"): user["score"].getInt else: 0
  
  # Create complex filters
  let 
    isActiveAdmin = all(isActive, isAdmin)
    isActiveHighScorer = all(isActive, highScore)
  
  # Create transformations
  let 
    getActiveUsers = filter(isActive)
    getAdmins = filter(isAdmin)
    getHighScorers = filter(highScore)
    getActiveAdmins = filter(isActiveAdmin)
    getActiveHighScorers = filter(isActiveHighScorer)
    
    getUserNames = map(getUserName)
    getUserScores = map(getUserScore)
  
  # Create the pipeline
  let 
    pipeline = parseJson |>> getUsers
    adminNamesPipeline = pipeline |>> getAdmins |>> getUserNames
    highScorersPipeline = pipeline |>> getHighScorers |>> getUserNames
    
    jsonUsers = pipeline(jsonStr)
    adminNames = adminNamesPipeline(jsonStr)
    highScorerNames = highScorersPipeline(jsonStr)
  
  echo "Total users: ", jsonUsers.len
  echo "Admin names: ", adminNames
  echo "High scorer names: ", highScorerNames
  
  # Reduce to get average score of active users
  let 
    sumScores = (acc: tuple[total: int, count: int], user: JsonNode) =>
      if isActive(user):
        (acc.total + getUserScore(user), acc.count + 1)
      else:
        acc
    
    getAverageScore = (data: seq[JsonNode]) =>
      let result = reduce(sumScores, (0, 0))(data)
      if result.count > 0: result.total / result.count else: 0
  
  echo "Average score of active users: ", getAverageScore(jsonUsers)

# Example 4: Option Handling with Composition
# ---------------------------------------------------------------------------

proc example4() =
  echo "\n==== Example 4: Option Handling with Composition ===="
  
  # Define a record type
  type 
    Address = ref object
      street: string
      city: string
      zipCode: string
    
    User = ref object
      id: int
      name: string
      email: string
      address: Option[Address]
      preferences: Option[Table[string, string]]
  
  # Create sample users
  let users = @[
    User(
      id: 1, 
      name: "Alice", 
      email: "alice@example.com",
      address: some(Address(street: "123 Main St", city: "Metropolis", zipCode: "12345")),
      preferences: some({"theme": "dark", "language": "en"}.toTable)
    ),
    User(
      id: 2, 
      name: "Bob", 
      email: "bob@example.com",
      address: none(Address),
      preferences: some({"theme": "light", "notifications": "off"}.toTable)
    ),
    User(
      id: 3, 
      name: "Charlie", 
      email: "charlie@example.com",
      address: some(Address(street: "456 Oak Ave", city: "Smallville", zipCode: "67890")),
      preferences: none(Table[string, string])
    )
  ]
  
  # Define safe accessor functions
  proc getAddress(user: User): Option[Address] = user.address
  
  proc getCity(address: Address): string = address.city
  
  proc getCityOption(addressOpt: Option[Address]): Option[string] =
    if addressOpt.isSome:
      some(addressOpt.get.city)
    else:
      none(string)
  
  proc getPreference(user: User, key: string): Option[string] =
    if user.preferences.isSome and user.preferences.get.hasKey(key):
      some(user.preferences.get[key])
    else:
      none(string)
  
  # Create composed functions
  proc getUserCity(user: User): Option[string] =
    getCityOption(getAddress(user))
  
  proc getUserTheme(user: User): Option[string] =
    getPreference(user, "theme")
  
  # Process the users
  echo "User cities:"
  for user in users:
    let cityOpt = getUserCity(user)
    echo fmt"  {user.name}: {if cityOpt.isSome: cityOpt.get else: 'Unknown'}"
  
  echo "User themes:"
  for user in users:
    let themeOpt = getUserTheme(user)
    echo fmt"  {user.name}: {if themeOpt.isSome: themeOpt.get else: 'Default'}"
  
  # Optional chaining-like behavior with composition
  proc formatAddress(address: Address): string =
    fmt"{address.street}, {address.city} {address.zipCode}"
  
  proc formatAddressOption(addressOpt: Option[Address]): string =
    if addressOpt.isSome:
      formatAddress(addressOpt.get)
    else:
      "No address"
  
  let getFormattedAddress = (user: User) => formatAddressOption(user.address)
  
  echo "Formatted addresses:"
  for user in users:
    echo fmt"  {user.name}: {getFormattedAddress(user)}"

# Run all examples
when isMainModule:
  example1()
  example2()
  example3()
  example4()