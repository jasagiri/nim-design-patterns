## Test Reporter - Generates test reports in various formats
##
## This module provides utilities to generate test reports including:
## - Console output with colors
## - JUnit XML format
## - HTML reports
## - Markdown reports
## - JSON reports

import std/[times, strformat, strutils, json, sequtils, os]
import std/xmltree except escape

type
  TestStatus* = enum
    tsPass = "PASS"
    tsFail = "FAIL"
    tsSkip = "SKIP"
    
  TestResult* = object
    name*: string
    suite*: string
    status*: TestStatus
    duration*: float # in seconds
    message*: string
    stackTrace*: string
    
  TestSuite* = object
    name*: string
    tests*: seq[TestResult]
    startTime*: DateTime
    endTime*: DateTime
    
  TestReport* = object
    title*: string
    suites*: seq[TestSuite]
    totalTests*: int
    passedTests*: int
    failedTests*: int
    skippedTests*: int
    totalDuration*: float
    timestamp*: DateTime
  
  TestReporter* = ref object
    results*: seq[TestResult]
    report*: TestReport

proc newTestResult*(name: string, suite: string, status: TestStatus, 
                   duration: float = 0.0, message = "", stackTrace = ""): TestResult =
  TestResult(
    name: name,
    suite: suite,
    status: status,
    duration: duration,
    message: message,
    stackTrace: stackTrace
  )

proc newTestSuite*(name: string): TestSuite =
  TestSuite(
    name: name,
    tests: @[],
    startTime: now(),
    endTime: now()
  )

proc addTest*(suite: var TestSuite, test: TestResult) =
  suite.tests.add(test)
  suite.endTime = now()

proc newTestReport*(title: string): TestReport =
  TestReport(
    title: title,
    suites: @[],
    totalTests: 0,
    passedTests: 0,
    failedTests: 0,
    skippedTests: 0,
    totalDuration: 0.0,
    timestamp: now()
  )

proc newTestReporter*(): TestReporter =
  ## Create a new test reporter
  TestReporter(
    results: @[],
    report: newTestReport("Test Report")
  )

proc addResult*(reporter: TestReporter, result: TestResult) =
  ## Add a test result to the reporter
  reporter.results.add(result)
  
  # Update report statistics
  reporter.report.totalTests += 1
  case result.status
  of tsPass:
    reporter.report.passedTests += 1
  of tsFail:
    reporter.report.failedTests += 1
  of tsSkip:
    reporter.report.skippedTests += 1
  
  reporter.report.totalDuration += result.duration

proc addSuite*(report: var TestReport, suite: TestSuite) =
  report.suites.add(suite)
  
  # Update statistics
  for test in suite.tests:
    inc(report.totalTests)
    case test.status
    of tsPass: inc(report.passedTests)
    of tsFail: inc(report.failedTests)
    of tsSkip: inc(report.skippedTests)
    report.totalDuration += test.duration

# Console Reporter
proc generateConsoleReport*(report: TestReport): string =
  result = "\n" & "=".repeat(80) & "\n"
  result &= &"TEST REPORT: {report.title}\n"
  result &= &"Generated: {report.timestamp.format(\"yyyy-MM-dd HH:mm:ss\")}\n"
  result &= "=".repeat(80) & "\n\n"
  
  # Summary
  result &= "SUMMARY:\n"
  result &= &"  Total Tests:   {report.totalTests}\n"
  result &= &"  Passed:        {report.passedTests} ({report.passedTests / report.totalTests * 100:.1f}%)\n"
  result &= &"  Failed:        {report.failedTests}\n"
  result &= &"  Skipped:       {report.skippedTests}\n"
  result &= &"  Duration:      {report.totalDuration:.3f}s\n\n"
  
  # Test suites
  for suite in report.suites:
    result &= &"Suite: {suite.name}\n"
    result &= "-".repeat(40) & "\n"
    
    for test in suite.tests:
      let statusSymbol = case test.status
        of tsPass: "✓"
        of tsFail: "✗"
        of tsSkip: "○"
      
      let statusColor = case test.status
        of tsPass: "\e[32m"  # Green
        of tsFail: "\e[31m"  # Red
        of tsSkip: "\e[33m"  # Yellow
      
      result &= &"  {statusColor}{statusSymbol}\e[0m {test.name} ({test.duration:.3f}s)\n"
      
      if test.status == tsFail and test.message != "":
        result &= &"    Error: {test.message}\n"
        if test.stackTrace != "":
          result &= &"    Stack: {test.stackTrace}\n"
    
    result &= "\n"

