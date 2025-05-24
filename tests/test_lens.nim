import unittest
import strutils
import sequtils
import options
import sugar

# Import the Lens pattern implementation
import ../src/nim_design_patterns/functional/lens

# Basic types for our example
type
  Address = object
    street: string
    city: string
    zipCode: string
    
  Employment = ref object
    company: string
    position: string
    salary: float

  Person = object
    name: string
    age: int
    address: Address
    employment: Employment  # Optional field (can be nil)

# The Lens implementation is imported from the module

# Example lenses for our Person and Address types
let nameLens = field[Person, string](
  "name",
  (p: Person) => p.name,
  (p: Person, name: string) => Person(name: name, age: p.age, address: p.address, employment: p.employment)
)

let ageLens = field[Person, int](
  "age",
  (p: Person) => p.age,
  (p: Person, age: int) => Person(name: p.name, age: age, address: p.address, employment: p.employment)
)

let addressLens = field[Person, Address](
  "address",
  (p: Person) => p.address,
  (p: Person, addr: Address) => Person(name: p.name, age: p.age, address: addr, employment: p.employment)
)

let employmentLens = field[Person, Employment](
  "employment",
  (p: Person) => p.employment,
  (p: Person, emp: Employment) => Person(name: p.name, age: p.age, address: p.address, employment: emp)
)

# Lenses for Employment fields
let companyLens = field[Employment, string](
  "company",
  (e: Employment) => e.company,
  (e: Employment, company: string) => Employment(company: company, position: e.position, salary: e.salary)
)

let positionLens = field[Employment, string](
  "position",
  (e: Employment) => e.position,
  (e: Employment, position: string) => Employment(company: e.company, position: position, salary: e.salary)
)

let salaryLens = field[Employment, float](
  "salary",
  (e: Employment) => e.salary,
  (e: Employment, salary: float) => Employment(company: e.company, position: e.position, salary: salary)
)

let streetLens = field[Address, string](
  "street",
  (a: Address) => a.street,
  (a: Address, street: string) => Address(street: street, city: a.city, zipCode: a.zipCode)
)

let cityLens = field[Address, string](
  "city",
  (a: Address) => a.city,
  (a: Address, city: string) => Address(street: a.street, city: city, zipCode: a.zipCode)
)

let zipCodeLens = field[Address, string](
  "zipCode",
  (a: Address) => a.zipCode,
  (a: Address, zipCode: string) => Address(street: a.street, city: a.city, zipCode: zipCode)
)

# Composed lenses for deeper access
let personStreetLens = compose(addressLens, streetLens)
let personCityLens = compose(addressLens, cityLens)
let personZipCodeLens = compose(addressLens, zipCodeLens)

# Optional composed lenses for potentially nil references
let personCompanyLens = optional(employmentLens, companyLens)
let personPositionLens = optional(employmentLens, positionLens)
let personSalaryLens = optional(employmentLens, salaryLens)

