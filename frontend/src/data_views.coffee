# data_views.coffee
# Data View management (saved queries).

LIST_DATA_VIEWS = """
  query { dataViews { id name description sourceSpace config createdAt updatedAt } }
"""

DATA_VIEW = """
  query DataView($id: ID!) {
    dataView(id: $id) { id name description sourceSpace config createdAt updatedAt }
  }
"""

CREATE_DATA_VIEW = """
  mutation CreateDataView($input: DataViewInput!) {
    createDataView(input: $input) { id name description sourceSpace config createdAt updatedAt }
  }
"""

UPDATE_DATA_VIEW = """
  mutation UpdateDataView($id: ID!, $input: DataViewInput!) {
    updateDataView(id: $id, input: $input) { id name description sourceSpace config createdAt updatedAt }
  }
"""

DELETE_DATA_VIEW = """
  mutation DeleteDataView($id: ID!) {
    deleteDataView(id: $id)
  }
"""

EXECUTE_DATA_VIEW = """
  query ExecuteDataView($id: ID!, $limit: Int, $offset: Int) {
    executeDataView(id: $id, limit: $limit, offset: $offset)
  }
"""

window.DataViews =
  list: ->
    GQL.query(LIST_DATA_VIEWS).then (d) -> d.dataViews

  get: (id) ->
    GQL.query(DATA_VIEW, { id }).then (d) -> d.dataView

  create: (input) ->
    GQL.mutate(CREATE_DATA_VIEW, { input }).then (d) -> d.createDataView

  update: (id, params) ->
    GQL.mutate(UPDATE_DATA_VIEW, { id, input: params }).then (d) -> d.updateDataView

  delete: (id) ->
    GQL.mutate(DELETE_DATA_VIEW, { id }).then (d) -> d.deleteDataView

  execute: (id, limit = 100, offset = 0) ->
    GQL.query(EXECUTE_DATA_VIEW, { id, limit, offset }).then (d) -> d.executeDataView