# JUnit XML Reporter
proc generateJUnitXML*(report: TestReport): string =
  var root = newElement("testsuites")
  root.attrs = {
    "name": report.title,
    "tests": $report.totalTests,
    "failures": $report.failedTests,
    "skipped": $report.skippedTests,
    "time": &"{report.totalDuration:.3f}",
    "timestamp": report.timestamp.format("yyyy-MM-dd'T'HH:mm:ss")
  }.toXmlAttributes
  
  for suite in report.suites:
    var suiteElem = newElement("testsuite")
    let suiteDuration = suite.tests.mapIt(it.duration).foldl(a + b, 0.0)
    let suiteFailures = suite.tests.filterIt(it.status == tsFail).len
    let suiteSkipped = suite.tests.filterIt(it.status == tsSkip).len
    
    suiteElem.attrs = {
      "name": suite.name,
      "tests": $suite.tests.len,
      "failures": $suiteFailures,
      "skipped": $suiteSkipped,
      "time": &"{suiteDuration:.3f}",
      "timestamp": suite.startTime.format("yyyy-MM-dd'T'HH:mm:ss")
    }.toXmlAttributes
    
    for test in suite.tests:
      var testElem = newElement("testcase")
      testElem.attrs = {
        "name": test.name,
        "classname": suite.name,
        "time": &"{test.duration:.3f}"
      }.toXmlAttributes
      
      case test.status
      of tsFail:
        var failureElem = newElement("failure")
        failureElem.attrs = {"message": test.message}.toXmlAttributes
        if test.stackTrace != "":
          failureElem.add(newText(test.stackTrace))
        testElem.add(failureElem)
      of tsSkip:
        testElem.add(newElement("skipped"))
      of tsPass:
        discard
      
      suiteElem.add(testElem)
    
    root.add(suiteElem)
  
  result = $root

