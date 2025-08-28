# Testing Strategies - Universal Best Practices

This document outlines comprehensive testing strategies focused on industry best practices and avoiding anti-patterns that lead to brittle, time-consuming tests.

> **📋 Elixir-Specific Patterns**: For detailed Elixir/Phoenix testing patterns, see [elixir-testing-patterns.md](./elixir-testing-patterns.md)

## TDD (Test-Driven Development) Specification

### Core TDD Principles

Test-Driven Development follows the **Red-Green-Refactor** cycle:

1. **Red**: Write a failing test that describes desired behavior
2. **Green**: Write minimal code to make the test pass  
3. **Refactor**: Improve code quality while keeping tests green

### TDD Best Practices

#### 1. Start with Behavior, Not Implementation
- Test the public API and observable behaviors
- Avoid testing internal methods or private state
- Focus on business requirements and user outcomes

#### 2. Use Test Data Builders
- Create reusable builders for complex test data
- Reduce test setup complexity and duplication
- Allow easy customization for different test scenarios

#### 3. Test Error Conditions First
- Write tests for invalid input and edge cases
- Drive proper error handling implementation
- Test boundary conditions and failure scenarios

#### 4. Break Down Complex Logic
- Start with simple cases, build complexity gradually
- Test each logical branch and condition
- Ensure tests clearly express business rules

### TDD Anti-Patterns to Avoid

#### ❌ DON'T: Write Tests After Code
- Tests become verification tools rather than design tools
- Missing edge cases and error conditions

#### ❌ DON'T: Test Implementation Details
- Test behaviors and outcomes, not internal implementation
- Write tests that survive refactoring

#### ❌ DON'T: Skip the Red Step
- Always ensure your test fails first
- Validates that the test actually tests something

---

## Universal Test Specification

### Test Structure and Organization

#### 1. Arrange-Act-Assert (AAA) Pattern
- **Arrange**: Set up test data and dependencies
- **Act**: Execute the code under test
- **Assert**: Verify the expected outcome

#### 2. Test Isolation and Independence
- Each test should run independently
- No shared state between tests
- Use fresh setup for each test

#### 3. Meaningful Test Names
- Describe what is being tested and expected outcome
- Use consistent naming conventions
- Make failures easy to understand

### Testing Different Scenarios

#### Unit Tests
- Test individual components in isolation
- Fast execution and focused scope
- High coverage of business logic

#### Integration Tests
- Test component interactions
- Verify system behavior end-to-end
- Test external dependencies and interfaces

#### Error Handling Tests
- Test failure scenarios and edge cases
- Verify proper error messages and recovery
- Test security and validation failures

### Test Organization Best Practices

#### Directory Structure
```
test/
├── unit/           # Fast, isolated unit tests
├── integration/    # Component interaction tests
├── support/        # Test helpers and utilities
└── fixtures/       # Test data and builders
```

#### Test Categories and Tags
- Use tags to categorize tests by speed/type
- Separate fast tests from slow tests
- Enable selective test execution

### Universal Anti-Patterns to Avoid

#### ❌ DON'T: Create Overly Complex Setup
- Keep test setup minimal and focused
- Use shared setup only for expensive operations
- Prefer composition over inheritance in test helpers

#### ❌ DON'T: Test Multiple Things in One Test
- One test should verify one behavior
- Keep tests focused and atomic
- Make failure diagnosis easy

#### ❌ DON'T: Use Sleep for Timing
- Use proper synchronization mechanisms
- Implement polling with timeouts for async operations
- Avoid brittle timing dependencies

#### ❌ DON'T: Ignore Test Performance
- Keep tests fast and reliable
- Use representative sample data, not large datasets
- Separate performance tests from regular test suite

### Test Helpers and Utilities

#### Shared Test Utilities
- Create helpers for common test operations
- Implement proper cleanup and resource management
- Provide utilities for async testing and synchronization

#### Test Data Management
- Use builders and factories for test data
- Implement data cleanup strategies
- Provide realistic but minimal test datasets

## Summary

Effective testing strategies focus on:

- **Behavior over Implementation**: Test what the code does, not how
- **Maintainable Structure**: Clear, focused tests that are easy to understand
- **Proper Isolation**: Independent tests without side effects
- **Performance Awareness**: Fast, reliable test execution
- **Clear Failure Messages**: Easy problem diagnosis

Following these practices results in:
- Confidence in code correctness
- Living documentation of system behavior
- Safe refactoring capabilities
- Quick and reliable feedback loops
- Maintainable and scalable test suites