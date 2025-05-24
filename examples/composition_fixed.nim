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

# Run the example
when isMainModule:
  example1()