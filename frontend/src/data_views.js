(function() {
  // data_views.coffee
  // Data View management (saved queries).
  var CREATE_DATA_VIEW, DATA_VIEW, DELETE_DATA_VIEW, EXECUTE_DATA_VIEW, LIST_DATA_VIEWS, UPDATE_DATA_VIEW;

  LIST_DATA_VIEWS = `query { dataViews { id name description sourceSpace config createdAt updatedAt } }`;

  DATA_VIEW = `query DataView($id: ID!) {
  dataView(id: $id) { id name description sourceSpace config createdAt updatedAt }
}`;

  CREATE_DATA_VIEW = `mutation CreateDataView($input: DataViewInput!) {
  createDataView(input: $input) { id name description sourceSpace config createdAt updatedAt }
}`;

  UPDATE_DATA_VIEW = `mutation UpdateDataView($id: ID!, $input: DataViewInput!) {
  updateDataView(id: $id, input: $input) { id name description sourceSpace config createdAt updatedAt }
}`;

  DELETE_DATA_VIEW = `mutation DeleteDataView($id: ID!) {
  deleteDataView(id: $id)
}`;

  EXECUTE_DATA_VIEW = `query ExecuteDataView($id: ID!, $limit: Int, $offset: Int) {
  executeDataView(id: $id, limit: $limit, offset: $offset)
}`;

  window.DataViews = {
    list: function() {
      return GQL.query(LIST_DATA_VIEWS).then(function(d) {
        return d.dataViews;
      });
    },
    get: function(id) {
      return GQL.query(DATA_VIEW, {id}).then(function(d) {
        return d.dataView;
      });
    },
    create: function(input) {
      return GQL.mutate(CREATE_DATA_VIEW, {input}).then(function(d) {
        return d.createDataView;
      });
    },
    update: function(id, params) {
      return GQL.mutate(UPDATE_DATA_VIEW, {
        id,
        input: params
      }).then(function(d) {
        return d.updateDataView;
      });
    },
    delete: function(id) {
      return GQL.mutate(DELETE_DATA_VIEW, {id}).then(function(d) {
        return d.deleteDataView;
      });
    },
    execute: function(id, limit = 100, offset = 0) {
      return GQL.query(EXECUTE_DATA_VIEW, {id, limit, offset}).then(function(d) {
        return d.executeDataView;
      });
    }
  };

}).call(this);
