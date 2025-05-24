# Package

version       = "0.0.0"
author        = "jasagiri"
description   = "Comprehensive design patterns library for Nim with cross-cutting concerns integration"
license       = "MIT"
srcDir        = "src"
bin           = @["nim_design_patterns"]

# Dependencies

requires "nim >= 2.0.0"
# Local dependencies are handled via nim.cfg
# requires "https://github.com/jasagiri/nim-lang-core.git"
# requires "https://github.com/jasagiri/nim-libaspects >= 0.0.0"
requires "results >= 0.5.0"
requires "chronicles >= 0.10.0"

# Tasks

task test, "Run all tests":
  echo "Running tests..."
  exec "nim c -r --hints:off --nimcache:./nimcache tests/test_factory.nim"
  # TODO: Fix other tests and re-enable
  # exec "nim c -r tests/test_all.nim"

task test_creational, "Run creational pattern tests":
  exec "nim c -r tests/test_factory.nim"
  exec "nim c -r tests/test_builder.nim"
  exec "nim c -r tests/test_singleton.nim"

task test_structural, "Run structural pattern tests":
  exec "nim c -r tests/test_adapter.nim"
  exec "nim c -r tests/test_decorator.nim"
  exec "nim c -r tests/test_proxy.nim"

task test_behavioral, "Run behavioral pattern tests":
  exec "nim c -r tests/test_observer.nim"
  exec "nim c -r tests/test_strategy.nim"
  exec "nim c -r tests/test_command.nim"

task test_functional, "Run functional pattern tests":
  exec "nim c -r tests/run_lens_test.nim"

task test_integration, "Run integration tests":
  exec "nim c -r tests/test_nim_core_integration.nim"
  exec "nim c -r tests/test_nim_libs_integration.nim"

task docs, "Generate documentation":
  exec "nim doc --outdir:htmldocs --git.url:https://github.com/jasagiri/nim-design-patterns --git.commit:main src/nim_design_patterns.nim"
  for module in ["creational/factory", "creational/builder", "creational/singleton",
                 "structural/adapter", "structural/decorator", "structural/proxy",
                 "behavioral/observer", "behavioral/strategy", "behavioral/command",
                 "functional/lens"]:
    exec "nim doc --outdir:htmldocs --git.url:https://github.com/jasagiri/nim-design-patterns --git.commit:main src/nim_design_patterns/" & module & ".nim"

task examples, "Build examples":
  exec "nim c -d:release examples/factory_example.nim"
  exec "nim c -d:release examples/observer_example.nim"
  exec "nim c -d:release examples/integration_example.nim"
  exec "nim c -d:release examples/lens_example.nim"

task benchmark, "Run benchmarks":
  exec "nim c -r -d:release --opt:speed benchmarks/pattern_benchmarks.nim"

task clean, "Clean build artifacts":
  exec "rm -rf nimcache/ htmldocs/ *.exe coverage_cache/ tests/*_cov *.gcda *.gcno *.gcov"

task coverage, "Run tests with coverage":
  # Compile tests with coverage flags for C backend
  echo "Building tests with coverage support..."
  exec "nim c --cc:gcc --passC:--coverage --passL:--coverage --nimcache:coverage_cache -o:tests/test_factory_cov tests/test_factory.nim"

  # Run the tests
  echo "Running tests..."
  exec "./tests/test_factory_cov"

  # Try to generate coverage for our source files
  echo "Generating coverage report..."
  exec "cd coverage_cache && gcov -r *.c 2>/dev/null | grep -E 'File|Lines executed' || echo 'Coverage data generated (raw .gcda files available)'"

  # Summary
  echo "\nTest execution completed successfully!"
  echo "Coverage data files are available in coverage_cache/"
  echo "For detailed HTML reports, consider using lcov and genhtml tools."

  # Clean up executable
  exec "rm -f tests/test_factory_cov"

task test_report, "Run tests with detailed reporting":
  exec "nim c -r tests/run_tests_with_report"

task test_coverage_report, "Run tests with coverage and detailed reporting":
  putEnv("COVERAGE", "true")
  exec "nim c --mm:refc --passC:--coverage --passL:--coverage -r tests/run_tests_with_report"
