## Main test runner that executes all tests and generates reports
## This wraps the existing unittest-based tests

import std/[os, osproc, strutils, json, times, sequtils, strformat]
import test_reporter
export test_reporter

type
  TestExecutor* = object
    reporter: TestReporter
    outputDir: string

proc parseTestOutput(output: string): seq[TestResult] =
  ## Parse unittest output to extract test results
  result = @[]
  var currentSuite = "default"
  let lines = output.splitLines()
  
  for line in lines:
    # Parse suite names
    if line.startsWith("[Suite]"):
      currentSuite = line[7..^1].strip()
    # Parse test results - unittest format
    elif line.contains("[OK]") or line.contains("[FAILED]"):
      let passed = line.contains("[OK]")
      var testName = line
      if line.contains("[OK]"):
        testName = line.replace("[OK]", "").strip()
      elif line.contains("[FAILED]"):
        testName = line.replace("[FAILED]", "").strip()
      
      let duration = initDuration(milliseconds = 10) # Default duration
      
      result.add(TestResult(
        name: testName,
        suite: currentSuite,
        status: if passed: tsPass else: tsFail,
        duration: duration.inMilliseconds.float / 1000.0,
        message: if not passed: "Test failed" else: "",
        stackTrace: ""
      ))
    # Also check for simpler test output format
    elif line.contains("test") and (line.contains("passed") or line.contains("failed")):
      let passed = line.contains("passed")
      let testName = if line.contains(":"):
        line.split(":")[0].strip()
      else:
        line.strip()
      
      result.add(TestResult(
        name: testName,
        suite: currentSuite,
        status: if passed: tsPass else: tsFail,
        duration: 0.01,  # Default 10ms
        message: if not passed: line else: "",
        stackTrace: ""
      ))

proc executeTest(executor: var TestExecutor, testFile: string): bool =
  ## Execute a single test file and capture results
  echo &"\nRunning {testFile}..."
  
  let cmd = &"nim c -r --hints:off --warnings:off {testFile}"
  let (output, exitCode) = execCmdEx(cmd)
  
  # Parse and record results
  let results = parseTestOutput(output)
  for result in results:
    executor.reporter.addResult(result)
  
  # Also save raw output
  let outputFile = executor.outputDir / &"{testFile.splitFile.name}_output.txt"
  writeFile(outputFile, output)
  
  return exitCode == 0

proc runAllTests*(outputDir: string = "test-reports") =
  ## Run all tests and generate reports
  var executor = TestExecutor(
    reporter: newTestReporter(),
    outputDir: outputDir
  )
  
  createDir(outputDir)
  
  # Find all test files
  let testFiles = @[
    "tests/test_factory.nim",
    "tests/test_strategy.nim",
    "tests/test_observer.nim",
    "tests/test_lazy.nim",
    "tests/test_immutability.nim",
    "tests/test_composition.nim",
    "tests/test_monad.nim",
    "tests/test_transducer.nim",
    "tests/test_future.nim",
    "tests/test_statemachine.nim",
    "tests/test_circuit_breaker.nim",
    "tests/test_saga.nim",
    "tests/test_executor.nim",
    "tests/test_checks_effects_interactions.nim"
  ]
  
  echo "Running test suite with integrated reporting..."
  echo &"Output directory: {outputDir}"
  
  var allPassed = true
  for testFile in testFiles:
    if fileExists(testFile):
      if not executor.executeTest(testFile):
        allPassed = false
    else:
      echo &"  Skipping {testFile} (not found)"
  
  # Generate reports
  echo "\nGenerating test reports..."
  
  # Console report
  executor.reporter.printConsoleReport()
  
  # File reports
  let timestamp = now().format("yyyyMMdd'_'HHmmss")
  
  # JUnit XML
  let junitPath = outputDir / &"junit_{timestamp}.xml"
  executor.reporter.generateJUnitReport(junitPath)
  echo &"  JUnit report: {junitPath}"
  
  # HTML
  let htmlPath = outputDir / &"report_{timestamp}.html"
  executor.reporter.generateHtmlReport(htmlPath)
  echo &"  HTML report: {htmlPath}"
  
  # Markdown
  let mdPath = outputDir / &"report_{timestamp}.md"
  executor.reporter.generateMarkdownReport(mdPath)
  echo &"  Markdown report: {mdPath}"
  
  # JSON
  let jsonPath = outputDir / &"report_{timestamp}.json"
  executor.reporter.generateJsonReport(jsonPath)
  echo &"  JSON report: {jsonPath}"
  
  # Coverage report integration
  if existsEnv("COVERAGE"):
    echo "\nGenerating coverage report..."
    let coverageCmd = "lcov --capture --directory . --output-file coverage.info"
    let (_, coverageExit) = execCmdEx(coverageCmd)
    if coverageExit == 0:
      let genHtmlCmd = "genhtml coverage.info --output-directory " & outputDir / "coverage"
      discard execCmdEx(genHtmlCmd)
      echo &"  Coverage report: {outputDir}/coverage/index.html"
  
  if not allPassed:
    quit(1)

when isMainModule:
  import std/parseopt
  
  var outputDir = "test-reports"
  
  # Parse command line arguments
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      if p.key == "output" or p.key == "o":
        outputDir = p.val
    of cmdArgument:
      discard
  
  runAllTests(outputDir)