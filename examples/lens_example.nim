## Lens Pattern Example
## 
## This example demonstrates the use of the Lens pattern for accessing and modifying
## nested immutable data structures.

import ../src/nim_design_patterns/functional/lens
import options, sequtils, sugar
import std/strformat

# Define our data model
type
  Address = object
    street: string
    city: string
    zipCode: string
  
  Contact = object
    email: string
    phone: string
    
  Employment = ref object
    company: string
    title: string
    salary: float
  
  Person = object
    firstName: string
    lastName: string
    age: int
    address: Address
    contact: Contact
    employment: Employment  # Optional field (can be nil)

# Create lenses for each field in Person
let firstNameLens = field[Person, string](
  "firstName",
  (p: Person) => p.firstName,
  (p: Person, v: string) => Person(
    firstName: v, lastName: p.lastName, age: p.age, 
    address: p.address, contact: p.contact, employment: p.employment
  )
)

let lastNameLens = field[Person, string](
  "lastName",
  (p: Person) => p.lastName,
  (p: Person, v: string) => Person(
    firstName: p.firstName, lastName: v, age: p.age, 
    address: p.address, contact: p.contact, employment: p.employment
  )
)

let ageLens = field[Person, int](
  "age",
  (p: Person) => p.age,
  (p: Person, v: int) => Person(
    firstName: p.firstName, lastName: p.lastName, age: v, 
    address: p.address, contact: p.contact, employment: p.employment
  )
)

let addressLens = field[Person, Address](
  "address",
  (p: Person) => p.address,
  (p: Person, v: Address) => Person(
    firstName: p.firstName, lastName: p.lastName, age: p.age, 
    address: v, contact: p.contact, employment: p.employment
  )
)

let contactLens = field[Person, Contact](
  "contact",
  (p: Person) => p.contact,
  (p: Person, v: Contact) => Person(
    firstName: p.firstName, lastName: p.lastName, age: p.age, 
    address: p.address, contact: v, employment: p.employment
  )
)

let employmentLens = field[Person, Employment](
  "employment",
  (p: Person) => p.employment,
  (p: Person, v: Employment) => Person(
    firstName: p.firstName, lastName: p.lastName, age: p.age, 
    address: p.address, contact: p.contact, employment: v
  )
)

# Create lenses for Address fields
let streetLens = field[Address, string](
  "street",
  (a: Address) => a.street,
  (a: Address, v: string) => Address(street: v, city: a.city, zipCode: a.zipCode)
)

let cityLens = field[Address, string](
  "city",
  (a: Address) => a.city,
  (a: Address, v: string) => Address(street: a.street, city: v, zipCode: a.zipCode)
)

let zipCodeLens = field[Address, string](
  "zipCode",
  (a: Address) => a.zipCode,
  (a: Address, v: string) => Address(street: a.street, city: a.city, zipCode: v)
)

# Create lenses for Contact fields
let emailLens = field[Contact, string](
  "email",
  (c: Contact) => c.email,
  (c: Contact, v: string) => Contact(email: v, phone: c.phone)
)

let phoneLens = field[Contact, string](
  "phone",
  (c: Contact) => c.phone,
  (c: Contact, v: string) => Contact(email: c.email, phone: v)
)

# Create optional lenses for Employment fields
let companyLens = field[Employment, string](
  "company",
  (e: Employment) => e.company,
  (e: Employment, v: string) => Employment(company: v, title: e.title, salary: e.salary)
)

let titleLens = field[Employment, string](
  "title",
  (e: Employment) => e.title,
  (e: Employment, v: string) => Employment(company: e.company, title: v, salary: e.salary)
)

let salaryLens = field[Employment, float](
  "salary",
  (e: Employment) => e.salary,
  (e: Employment, v: float) => Employment(company: e.company, title: e.title, salary: v)
)

# Create composed lenses for nested access
let personStreetLens = compose(addressLens, streetLens)
let personCityLens = compose(addressLens, cityLens)
let personZipLens = compose(addressLens, zipCodeLens)
let personEmailLens = compose(contactLens, emailLens)
let personPhoneLens = compose(contactLens, phoneLens)

# Create optional lenses for nilable fields
let personCompanyLens = optional(employmentLens, companyLens)
let personTitleLens = optional(employmentLens, titleLens)
let personSalaryLens = optional(employmentLens, salaryLens)

# Example data
let alice = Person(
  firstName: "Alice",
  lastName: "Smith",
  age: 30,
  address: Address(
    street: "123 Main St",
    city: "Metropolis",
    zipCode: "12345"
  ),
  contact: Contact(
    email: "alice@example.com",
    phone: "555-123-4567"
  ),
  employment: Employment(
    company: "Acme Corp",
    title: "Engineer",
    salary: 85000.0
  )
)

