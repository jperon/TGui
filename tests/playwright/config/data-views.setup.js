(function() {
  // Data Views helper utilities for Playwright tests
  // Provides Data View creation, configuration, and management
  var DataViewsHelper;

  DataViewsHelper = class DataViewsHelper {
    constructor() {
      this.createdDataViews = [];
      this.randomSuffix = Math.floor(Math.random() * 1000000);
    }

    // Generate unique test data view name
    generateDataViewName(baseName = 'test_data_view') {
      return `${baseName}_${this.randomSuffix}`;
    }

    // Create a new Data View via UI
    async createDataView({page, name, description, sourceSpace, config = {}}) {
      var dataViewId;
      await page.goto('/#!data-views');
      
      // Click "Create Data View" button
      await page.click('[data-testid="create-data-view-button"]');
      
      // Fill Data View creation form
      await page.fill('input[name="name"]', name);
      await page.fill('textarea[name="description"]', description);
      await page.selectOption('select[name="sourceSpace"]', sourceSpace);
      
      // Configure basic settings
      if (config.limit) {
        await page.fill('input[name="limit"]', config.limit.toString());
      }
      if (config.offset) {
        await page.fill('input[name="offset"]', config.offset.toString());
      }
      
      // Submit form
      await page.click('[data-testid="save-data-view-button"]');
      
      // Wait for success and redirect
      await page.waitForSelector('[data-testid="data-view-created-success"]');
      
      // Get Data View ID from page content
      dataViewId = (await page.evaluate(function() {
        var ref;
        return (ref = document.querySelector('[data-data-view-id]')) != null ? ref.getAttribute('data-data-view-id') : void 0;
      }));
      this.createdDataViews.push({
        id: dataViewId,
        name,
        sourceSpace
      });
      console.log(`✅ Created Data View: ${name} (ID: ${dataViewId})`);
      return dataViewId;
    }

    // Create a new Data View via GraphQL API
    async createDataViewGraphQL({page, name, description, sourceSpace, config = {}}) {
      var AuthHelper, auth, configJson, dataViewId, query, result, variables;
      query = `mutation CreateDataView($name: String!, $description: String!, $sourceSpace: String!, $config: String!) {
  createDataView(name: $name, description: $description, sourceSpace: $sourceSpace, config: $config) {
    id
    name
    description
    sourceSpace
    config
  }
}`;
      
      // Convert config to JSON string
      configJson = JSON.stringify(config);
      variables = {
        name,
        description,
        sourceSpace,
        config: configJson
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      dataViewId = result.createDataView.id;
      this.createdDataViews.push({
        id: dataViewId,
        name,
        sourceSpace
      });
      console.log(`✅ Created Data View via GraphQL: ${name} (ID: ${dataViewId})`);
      return dataViewId;
    }

    // Configure filters on Data View
    async configureFilters({page, dataViewId, filters}) {
      var filter, i, len;
      await page.goto(`/#!data-views/${dataViewId}`);
      
      // Click "Configure Filters" button
      await page.click('[data-testid="configure-filters-button"]');

      // Add each filter
      for (i = 0, len = filters.length; i < len; i++) {
        filter = filters[i];
        await page.click('[data-testid="add-filter-button"]');
        await page.selectOption('select[name="field"]', filter.field);
        await page.selectOption('select[name="operator"]', filter.operator);
        await page.fill('input[name="value"]', filter.value.toString());
        await page.click('[data-testid="save-filter-button"]');
      }
      
      // Apply filters
      await page.click('[data-testid="apply-filters-button"]');
      
      // Wait for filters to be applied
      await page.waitForSelector('[data-testid="filters-applied"]');
      return console.log(`✅ Configured ${filters.length} filters for Data View ${dataViewId}`);
    }

    // Configure aggregations (GROUP BY)
    async configureAggregations({page, dataViewId, aggregations}) {
      var agg, i, len;
      await page.goto(`/#!data-views/${dataViewId}`);
      
      // Click "Configure Aggregations" button
      await page.click('[data-testid="configure-aggregations-button"]');

      // Add aggregation fields
      for (i = 0, len = aggregations.length; i < len; i++) {
        agg = aggregations[i];
        await page.click('[data-testid="add-aggregation-button"]');
        await page.selectOption('select[name="field"]', agg.field);
        await page.selectOption('select[name="function"]', agg.function); // COUNT, SUM, AVG, etc.
        if (agg.alias) {
          await page.fill('input[name="alias"]', agg.alias);
        }
        await page.click('[data-testid="save-aggregation-button"]');
      }
      
      // Apply aggregations
      await page.click('[data-testid="apply-aggregations-button"]');
      
      // Wait for aggregations to be applied
      await page.waitForSelector('[data-testid="aggregations-applied"]');
      return console.log(`✅ Configured ${aggregations.length} aggregations for Data View ${dataViewId}`);
    }

    // Execute Data View and get results
    async executeDataView({page, dataViewId}) {
      var results;
      await page.goto(`/#!data-views/${dataViewId}`);
      
      // Click "Execute" button
      await page.click('[data-testid="execute-data-view-button"]');
      
      // Wait for results to load
      await page.waitForSelector('[data-testid="data-view-results"]');
      
      // Get results from page
      results = (await page.evaluate(function() {
        var rows;
        rows = document.querySelectorAll('[data-testid="result-row"]');
        return Array.from(rows).map(function(row) {
          var cells;
          cells = row.querySelectorAll('[data-testid="result-cell"]');
          return Array.from(cells).map(function(cell) {
            return cell.textContent;
          });
        });
      }));
      console.log(`✅ Executed Data View ${dataViewId}, got ${results.length} results`);
      return results;
    }

    // Execute Data View via GraphQL API
    async executeDataViewGraphQL({page, dataViewId}) {
      var AuthHelper, auth, query, result, variables;
      query = `query ExecuteDataView($dataViewId: ID!) {
  dataView(id: $dataViewId) {
    id
    name
    results
  }
}`;
      variables = {dataViewId};
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`✅ Executed Data View via GraphQL: ${dataViewId}`);
      return result.dataView;
    }

    // Update Data View configuration
    async updateDataView({page, dataViewId, updates}) {
      var AuthHelper, auth, query, result, variables;
      query = `mutation UpdateDataView($dataViewId: ID!, $input: UpdateDataViewInput!) {
  updateDataView(dataViewId: $dataViewId, input: $input) {
    id
    name
    description
    config
  }
}`;
      variables = {
        dataViewId: dataViewId,
        input: updates
      };
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      result = (await auth.makeGraphQLRequest(page, query, variables));
      console.log(`✅ Updated Data View: ${dataViewId}`);
      return result.updateDataView;
    }

    // Delete Data View
    async deleteDataView({page, dataViewId}) {
      await page.goto(`/#!data-views/${dataViewId}`);
      
      // Click delete button
      await page.click('[data-testid="delete-data-view-button"]');
      
      // Confirm deletion in modal
      await page.click('[data-testid="confirm-delete-button"]');
      
      // Wait for success message
      await page.waitForSelector('[data-testid="data-view-deleted-success"]');
      
      // Remove from created Data Views tracking
      this.createdDataViews = this.createdDataViews.filter(function(dv) {
        return dv.id !== dataViewId;
      });
      return console.log(`✅ Deleted Data View: ${dataViewId}`);
    }

    // Delete Data View via GraphQL API
    async deleteDataViewGraphQL({page, dataViewId}) {
      var AuthHelper, auth, query, variables;
      query = `mutation DeleteDataView($dataViewId: ID!) {
  deleteDataView(dataViewId: $dataViewId)
}`;
      variables = {dataViewId};
      ({AuthHelper} = require('./auth.setup'));
      auth = new AuthHelper();
      await auth.makeGraphQLRequest(page, query, variables);
      
      // Remove from created Data Views tracking
      this.createdDataViews = this.createdDataViews.filter(function(dv) {
        return dv.id !== dataViewId;
      });
      return console.log(`✅ Deleted Data View via GraphQL: ${dataViewId}`);
    }

    // Clean up all created Data Views
    async cleanup({page}) {
      var dataView, error, i, len, ref;
      console.log(`🧹 Cleaning up ${this.createdDataViews.length} test Data Views...`);
      ref = this.createdDataViews;
      for (i = 0, len = ref.length; i < len; i++) {
        dataView = ref[i];
        try {
          await this.deleteDataViewGraphQL(page, dataView.id);
        } catch (error1) {
          error = error1;
          console.warn(`⚠️ Failed to delete Data View ${dataView.name}: ${error.message}`);
        }
      }
      this.createdDataViews = [];
      return console.log("✅ All test Data Views cleaned up");
    }

  };

  module.exports = {DataViewsHelper};

}).call(this);
