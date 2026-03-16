# Playwright Tests Usage Guide

## Quick Start

### 1. Start Test Environment
```bash
# Start the test instance (port 8081)
make test-up

# Verify it's running
curl http://localhost:8081
```

### 2. Install Playwright (first time only)
```bash
make playwright-install
```

### 3. Run Tests
```bash
# Run all browser tests
make test-browser

# Run specific test suites
make test-browser-spaces
make test-browser-pages
make test-browser-auth
```

## Environment Details

### Test vs Production
- **Test**: `localhost:8081` - Isolated test environment
- **Production**: `localhost:8080` - Main application

### Why Port 8081?
- **Isolation**: Tests use dedicated test database
- **Safety**: No risk to production data
- **Parallel**: Can run alongside production
- **Cleanup**: Automatic cleanup after tests

### Test Data
- **Random suffixes**: All test data uses random suffixes
- **Automatic cleanup**: Tests clean up their own data
- **Isolated spaces**: Each test gets its own spaces/pages
- **No conflicts**: Tests can run in parallel safely

## Test Environment Management

### Start Test Environment
```bash
make test-up
# Starts: tgui-tarantool-test on port 8081
# Uses: docker-compose.test.yml
# Database: Fresh test database
```

### Stop Test Environment
```bash
make test-down
# Stops and removes test containers
# Cleans up test data
```

### Check Test Environment
```bash
make test-logs
# View test container logs
curl http://localhost:8081
# Verify test instance is responding
```

## Test Execution Examples

### Run All Tests
```bash
make test-browser
# Equivalent to:
# make test-browser-spaces
# make test-browser-data-views
# make test-browser-pages
# make test-browser-relations
# make test-browser-auth
# make test-browser-integration
# make test-browser-e2e
```

### Run Single Test File
```bash
npx playwright test tests/playwright/auth/login.spec.coffee --config=tests/playwright/playwright.config.coffee
```

### Debug Mode
```bash
make test-browser-debug
# Opens browser in debug mode
# Step through tests interactively
```

### Generate Report
```bash
make test-browser-report
# Opens HTML report in browser
# Shows screenshots/videos of failures
```

## Test Categories

### 1. Authentication Tests (`make test-browser-auth`)
- Login/logout functionality
- Permission validation
- Session management
- Access control

### 2. Spaces Tests (`make test-browser-spaces`)
- Space CRUD operations
- Field management (all types)
- Field reordering (drag & drop)
- Validation and error handling

### 3. Data Views Tests (`make test-browser-data-views`)
- Data View creation and configuration
- Filter setup and execution
- Aggregation (GROUP BY) configuration
- Performance testing

### 4. Pages Tests (`make test-browser-pages`)
- YAML direct editing
- Widget creation and management
- Drag & drop widget reordering
- Complex nested layouts

### 5. End-to-End Tests (`make test-browser-e2e`)
- Complete user workflows
- Complex nested page layouts
- Error scenario handling
- Performance with large datasets

## Troubleshooting

### Port Already in Use
```bash
# Check what's using port 8081
lsof -i :8081

# Stop test environment
make test-down

# Restart
make test-up
```

### Test Instance Not Responding
```bash
# Check container status
docker ps | grep tdb-test

# View logs
make test-logs

# Restart if needed
make test-down && make test-up
```

### Browser Installation Issues
```bash
# Reinstall Playwright browsers
npx playwright install

# Force reinstall
npx playwright install --force
```

### Test Timeouts
```bash
# Increase timeout in playwright.config.coffee
timeout: 60000  # 60 seconds instead of 30
```

### Authentication Failures
```bash
# Check test credentials (admin/adminadmin)
# Verify test instance is running
# Check test database is accessible
```

## Best Practices

### Before Running Tests
1. **Start test environment**: `make test-up`
2. **Verify instance**: `curl http://localhost:8081`
3. **Clean up old data**: `make test-down && make test-up`

### During Development
1. **Use debug mode**: `make test-browser-debug`
2. **Run specific tests**: `make test-browser-spaces`
3. **Check logs**: `make test-logs`

### After Tests
1. **View reports**: `make test-browser-report`
2. **Clean up**: `make test-down` (optional)
3. **Check for leftover data**: Review test logs

## Performance Tips

### Test Execution Speed
- **Run specific suites**: Don't run all tests unless needed
- **Use test data wisely**: Tests create their own data
- **Parallel execution**: Tests can run independently

### Resource Usage
- **Memory**: Each test creates temporary data
- **Disk**: Screenshots/videos on failure only
- **Network**: All requests to localhost (fast)

## Integration with CI

### GitHub Actions Example
```yaml
- name: Start Test Environment
  run: make test-up

- name: Run Playwright Tests
  run: make test-browser

- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: playwright-report
    path: playwright-report/
```

### Local CI Simulation
```bash
# Full test cycle
make test-down          # Clean start
make test-up            # Start environment
make test-browser       # Run all tests
make test-browser-report # View results
make test-down          # Clean up
```

## Security Considerations

### Test Isolation
- **Separate database**: Test data never touches production
- **Network isolation**: Only localhost access
- **Container isolation**: Docker containers isolate tests

### Data Protection
- **Auto cleanup**: Tests clean up their own data
- **Random naming**: No conflicts between test runs
- **No persistence**: Test data is temporary

### Access Control
- **Admin credentials**: Tests use admin account
- **Token management**: Tokens are isolated per test
- **Session cleanup**: Sessions are cleaned up after tests
