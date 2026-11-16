-- backend/ui/widget_modal.moon
-- "Add widget" modal of the SPA (extracted from backend/index.moon, no functional change).

H = require 'html'

_widgetConfigRow = (labelText, inputElement) ->
  H.div {class: 'config-row',
    H.label {labelText}
    inputElement
  }

_widgetTitleInput = ->
  H.input {type: 'text', id: 'widget-title-input', placeholder: 'Mon widget', class: 'widget-input'}

_widgetSpaceSelect = ->
  H.select {id: 'widget-space-select', class: 'widget-select',
    H.option {value: '', 'Sélectionner un espace...'}
  }

_widgetFieldsContainer = ->
  H.div {id: 'widget-fields-container', class: 'fields-container',
    H.div {class: 'fields-header',
      H.div {class: 'field-group', 'Disponibles:'}
      H.div {class: 'field-group', 'Sélectionnées:'}
    }
    H.div {class: 'fields-lists',
      H.div {id: 'available-fields', class: 'fields-list',
        H.div {class: 'field-placeholder', 'Sélectionnez un espace...'}
      }
      H.div {id: 'selected-fields', class: 'fields-list selected',
        H.div {class: 'field-placeholder', 'Aucun champ sélectionné'}
      }
    }
  }

_widgetTypeOption = (value, label, checked = false) ->
  H.div {class: 'widget-type-option',
    H.input {type: 'radio', name: 'widget-type', value: value, id: "widget-type-#{value}", checked: checked}
    H.label {['for']: "widget-type-#{value}", label}
  }

-- Groupe « Widgets personnalisés » : la liste est remplie par le frontend
-- (app_view_helpers_add_widget.coffee) à chaque ouverture de la fenêtre.
-- Markup initial : « Chargement… » remplacé par les définitions, ou par
-- « Aucun widget personnalisé », ou par un message d'erreur visible.
_widgetTypePluginsGroup = ->
  H.div {class: 'widget-type-group',
    H.h4 {class: 'widget-type-group-title', 'Widgets personnalisés'}
    H.div {id: 'widget-type-plugin-list', class: 'widget-type-plugins',
      H.div {class: 'widget-type-hint', 'Chargement…'}
    }
    H.button {id: 'widget-type-new-plugin', type: 'button',
      class: 'widget-type-new-plugin hidden', 'Nouveau widget personnalisé…'}
  }

_widgetParamRow = ->
  H.div {class: 'param-row',
    H.input {type: 'text', placeholder: 'Clé', class: 'param-key'}
    H.input {type: 'text', placeholder: 'Valeur', class: 'param-value'}
    H.button {type: 'button', class: 'param-remove-btn', '✕'}
  }

_widgetDataSourceSection = ->
  H.div {class: 'widget-section',
    H.h3 {'1. Source de données'}
    H.div {class: 'data-source-config',
      _widgetConfigRow('Titre du widget:', _widgetTitleInput!)
      _widgetConfigRow('Espace:', _widgetSpaceSelect!)
      _widgetConfigRow('Colonnes à afficher:', _widgetFieldsContainer!)
    }
  }

_widgetTypeSection = ->
  H.div {class: 'widget-section',
    H.h3 {'2. Type de widget'}
    H.div {class: 'widget-type-config',
      H.div {id: 'widget-type-options', class: 'widget-type-options',
        _widgetTypeOption('table', 'Tableau simple', true)
        _widgetTypePluginsGroup!
      }
    }
  }

_widgetParamsSection = ->
  H.div {class: 'widget-section',
    H.h3 {'3. Paramètres du widget'}
    H.div {class: 'widget-params-config',
      -- Paires clé/valeur (sans manifest) : le conteneur est masqué quand le
      -- widget choisi déclare un manifest.
      H.div {id: 'widget-params-pairs',
        H.div {id: 'widget-params-list', class: 'params-list',
          _widgetParamRow!
        }
        H.button {id: 'add-param-btn', class: 'btn-secondary', '+ Ajouter un paramètre'}
      }
      -- Formulaire tiré du manifest (colonnes de la source + options typées),
      -- rempli par app_view_helpers_add_widget.coffee.
      H.div {id: 'widget-manifest-form', class: 'widget-manifest-form hidden', ''}
      H.div {id: 'widget-manifest-hint', class: 'widget-type-hint hidden', ''}
    }
  }

make_add_widget_modal = ->
  H.div {id: 'add-widget-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Ajouter un widget'}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'add-widget-confirm-btn', class: 'btn-primary', 'Ajouter'}
          H.button {id: 'add-widget-cancel-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {class: 'add-widget-modal-body',
        _widgetDataSourceSection!
        _widgetTypeSection!
        _widgetParamsSection!
      }
    }
  }

{
  make_add_widget_modal: make_add_widget_modal
}
