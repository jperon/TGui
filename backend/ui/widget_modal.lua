local H = require('html')
local _widgetConfigRow
_widgetConfigRow = function(labelText, inputElement)
  return H.div({
    class = 'config-row',
    H.label({
      labelText
    }),
    inputElement
  })
end
local _widgetTitleInput
_widgetTitleInput = function()
  return H.input({
    type = 'text',
    id = 'widget-title-input',
    placeholder = 'Mon widget',
    class = 'widget-input'
  })
end
local _widgetSpaceSelect
_widgetSpaceSelect = function()
  return H.select({
    id = 'widget-space-select',
    class = 'widget-select',
    H.option({
      value = '',
      'Sélectionner un espace...'
    })
  })
end
local _widgetFieldsContainer
_widgetFieldsContainer = function()
  return H.div({
    id = 'widget-fields-container',
    class = 'fields-container',
    H.div({
      class = 'fields-header',
      H.div({
        class = 'field-group',
        'Disponibles:'
      }),
      H.div({
        class = 'field-group',
        'Sélectionnées:'
      })
    }),
    H.div({
      class = 'fields-lists',
      H.div({
        id = 'available-fields',
        class = 'fields-list',
        H.div({
          class = 'field-placeholder',
          'Sélectionnez un espace...'
        })
      }),
      H.div({
        id = 'selected-fields',
        class = 'fields-list selected',
        H.div({
          class = 'field-placeholder',
          'Aucun champ sélectionné'
        })
      })
    })
  })
end
local _widgetTypeOption
_widgetTypeOption = function(value, label, checked)
  if checked == nil then
    checked = false
  end
  return H.div({
    class = 'widget-type-option',
    H.input({
      type = 'radio',
      name = 'widget-type',
      value = value,
      id = "widget-type-" .. tostring(value),
      checked = checked
    }),
    H.label({
      ['for'] = "widget-type-" .. tostring(value),
      label
    })
  })
end
local _widgetParamRow
_widgetParamRow = function()
  return H.div({
    class = 'param-row',
    H.input({
      type = 'text',
      placeholder = 'Clé',
      class = 'param-key'
    }),
    H.input({
      type = 'text',
      placeholder = 'Valeur',
      class = 'param-value'
    }),
    H.button({
      type = 'button',
      class = 'param-remove-btn',
      '✕'
    })
  })
end
local _widgetDataSourceSection
_widgetDataSourceSection = function()
  return H.div({
    class = 'widget-section',
    H.h3({
      '1. Source de données'
    }),
    H.div({
      class = 'data-source-config',
      _widgetConfigRow('Titre du widget:', _widgetTitleInput()),
      _widgetConfigRow('Espace:', _widgetSpaceSelect()),
      _widgetConfigRow('Colonnes à afficher:', _widgetFieldsContainer())
    })
  })
end
local _widgetTypeSection
_widgetTypeSection = function()
  return H.div({
    class = 'widget-section',
    H.h3({
      '2. Type de widget'
    }),
    H.div({
      class = 'widget-type-config',
      H.div({
        class = 'widget-type-options',
        _widgetTypeOption('table', 'Tableau simple', true)
      })
    })
  })
end
local _widgetParamsSection
_widgetParamsSection = function()
  return H.div({
    class = 'widget-section',
    H.h3({
      '3. Paramètres du widget'
    }),
    H.div({
      class = 'widget-params-config',
      H.div({
        id = 'widget-params-list',
        class = 'params-list',
        _widgetParamRow()
      }),
      H.button({
        id = 'add-param-btn',
        class = 'btn-secondary',
        '+ Ajouter un paramètre'
      })
    })
  })
end
local make_add_widget_modal
make_add_widget_modal = function()
  return H.div({
    id = 'add-widget-modal',
    class = 'modal-overlay hidden',
    H.div({
      class = 'modal-box modal-box--editor',
      H.div({
        class = 'modal-editor-header',
        H.span({
          class = 'modal-title',
          'Ajouter un widget'
        }),
        H.div({
          class = 'modal-editor-actions',
          H.button({
            id = 'add-widget-confirm-btn',
            class = 'btn-primary',
            'Ajouter'
          }),
          H.button({
            id = 'add-widget-cancel-btn',
            class = 'toolbar-btn',
            '✕'
          })
        })
      }),
      H.div({
        class = 'add-widget-modal-body',
        _widgetDataSourceSection(),
        _widgetTypeSection(),
        _widgetParamsSection()
      })
    })
  })
end
return {
  make_add_widget_modal = make_add_widget_modal
}