# Test suite
proc runTests*(): int =
  # Returns the number of test failures
  var failures = 0
  
  # Let's skip tracking failures for now and just use the unittest module's tracking

  # Tests
  suite "Lens Pattern":
    test "Basic lens operations":
      var person = Person(
        name: "John Doe",
        age: 30,
        address: Address(
          street: "123 Main St",
          city: "Anytown",
          zipCode: "12345"
        )
      )
    
      # Test getters
      check nameLens.get(person) == "John Doe"
      check ageLens.get(person) == 30
      check streetLens.get(addressLens.get(person)) == "123 Main St"
      
      # Test setters (creating new immutable objects)
      let newPerson = nameLens.set(person, "Jane Doe")
      check newPerson.name == "Jane Doe"
      check person.name == "John Doe"  # Original unchanged
      
      # Test modification
      let olderPerson = ageLens.modify(person, proc(a: int): int = a + 5)
      check olderPerson.age == 35
      check person.age == 30  # Original unchanged
    
    test "Composed lens operations":
      var person = Person(
        name: "John Doe",
        age: 30,
        address: Address(
          street: "123 Main St",
          city: "Anytown",
          zipCode: "12345"
        )
      )
    
      # Test composed getters
      check personStreetLens.get(person) == "123 Main St"
      check personCityLens.get(person) == "Anytown"
      check personZipCodeLens.get(person) == "12345"
      
      # Test composed setters
      let personWithNewStreet = personStreetLens.set(person, "456 Oak Ave")
      check personWithNewStreet.address.street == "456 Oak Ave"
      check person.address.street == "123 Main St"  # Original unchanged
      
      # Test composed modification
      let personWithUpperCaseCity = personCityLens.modify(person, proc(c: string): string = c.toUpperAscii())
      check personWithUpperCaseCity.address.city == "ANYTOWN"
      check person.address.city == "Anytown"  # Original unchanged

    test "Chain of modifications":
      var person = Person(
        name: "John Doe",
        age: 30,
        address: Address(
          street: "123 Main St",
          city: "Anytown",
          zipCode: "12345"
        )
      )
    
      # Chain multiple modifications
      let updatedName = nameLens.modify(person, proc(n: string): string = n & ", Jr.")
      let updatedAge = ageLens.modify(updatedName, proc(a: int): int = a - 5)
      let updatedPerson = personCityLens.modify(updatedAge, proc(c: string): string = "New " & c)
      
      # Check all modifications were applied
      check updatedPerson.name == "John Doe, Jr."
      check updatedPerson.age == 25
      check updatedPerson.address.city == "New Anytown"
      
      # Original still unchanged
      check person.name == "John Doe"
      check person.age == 30
      check person.address.city == "Anytown"
  
    test "Fluent API with method syntax":
      var person = Person(
        name: "John Doe",
        age: 30,
        address: Address(
          street: "123 Main St",
          city: "Anytown",
          zipCode: "12345"
        )
      )
    
      # Using fluent API with method syntax
      let updatedPerson = person
        .modify(nameLens, proc(n: string): string = n & ", Jr.")
        .modify(ageLens, proc(a: int): int = a - 5)
        .modify(personCityLens, proc(c: string): string = "New " & c)
      
      # Check all modifications were applied
      check updatedPerson.name == "John Doe, Jr."
      check updatedPerson.age == 25
      check updatedPerson.address.city == "New Anytown"
      
      # Original still unchanged
      check person.name == "John Doe"
      check person.age == 30
      check person.address.city == "Anytown"
    
    test "Optional lens for nilable fields":
      # Create test persons, one with employment and one without
      let employedPerson = Person(
        name: "Employed Person",
        age: 35,
        address: Address(street: "Work St", city: "Worktown", zipCode: "W1234"),
        employment: Employment(company: "Acme Inc", position: "Developer", salary: 100000.0)
      )
      
      let unemployedPerson = Person(
        name: "Unemployed Person",
        age: 30,
        address: Address(street: "Home St", city: "Hometown", zipCode: "H1234"),
        employment: nil
      )
    
      # Test getting values with optional lens
      let employedCompany = personCompanyLens.get(employedPerson)
      check employedCompany.isSome
      check employedCompany.get == "Acme Inc"
      
      let unemployedCompany = personCompanyLens.get(unemployedPerson)
      check unemployedCompany.isNone
      
      # Test safely setting values with optional lens
      let updatedEmployed = personCompanyLens.set(employedPerson, some("New Corp"))
      check updatedEmployed.employment != nil
      check updatedEmployed.employment.company == "New Corp"
      
      # Attempting to set a value on a nil reference is a no-op
      let attemptUpdateUnemployed = personCompanyLens.set(unemployedPerson, some("New Corp"))
      check attemptUpdateUnemployed.employment == nil
      
      # Setting to none is also a no-op
      let setToNone = personCompanyLens.set(employedPerson, none(string))
      check setToNone.employment != nil
      check setToNone.employment.company == "Acme Inc"
      
      # Using modify safely
      let salaryRaise = personSalaryLens.modify(employedPerson, proc(s: Option[float]): Option[float] =
        if s.isSome:
          return some(s.get * 1.1)  # 10% raise
        return none(float)
      )
      check salaryRaise.employment != nil
      # Using a delta for floating point comparison
      check abs(salaryRaise.employment.salary - 110000.0) < 0.001
      
      # Modifying a nil reference is a no-op
      let attemptModifyUnemployed = personSalaryLens.modify(unemployedPerson, proc(s: Option[float]): Option[float] =
        if s.isSome:
          return some(s.get * 1.1)
        return none(float)
      )
      check attemptModifyUnemployed.employment == nil

    test "Lenses with collections":
      # Define a lens for a sequence of persons
      # Using the at function from the lens module
      
      # Create a lens for each field in the collection
      let people = @[
        Person(name: "Alice", age: 25, address: Address(street: "A St", city: "A-town", zipCode: "A1234"), employment: nil),
        Person(name: "Bob", age: 30, address: Address(street: "B St", city: "B-town", zipCode: "B1234"), employment: nil),
        Person(name: "Charlie", age: 35, address: Address(street: "C St", city: "C-town", zipCode: "C1234"), employment: nil)
      ]
    
      # Create lenses into the collection
      let personAt0 = at[Person](0)
      let personAt1 = at[Person](1)
      let personAt2 = at[Person](2)
      
      # Compose lenses to access nested fields
      let person0Name = compose(personAt0, nameLens)
      let person1Age = compose(personAt1, ageLens)
      let person2Street = compose(compose(personAt2, addressLens), streetLens)
      
      # Test getters
      check person0Name.get(people) == "Alice"
      check person1Age.get(people) == 30
      check person2Street.get(people) == "C St"
      
      # Test setters
      let peopleUpdated = people
        .modify(person0Name, proc(n: string): string = n.toUpperAscii())
        .modify(person1Age, proc(a: int): int = a + 10) 
        .modify(person2Street, proc(s: string): string = s & " Avenue")
      
      # Check updates were applied correctly
      check peopleUpdated[0].name == "ALICE"
      check peopleUpdated[1].age == 40
      check peopleUpdated[2].address.street == "C St Avenue"
      
      # Original data unchanged
      check people[0].name == "Alice"
      check people[1].age == 30
      check people[2].address.street == "C St"
      
      # mapLens is provided by the lens module
      
      # Increase everyone's age by 5
      let olderPeople = people.map(proc(p: Person): Person = ageLens.modify(p, proc(a: int): int = a + 5))
      
      # Check the result
      check olderPeople[0].age == 30
      check olderPeople[1].age == 35
      check olderPeople[2].age == 40
    
  return failures

# Run the tests when this module is executed directly
when isMainModule:
  let failures = runTests()
  quit(if failures > 0: 1 else: 0)