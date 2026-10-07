local H = require('html')
local _dataViewTabFields
_dataViewTabFields = function()
  return H.div({
    id = 'dv-tab-fields',
    class = 'dv-tab-content',
    H.div({
      class = 'dv-fields-layout',
      H.div({
        class = 'dv-fields-left',
        H.h4({
          'Sélectionnez les champs et jointures'
        }),
        H.div({
          id = 'dv-joins-graph-container',
          class = 'joins-graph-container',
          H.div({
            class = 'joins-placeholder',
            'Sélectionnez un espace source pour voir les relations...'
          })
        })
      }),
      H.div({
        class = 'dv-fields-right',
        H.h4({
          'Champs sélectionnés'
        }),
        H.div({
          id = 'dv-selected-fields',
          class = 'selected-fields-list',
          H.div({
            class = 'field-placeholder',
            'Aucun champ sélectionné'
          })
        }),
        H.div({
          class = 'dv-fields-info',
          H.small({
            'Cliquez sur les champs dans le graphe pour les ajouter à la vue'
          })
        })
      })
    })
  })
end
local _dataViewTabFilter
_dataViewTabFilter = function()
  return H.div({
    id = 'dv-tab-filter',
    class = 'dv-tab-content hidden'
  }, H.div({
    class = 'config-row',
    H.label({
      'Filtre MoonScript:'
    }),
    H.textarea({
      id = 'dv-filter-formula',
      rows = '6',
      placeholder = '@age > 18 and @status == "active"',
      ''
    })
  }))
end
local _dataViewTabGroup
_dataViewTabGroup = function()
  return H.div({
    id = 'dv-tab-group',
    class = 'dv-tab-content hidden',
    H.div({
      class = 'config-row',
      H.label({
        'Groupement par:'
      }),
      H.div({
        id = 'dv-groupby-fields',
        class = 'fields-container',
        H.div({
          class = 'field-group',
          H.h5({
            'Champs disponibles'
          }),
          H.div({
            id = 'dv-groupby-available',
            class = 'fields-list',
            H.div({
              class = 'field-placeholder',
              'Sélectionnez un espace...'
            })
          })
        }),
        H.div({
          class = 'field-group',
          H.h5({
            'Groupement'
          }),
          H.div({
            id = 'dv-groupby-selected',
            class = 'fields-list selected',
            H.div({
              class = 'field-placeholder',
              'Aucun groupement'
            })
          })
        })
      })
    }),
    H.div({
      class = 'config-row',
      H.label({
        'Agrégats:'
      }),
      H.div({
        id = 'dv-aggregates-list',
        class = 'dv-list',
        ''
      }),
      H.button({
        id = 'dv-add-agg-btn',
        class = 'toolbar-btn',
        '＋ Ajouter agrégat'
      })
    })
  })
end
local _dataViewModalHeader
_dataViewModalHeader = function()
  return H.div({
    class = 'modal-editor-header',
    H.span({
      class = 'modal-title',
      id = 'data-view-modal-title',
      'Configuration de la vue'
    }),
    H.div({
      class = 'modal-editor-actions',
      H.button({
        class = 'btn-primary',
        id = 'data-view-save-btn',
        '💾 Enregistrer'
      }),
      H.button({
        class = 'toolbar-btn',
        id = 'data-view-modal-close-btn',
        '✕'
      })
    })
  })
end
local _dataViewModalMainConfig
_dataViewModalMainConfig = function()
  return H.div({
    class = 'dv-main-config',
    H.div({
      class = 'config-row',
      H.label({
        ['for'] = 'dv-name',
        'Nom :'
      }),
      H.input({
        id = 'dv-name',
        type = 'text',
        placeholder = 'Ma vue'
      })
    }),
    H.div({
      class = 'config-row',
      H.label({
        ['for'] = 'dv-source',
        'Source :'
      }),
      H.select({
        id = 'dv-source',
        ''
      })
    })
  })
end
local _dataViewModalYamlEditor
_dataViewModalYamlEditor = function()
  return H.div({
    class = 'dv-yaml-editor',
    H.h4({
      'Requête YAML'
    }),
    H.div({
      id = 'dv-yaml-editor-container',
      class = 'yaml-editor-container',
      H.textarea({
        id = 'dv-yaml-content',
        class = 'yaml-editor',
        placeholder = '# Définissez votre vue ici',
        ''
      })
    }),
    H.div({
      class = 'yaml-editor-actions',
      H.button({
        id = 'dv-format-yaml-btn',
        class = 'toolbar-btn',
        '🎨 Formater'
      }),
      H.button({
        id = 'dv-apply-yaml-btn',
        class = 'btn-primary',
        '✓ Appliquer YAML'
      })
    })
  })
end
local _dataViewModalVisualEditor
_dataViewModalVisualEditor = function()
  return H.div({
    class = 'dv-visual-editor',
    H.div({
      class = 'dv-config-tabs',
      H.button({
        class = 'tab-btn active',
        ['data-tab'] = 'fields',
        'Champs'
      }),
      H.button({
        class = 'tab-btn',
        ['data-tab'] = 'filter',
        'Filtre'
      }),
      H.button({
        class = 'tab-btn',
        ['data-tab'] = 'group',
        'Groupement'
      })
    }),
    H.div({
      class = 'dv-tabs-content',
      _dataViewTabFields(),
      _dataViewTabFilter(),
      _dataViewTabGroup()
    })
  })
end
local _dataViewModalSplitLayout
_dataViewModalSplitLayout = function()
  return H.div({
    class = 'dv-split-layout',
    _dataViewModalYamlEditor(),
    _dataViewModalVisualEditor()
  })
end
local make_data_view_modal
make_data_view_modal = function()
  return H.div({
    id = 'data-view-modal',
    class = 'modal-overlay hidden',
    H.div({
      class = 'modal-box modal-box--editor modal-box--large',
      _dataViewModalHeader(),
      H.div({
        class = 'data-view-modal-body',
        _dataViewModalMainConfig(),
        _dataViewModalSplitLayout()
      })
    })
  })
end
return {
  make_data_view_modal = make_data_view_modal
}