# HTML Reporter
proc generateHTMLReport*(report: TestReport): string =
  let passRate = if report.totalTests > 0: 
    report.passedTests / report.totalTests * 100 
  else: 0.0
  
  # Build HTML manually since htmlgen doesn't support string interpolation
  result = "<!DOCTYPE html>\n<html>\n<head>\n"
  result.add("<title>" & report.title & "</title>\n")
  result.add("<style>\n")
  result.add("""
    body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
    .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .header { text-align: center; margin-bottom: 30px; }
    .summary { display: flex; justify-content: space-around; margin-bottom: 30px; }
    .summary-item { text-align: center; padding: 20px; border-radius: 8px; background: #f8f9fa; }
    .summary-item h3 { margin: 0 0 10px 0; color: #666; }
    .summary-item .number { font-size: 2em; font-weight: bold; }
    .passed { color: #28a745; }
    .failed { color: #dc3545; }
    .skipped { color: #ffc107; }
    .suite { margin-bottom: 30px; }
    .suite-header { background: #007bff; color: white; padding: 10px 15px; border-radius: 4px; }
    .test { padding: 10px 15px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center; }
    .test:hover { background: #f8f9fa; }
    .test-name { font-weight: 500; }
    .test-status { padding: 4px 12px; border-radius: 4px; font-size: 0.9em; }
    .status-pass { background: #d4edda; color: #155724; }
    .status-fail { background: #f8d7da; color: #721c24; }
    .status-skip { background: #fff3cd; color: #856404; }
    .test-duration { color: #666; font-size: 0.9em; }
    .progress-bar { width: 100%; height: 30px; background: #e9ecef; border-radius: 4px; overflow: hidden; margin-bottom: 30px; }
    .progress-fill { height: 100%; background: #28a745; transition: width 0.3s; }
    .error-details { margin-top: 10px; padding: 10px; background: #f8d7da; border-radius: 4px; font-size: 0.9em; }
  """)
  result.add("</style>\n</head>\n<body>\n")
  result.add("<div class=\"container\">\n")
  
  # Header
  result.add("<div class=\"header\">\n")
  result.add("<h1>" & report.title & "</h1>\n")
  result.add("<p>Generated: " & report.timestamp.format("yyyy-MM-dd HH:mm:ss") & "</p>\n")
  result.add("</div>\n")
  
  # Progress bar
  result.add("<div class=\"progress-bar\">\n")
  result.add(&"<div class=\"progress-fill\" style=\"width: {passRate:.1f}%\"></div>\n")
  result.add("</div>\n")
  
  # Summary
  result.add("<div class=\"summary\">\n")
  result.add("<div class=\"summary-item\">\n")
  result.add("<h3>Total Tests</h3>\n")
  result.add("<div class=\"number\">" & $report.totalTests & "</div>\n")
  result.add("</div>\n")
  
  result.add("<div class=\"summary-item\">\n")
  result.add("<h3>Passed</h3>\n")
  result.add("<div class=\"number passed\">" & $report.passedTests & "</div>\n")
  result.add("</div>\n")
  
  result.add("<div class=\"summary-item\">\n")
  result.add("<h3>Failed</h3>\n")
  result.add("<div class=\"number failed\">" & $report.failedTests & "</div>\n")
  result.add("</div>\n")
  
  result.add("<div class=\"summary-item\">\n")
  result.add("<h3>Skipped</h3>\n")
  result.add("<div class=\"number skipped\">" & $report.skippedTests & "</div>\n")
  result.add("</div>\n")
  
  result.add("<div class=\"summary-item\">\n")
  result.add("<h3>Duration</h3>\n")
  result.add(&"<div class=\"number\">{report.totalDuration:.3f}s</div>\n")
  result.add("</div>\n")
  result.add("</div>\n")
  
  # Test suites
  result.add("<div class=\"suites\">\n")
  for suite in report.suites:
    result.add("<div class=\"suite\">\n")
    result.add("<div class=\"suite-header\">" & suite.name & "</div>\n")
    result.add("<div class=\"tests\">\n")
    
    for test in suite.tests:
      result.add("<div class=\"test\">\n")
      result.add("<div>\n")
      result.add("<div class=\"test-name\">" & test.name & "</div>\n")
      if test.status == tsFail and test.message != "":
        result.add("<div class=\"error-details\">" & test.message & "</div>\n")
      result.add("</div>\n")
      
      result.add("<div style=\"display: flex; align-items: center; gap: 10px;\">\n")
      let statusClass = "status-" & ($test.status).toLowerAscii()
      result.add("<div class=\"test-status " & statusClass & "\">" & $test.status & "</div>\n")
      result.add(&"<div class=\"test-duration\">{test.duration:.3f}s</div>\n")
      result.add("</div>\n")
      result.add("</div>\n")
    
    result.add("</div>\n")
    result.add("</div>\n")
  
  result.add("</div>\n")
  result.add("</div>\n")
  result.add("</body>\n</html>")