let bob = Person(
  firstName: "Bob",
  lastName: "Johnson",
  age: 25,
  address: Address(
    street: "456 Oak Ave",
    city: "Smallville",
    zipCode: "67890"
  ),
  contact: Contact(
    email: "bob@example.com",
    phone: "555-987-6543"
  ),
  employment: nil  # Unemployed
)

# Create a collection of people
let people = @[alice, bob]

# Helper to print person info
proc printPerson(p: Person) =
  echo fmt"Name: {p.firstName} {p.lastName}"
  echo fmt"Age: {p.age}"
  echo fmt"Address: {p.address.street}, {p.address.city} {p.address.zipCode}"
  echo fmt"Contact: {p.contact.email} / {p.contact.phone}"
  
  if p.employment != nil:
    echo fmt"Employment: {p.employment.company}, {p.employment.title}, ${p.employment.salary:.2f}"
  else:
    echo "Employment: None"
  echo ""

# Example 1: Basic lens usage
proc example1() =
  echo "==== Example 1: Basic Lens Usage ===="
  
  # Reading values with lenses
  echo fmt"First name: {firstNameLens.get(alice)}"
  echo fmt"Email: {personEmailLens.get(alice)}"
  echo fmt"Street: {personStreetLens.get(alice)}"
  
  # Creating a new object with a modified value (immutable update)
  let updatedAlice = lastNameLens.set(alice, "Williams")
  
  echo "\nOriginal person:"
  printPerson(alice)
  
  echo "Updated person:"
  printPerson(updatedAlice)

# Example 2: Chaining operations with the fluent API
proc example2() =
  echo "==== Example 2: Chaining Lens Operations ===="
  
  # Chain multiple lens operations
  let updatedAlice = alice
    .modify(firstNameLens, proc(n: string): string = n & " J.")
    .modify(ageLens, proc(a: int): int = a + 1)
    .modify(personZipLens, proc(z: string): string = "A" & z)
  
  echo "After multiple modifications:"
  printPerson(updatedAlice)

# Example 3: Using optional lenses for nilable fields
proc example3() =
  echo "==== Example 3: Optional Lenses for Nilable Fields ===="
  
  # Get employment information safely
  let aliceCompany = personCompanyLens.get(alice)
  let bobCompany = personCompanyLens.get(bob)
  
  echo "Alice's company: ", if aliceCompany.isSome: aliceCompany.get else: "None"
  echo "Bob's company: ", if bobCompany.isSome: bobCompany.get else: "None"
  
  # Give Alice a raise (safely)
  let aliceWithRaise = personSalaryLens.modify(alice, proc(s: Option[float]): Option[float] =
    if s.isSome:
      some(s.get * 1.1)  # 10% raise
    else:
      none(float)
  )
  
  echo "\nAlice after raise:"
  printPerson(aliceWithRaise)
  
  # Try to give Bob a raise (no-op because employment is nil)
  let bobWithRaise = personSalaryLens.modify(bob, proc(s: Option[float]): Option[float] =
    if s.isSome:
      some(s.get * 1.1)
    else:
      none(float)
  )
  
  echo "Bob after attempted raise (unchanged):"
  printPerson(bobWithRaise)

# Example 4: Working with collections
proc example4() =
  echo "==== Example 4: Working with Collections ===="
  
  # Create lenses into the collection
  let personAt0 = at[Person](0)
  let personAt1 = at[Person](1)
  
  # Create deep paths into the collection
  let person0EmailLens = compose(personAt0, personEmailLens)
  let person1PhoneLens = compose(personAt1, personPhoneLens)
  
  echo fmt"First person's email: {person0EmailLens.get(people)}"
  echo fmt"Second person's phone: {person1PhoneLens.get(people)}"
  
  # Update the collection (immutably)
  let updatedPeople = people
    .modify(person0EmailLens, proc(e: string): string = "alice.new@example.com")
    .modify(person1PhoneLens, proc(p: string): string = "555-NEW-NMBR")
  
  echo "\nFirst person after update:"
  printPerson(updatedPeople[0])
  
  echo "Second person after update:"
  printPerson(updatedPeople[1])
  
  echo "\nOriginal collection unchanged:"
  printPerson(people[0])
  printPerson(people[1])

# Run all examples
when isMainModule:
  example1()
  echo "\n"
  example2()
  echo "\n"
  example3()
  echo "\n"
  example4()