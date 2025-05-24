## Immutability Pattern Example
##
## This example demonstrates the use of immutable data structures for maintaining
## application state in a predictable and thread-safe manner.

import std/[hashes, tables, sets, strformat, times, strutils]
import ../src/nim_design_patterns/functional/immutability

# Example 1: Using ImmutableList for a transaction history log
# ---------------------------------------------------------

type Transaction = object
  id: string
  timestamp: DateTime
  amount: float
  description: string

proc newTransaction(id: string, amount: float, description: string): Transaction =
  Transaction(
    id: id,
    timestamp: now(),
    amount: amount,
    description: description
  )

# Create an immutable transaction log
var transactionLog = empty[Transaction]()

# Add transactions (creates new lists each time)
transactionLog = cons(newTransaction("tx1", 100.0, "Deposit"), transactionLog)
transactionLog = cons(newTransaction("tx2", -50.0, "Withdrawal"), transactionLog)
transactionLog = cons(newTransaction("tx3", 25.0, "Refund"), transactionLog)

# Process transactions without modifying the original log
let positiveTransactions = filter(transactionLog, proc(tx: Transaction): bool = tx.amount > 0)
let totalDeposits = foldLeft(positiveTransactions, 0.0, proc(acc: float, tx: Transaction): float = acc + tx.amount)

echo "Transaction Log Example:"
echo "------------------------"
echo "Total number of transactions: " & $transactionLog.toSeq().len
echo "Positive transactions: " & $positiveTransactions.toSeq().len
echo "Total deposits: $" & formatFloat(totalDeposits, ffDecimal, 2)
echo ""

# Example 2: Using ImmutableMap for a user preferences system
# ---------------------------------------------------------

# Initial user preferences
var userPrefs = emptyMap[string, string]()
userPrefs = put(userPrefs, "theme", "dark")
userPrefs = put(userPrefs, "fontSize", "12")
userPrefs = put(userPrefs, "showNotifications", "true")

# Create a new preferences object based on user changes
let updatedPrefs = put(userPrefs, "fontSize", "14")

echo "User Preferences Example:"
echo "------------------------"
echo "Initial preferences:"
for k in userPrefs.keys():
  echo fmt"  {k}: {userPrefs.get(k)}"

echo "Updated preferences (note original is unchanged):"
for k in updatedPrefs.keys():
  echo fmt"  {k}: {updatedPrefs.get(k)}"
echo ""

# Example 3: Using ImmutableSet for a tag system
# ---------------------------------------------------------

# Create a set of tags for an article
var articleTags = emptySet[string]()
articleTags = add(articleTags, "programming")
articleTags = add(articleTags, "nim")
articleTags = add(articleTags, "functional")

# User adds a tag
let userTags = add(articleTags, "immutability")

# Recommended tags (another set)
var recommendedTags = emptySet[string]()
recommendedTags = add(recommendedTags, "functional")
recommendedTags = add(recommendedTags, "patterns")
recommendedTags = add(recommendedTags, "design")

# Find union of all tags
let allTags = union(userTags, recommendedTags)

# Find common tags
let commonTags = intersection(articleTags, recommendedTags)

echo "Tag System Example:"
echo "------------------------"
echo "Article tags: " & articleTags.toSeq().join(", ")
echo "User tags: " & userTags.toSeq().join(", ")
echo "Recommended tags: " & recommendedTags.toSeq().join(", ")
echo "All tags: " & allTags.toSeq().join(", ")
echo "Common tags: " & commonTags.toSeq().join(", ")
echo ""

# Example 4: Immutable data processing pipeline
# ---------------------------------------------------------

# Create an initial user record
type UserRecord = object
  name: string
  age: int
  isPremium: bool
  loginCount: int
  createdAt: DateTime

var users = empty[UserRecord]()

# Add some user records
users = cons(UserRecord(name: "Alice", age: 28, isPremium: true, loginCount: 42, createdAt: now() - initDuration(days = 100)), users)
users = cons(UserRecord(name: "Bob", age: 35, isPremium: false, loginCount: 5, createdAt: now() - initDuration(days = 5)), users)
users = cons(UserRecord(name: "Charlie", age: 22, isPremium: true, loginCount: 20, createdAt: now() - initDuration(days = 30)), users)
users = cons(UserRecord(name: "David", age: 45, isPremium: false, loginCount: 1, createdAt: now() - initDuration(days = 1)), users)

# Processing pipeline using immutable operations
let premiumUsers = filter(users, proc(u: UserRecord): bool = u.isPremium)
let activeUsers = filter(users, proc(u: UserRecord): bool = u.loginCount > 10)
let recentUsers = filter(users, proc(u: UserRecord): bool = 
  (now() - u.createdAt) < initDuration(days = 7)
)

let userNames = map(users, proc(u: UserRecord): string = u.name)

echo "Data Processing Pipeline Example:"
echo "--------------------------------"
echo "All users: " & userNames.toSeq().join(", ")
echo "Premium users: " & map(premiumUsers, proc(u: UserRecord): string = u.name).toSeq().join(", ")
echo "Active users: " & map(activeUsers, proc(u: UserRecord): string = u.name).toSeq().join(", ")
echo "Recent users: " & map(recentUsers, proc(u: UserRecord): string = u.name).toSeq().join(", ")
echo ""

# Example 5: Using immutability with non-destructive updates on sequences
# ----------------------------------------------------------------------

type Todo = object
  id: int
  task: string
  completed: bool

# Initial todo list
let todos = @[
  Todo(id: 1, task: "Buy groceries", completed: false),
  Todo(id: 2, task: "Finish project", completed: false),
  Todo(id: 3, task: "Call mom", completed: true),
  Todo(id: 4, task: "Exercise", completed: false)
]

# Mark a task as completed (non-destructively)
let updatedTodos = modify(todos, 1, Todo(id: 2, task: "Finish project", completed: true))

# Add a new todo (non-destructively)
let expandedTodos = insertAt(todos, todos.len, Todo(id: 5, task: "Read book", completed: false))

# Remove a todo (non-destructively)
let reducedTodos = remove(todos, 0)

echo "Todo List Example:"
echo "----------------"
echo "Original todos:"
for todo in todos:
  echo "  [" & (if todo.completed: "x" else: " ") & "] " & todo.task

echo "After marking 'Finish project' as completed:"
for todo in updatedTodos:
  echo "  [" & (if todo.completed: "x" else: " ") & "] " & todo.task

echo "After adding a new todo:"
for todo in expandedTodos:
  echo "  [" & (if todo.completed: "x" else: " ") & "] " & todo.task

echo "After removing the first todo:"
for todo in reducedTodos:
  echo "  [" & (if todo.completed: "x" else: " ") & "] " & todo.task