# Markdown Reporter
proc generateMarkdownReport*(report: TestReport): string =
  result = &"# {report.title}\n\n"
  result &= &"**Generated:** {report.timestamp.format(\"yyyy-MM-dd HH:mm:ss\")}\n\n"
  
  # Summary table
  result &= "## Summary\n\n"
  result &= "| Metric | Value | Percentage |\n"
  result &= "|--------|-------|------------|\n"
  result &= &"| Total Tests | {report.totalTests} | 100% |\n"
  result &= &"| Passed | {report.passedTests} | {report.passedTests / report.totalTests * 100:.1f}% |\n"
  result &= &"| Failed | {report.failedTests} | {report.failedTests / report.totalTests * 100:.1f}% |\n"
  result &= &"| Skipped | {report.skippedTests} | {report.skippedTests / report.totalTests * 100:.1f}% |\n"
  result &= &"| Duration | {report.totalDuration:.3f}s | - |\n\n"
  
  # Test details
  result &= "## Test Results\n\n"
  
  for suite in report.suites:
    result &= &"### {suite.name}\n\n"
    
    if suite.tests.len > 0:
      result &= "| Test | Status | Duration |\n"
      result &= "|------|--------|----------|\n"
      
      for test in suite.tests:
        let statusIcon = case test.status
          of tsPass: "✅"
          of tsFail: "❌"
          of tsSkip: "⏭️"
        
        result &= &"| {test.name} | {statusIcon} {test.status} | {test.duration:.3f}s |\n"
        
        if test.status == tsFail and test.message != "":
          result &= &"\n> **Error:** {test.message}\n\n"
    
    result &= "\n"

# JSON Reporter
proc generateJSONReport*(report: TestReport): string =
  var reportJson = %*{
    "title": report.title,
    "timestamp": report.timestamp.format("yyyy-MM-dd'T'HH:mm:ss"),
    "summary": {
      "total": report.totalTests,
      "passed": report.passedTests,
      "failed": report.failedTests,
      "skipped": report.skippedTests,
      "duration": report.totalDuration,
      "passRate": if report.totalTests > 0: report.passedTests / report.totalTests * 100 else: 0.0
    },
    "suites": []
  }
  
  for suite in report.suites:
    var suiteJson = %*{
      "name": suite.name,
      "startTime": suite.startTime.format("yyyy-MM-dd'T'HH:mm:ss"),
      "endTime": suite.endTime.format("yyyy-MM-dd'T'HH:mm:ss"),
      "tests": []
    }
    
    for test in suite.tests:
      var testJson = %*{
        "name": test.name,
        "status": $test.status,
        "duration": test.duration
      }
      
      if test.message != "":
        testJson["message"] = %test.message
      if test.stackTrace != "":
        testJson["stackTrace"] = %test.stackTrace
      
      suiteJson["tests"].add(testJson)
    
    reportJson["suites"].add(suiteJson)
  
  result = reportJson.pretty()

# File writers
proc writeReport*(report: TestReport, format: string, filename: string) =
  let content = case format.toLowerAscii()
    of "console": report.generateConsoleReport()
    of "junit", "xml": report.generateJUnitXML()
    of "html": report.generateHTMLReport()
    of "markdown", "md": report.generateMarkdownReport()
    of "json": report.generateJSONReport()
    else: report.generateConsoleReport()
  
  if format == "console":
    echo content
  else:
    writeFile(filename, content)
    echo &"Test report written to: {filename}"

# Wrapper functions for TestReporter
proc printConsoleReport*(reporter: TestReporter) =
  ## Print console report
  echo generateConsoleReport(reporter.report)

proc generateJUnitReport*(reporter: TestReporter, filename: string) =
  ## Generate JUnit XML report and save to file
  writeFile(filename, generateJUnitXML(reporter.report))

proc generateHtmlReport*(reporter: TestReporter, filename: string) =
  ## Generate HTML report and save to file
  writeFile(filename, generateHTMLReport(reporter.report))

proc generateMarkdownReport*(reporter: TestReporter, filename: string) =
  ## Generate Markdown report and save to file
  writeFile(filename, generateMarkdownReport(reporter.report))

proc generateJsonReport*(reporter: TestReporter, filename: string) =
  ## Generate JSON report and save to file
  writeFile(filename, generateJSONReport(reporter.report))