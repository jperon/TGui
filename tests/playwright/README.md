# Playwright E2E Tests for TGui

## Overview

This directory contains comprehensive end-to-end tests for the TGui web application using Playwright. The tests are written in CoffeeScript to maintain consistency with the existing codebase.

## Structure

```
tests/playwright/
├── playwright.config.coffee      # Main Playwright configuration
├── config/                      # Helper utilities and setup
│   ├── auth.setup.coffee        # Authentication helpers
│   ├── spaces.setup.coffee      # Space management helpers
│   ├── data-views.setup.coffee  # Data View helpers
│   ├── pages.setup.coffee       # Page/widget helpers
│   ├── global-setup.coffee      # Global test setup
│   └── global-teardown.coffee    # Global test cleanup
├── auth/                        # Authentication tests
│   ├── login.spec.coffee         # Login/logout functionality
│   └── permissions.spec.coffee   # Access control tests
├── spaces/                      # Space management tests
│   ├── creation.spec.coffee     # Space CRUD operations
│   ├── fields.spec.coffee       # Field management
│   └── reordering.spec.coffee   # Field drag & drop
├── data-views/                  # Data View tests
│   ├── creation.spec.coffee     # Data View CRUD
│   ├── filters.spec.coffee      # Filter configuration
│   └── aggregations.spec.coffee # GROUP BY and aggregations
├── pages/                       # Page and widget tests
│   ├── yaml-editor.spec.coffee  # Direct YAML editing
│   ├── widgets.spec.coffee      # Widget management
│   └── drag-drop.spec.coffee    # Widget drag & drop
├── relations/                   # Relation tests (TODO)
├── integration/                 # Integration tests (TODO)
└── e2e/                         # End-to-end workflow tests
    └── complete-workflow.spec.coffee
```

## Setup

### Prerequisites

1. Node.js 16+ and npm installed
2. TGui test instance running on `http://localhost:8081`
3. Playwright browsers installed

### Installation

```bash
# Install Playwright and browsers
make playwright-install

# Or using npm directly
npm install @playwright/test
npx playwright install

# Start test environment
make test-up

# Compile tests (automatic when running tests)
make playwright-compile
```

## Running Tests

### Individual Test Suites

```bash
# Run all browser tests (compiles automatically)
make test-browser

# Run specific test suites (compiles automatically)
make test-browser-spaces
make test-browser-pages
make test-browser-auth
make test-browser-data-views
make test-browser-relations
make test-browser-integration
make test-browser-e2e
```

### Manual Compilation

```bash
# Compile only Playwright tests
make playwright-compile

# Compile and run
make test-browser-spaces
```

### Development and Debugging

```bash
# Run tests in debug mode (compiles automatically)
make test-browser-debug

# Run specific test file (compile first)
make playwright-compile
npx playwright test tests/playwright/auth/login.spec.js --config=tests/playwright/playwright.config.js

# Generate HTML report
make test-browser-report
```

## Test Features

### Authentication Tests
- Login with valid/invalid credentials
- Session management
- Permission-based access control
- Logout functionality

### Space Management Tests
- Space creation, modification, deletion
- Field management (all field types)
- Field reordering via drag & drop
- Validation and error handling

### Data View Tests
- Data View creation and configuration
- Filter setup and execution
- Aggregation (GROUP BY) configuration
- Performance with large datasets

### Page and Widget Tests
- YAML direct editing
- Widget creation and management
- Drag & drop widget reordering
- Complex nested layouts

### End-to-End Tests
- Complete user workflows
- Complex nested page layouts
- Error scenario handling
- Performance testing

## Configuration

### Playwright Config

The main configuration is in `playwright.config.coffee`:

- **Base URL**: `http://localhost:8081` (test environment)
- **Timeout**: 30 seconds (for GraphQL operations)
- **Browsers**: Chromium, Firefox, WebKit
- **Retry**: 2 attempts on failure
- **Reporting**: HTML reports with screenshots/videos on failure

### Test Helpers

Each test suite uses helper classes for common operations:

- **AuthHelper**: Login, logout, token management
- **SpacesHelper**: Space and field CRUD operations
- **DataViewsHelper**: Data View management
- **PagesHelper**: Page and widget management

## Test Data Management

### Cleanup Strategy

- Each test suite cleans up its own data
- Random suffixes prevent naming conflicts
- Global setup/teardown for environment cleanup
- Tests can run independently or together

### Data Isolation

- Tests use random suffixes for resource names
- Each test creates its own data
- Automatic cleanup after test completion
- No interference between test runs

## Writing New Tests

### Test Structure

```coffee
{ test, expect } = require '@playwright/test'
{ AuthHelper } = require '../config/auth.setup'
{ SpacesHelper } = require '../config/spaces.setup'

test.describe('Feature Name', ->
  let authHelper
  let spacesHelper

  test.beforeEach(async ({ page }) ->
    authHelper = new AuthHelper()
    spacesHelper = new SpacesHelper()
    await authHelper.login page
  )

  test.afterEach(async ({ page }) ->
    await spacesHelper.cleanup page
  )

  test('should do something', async ({ page }) ->
    # Test implementation
    await expect(page.locator('[data-testid="element"]')).toBeVisible()
  )
)
```

### Best Practices

1. **Use data-testid attributes** for reliable element selection
2. **Clean up created data** in afterEach hooks
3. **Use helper classes** for common operations
4. **Add descriptive test names** and console logging
5. **Test both UI and GraphQL APIs** when available
6. **Include error scenarios** and edge cases

## Troubleshooting

### Common Issues

1. **TGui test instance not running**: Start with `make test-up`
2. **Port conflicts**: Ensure TGui test instance is on port 8081
3. **Browser installation**: Run `npx playwright install`
4. **Test timeouts**: Increase timeout in config for slow operations
5. **Authentication failures**: Check admin credentials

### Debug Mode

```bash
# Run with debugging
make test-browser-debug

# Or specific test
npx playwright test tests/playwright/auth/login.spec.coffee --config=tests/playwright/playwright.config.coffee --debug
```

### Reports and Artifacts

- **HTML Reports**: `make test-browser-report`
- **Screenshots**: Saved on test failure
- **Videos**: Recorded on test failure
- **Trace Files**: Detailed execution traces

## Integration with CI

The tests are designed to integrate with the existing CI/CD pipeline:

```bash
# Run all tests (including existing unit tests)
make test

# Run only browser tests
make test-browser

# Run specific suite
make test-browser-spaces
```

## Future Enhancements

- [ ] Visual regression testing
- [ ] Mobile device testing
- [ ] Performance benchmarking
- [ ] Accessibility testing
- [ ] API response time monitoring
- [ ] Cross-browser compatibility matrix
