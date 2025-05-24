## Test runner with integrated reporting
## Captures test results and generates reports in multiple formats

import std/[unittest, os, strutils, times, tables, json, sequtils]
import ../src/nim_design_patterns/core/base
import test_reporter

type
  TestRunner* = ref object
    reporter: TestReporter
    currentSuite: string
    testResults: Table[string, seq[TestResult]]
    startTime: DateTime

proc newTestRunner*(outputDir: string = "test-reports"): TestRunner =
  ## Create a new test runner with integrated reporting
  createDir(outputDir)
  result = TestRunner(
    reporter: newTestReporter(),
    testResults: initTable[string, seq[TestResult]](),
    startTime: now()
  )

proc beginSuite*(runner: TestRunner, name: string) =
  ## Mark the beginning of a test suite
  runner.currentSuite = name
  if name notin runner.testResults:
    runner.testResults[name] = @[]

proc recordTest*(runner: TestRunner, name: string, passed: bool, 
                 duration: Duration, message: string = "") =
  ## Record a test result
  let result = TestResult(
    name: name,
    suite: runner.currentSuite,
    passed: passed,
    duration: duration,
    message: message,
    timestamp: now()
  )
  
  if runner.currentSuite notin runner.testResults:
    runner.testResults[runner.currentSuite] = @[]
  
  runner.testResults[runner.currentSuite].add(result)
  runner.reporter.addResult(result)

proc generateReports*(runner: TestRunner, outputDir: string = "test-reports") =
  ## Generate all report formats
  echo "\nGenerating test reports..."
  
  # Console output
  runner.reporter.printConsoleReport()
  
  # File reports
  let timestamp = now().format("yyyyMMdd'_'HHmmss")
  
  # JUnit XML
  let junitPath = outputDir / &"junit_{timestamp}.xml"
  runner.reporter.generateJUnitReport(junitPath)
  echo &"  JUnit report: {junitPath}"
  
  # HTML
  let htmlPath = outputDir / &"report_{timestamp}.html"
  runner.reporter.generateHtmlReport(htmlPath)
  echo &"  HTML report: {htmlPath}"
  
  # Markdown
  let mdPath = outputDir / &"report_{timestamp}.md"
  runner.reporter.generateMarkdownReport(mdPath)
  echo &"  Markdown report: {mdPath}"
  
  # JSON
  let jsonPath = outputDir / &"report_{timestamp}.json"
  runner.reporter.generateJsonReport(jsonPath)
  echo &"  JSON report: {jsonPath}"

# Test execution helpers
template runTest*(runner: TestRunner, testName: string, body: untyped) =
  ## Run a test and record its result
  let startTime = now()
  var passed = false
  var message = ""
  
  try:
    body
    passed = true
  except AssertionDefect as e:
    message = e.msg
  except Exception as e:
    message = &"Unexpected error: {e.msg}"
  
  let duration = now() - startTime
  runner.recordTest(testName, passed, duration, message)

# Integration with unittest
proc captureUnittestResults*(runner: TestRunner) =
  ## Capture results from unittest execution
  # This is a placeholder - in a real implementation, we would hook into
  # unittest's internals or parse its output
  discard

when isMainModule:
  # Example usage
  let runner = newTestRunner()
  
  runner.beginSuite("Example Tests")
  
  runner.runTest("test addition"):
    assert 1 + 1 == 2
  
  runner.runTest("test string concat"):
    assert "hello" & " world" == "hello world"
  
  runner.runTest("test failure"):
    assert 1 == 2  # This will fail
  
  runner.generateReports()