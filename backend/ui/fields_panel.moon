-- backend/ui/fields_panel.moon
-- Fields panel of the SPA (extracted from backend/index.moon, no functional change).

H = require 'html'

FIELD_TYPE_OPTIONS = {
  {'String',   'String'}
  {'Int',      'Int'}
  {'Float',    'Float'}
  {'Boolean',  'Boolean'}
  {'UUID',     'UUID'}
  {'Any',      'Any (type libre)'}
  {'Map',      'Map (objet JSON)'}
  {'Array',    'Array (tableau JSON)'}
  {'Sequence', 'Séquence (auto-incrément)'}
  {'Datetime', 'Datetime'}
  {'Relation', 'Relation'}
}

field_type_select = ->
  opts = {id: 'field-type'}
  for {val, label} in *FIELD_TYPE_OPTIONS
    table.insert opts, H.option({value: val}, label)
  H.select opts

_fieldFormulaSection = ->
  H.div {class: 'formula-section',
    H.div {class: 'formula-type-row',
      H.label {class: 'formula-radio',
        H.input {type: 'radio', name: 'formula-type', value: 'none', checked: 'checked'}
        ' Aucune formule'
      }
      H.label {class: 'formula-radio',
        H.input {type: 'radio', name: 'formula-type', value: 'formula'}
        ' Colonne calculée'
      }
      H.label {class: 'formula-radio',
        H.input {type: 'radio', name: 'formula-type', value: 'trigger'}
        ' Trigger formula'
      }
    }
    H.div {id: 'formula-body', class: 'hidden',
      H.div {class: 'formula-lang-row',
        H.label {class: 'formula-hint', ['for']: 'formula-language', 'Langage :'}
        H.select {id: 'formula-language',
          H.option {value: 'lua',        'Lua'}
          H.option {value: 'moonscript', 'MoonScript'}
        }
      }
      H.textarea {id: 'field-formula', rows: '3',
        placeholder: "Expression (Lua : self.prenom .. ' ' .. self.nom)", ''}
      H.button {id: 'formula-expand-btn', class: 'formula-expand-btn',
        title: 'Ouvrir dans l\'éditeur', '⤢ Agrandir'}
      H.div {id: 'trigger-fields-row', class: 'hidden',
        H.label {class: 'formula-hint', ['for']: 'field-trigger-fields',
          'Déclencher quand :'}
        H.input {id: 'field-trigger-fields', type: 'text',
          placeholder: '* | nom, prenom | (vide = création seule)'}
        H.span {class: 'formula-hint',
          'Vide = création seule · '
          H.code {'*'}
          ' = tout changement · liste de champs'
        }
      }
    }
  }

_fieldReprSection = ->
  H.div {id: 'field-repr-section',
    H.label {class: 'formula-hint', ['for']: 'field-repr-formula', 'Représentation (affichage) :'}
    H.textarea {id: 'field-repr-formula', rows: '2',
      placeholder: "Ex: os.date('%d/%m/%Y', self.date) ou string.format('%.2f', self.montant)", ''}
    H.span {class: 'formula-hint', 'Formule MoonScript/Lua de rendu visuel (ne modifie pas la donnée brute).'}
  }

make_fields_panel = ->
  H.aside {id: 'fields-panel', class: 'hidden',
    H.div {class: 'fields-panel-header',
      H.span {'Champs'}
      H.button {id: 'fields-panel-close', '✕'}
    }
    H.ul {id: 'fields-list', ''}
    H.div {class: 'fields-add-form',
      H.input {id: 'field-name', type: 'text', placeholder: 'Nom du champ'}
      field_type_select!
      H.div {id: 'rel-target-row', class: 'hidden',
        H.label {class: 'formula-hint', 'Cible :'}
        H.select {id: 'rel-to-space',
          H.option {value: '', 'Cible…'}
        }
      }
      H.div {id: 'rel-repr-row', class: 'hidden',
        H.label {class: 'formula-hint', 'Représentation :'}
        H.textarea {id: 'rel-repr-formula', rows: '2',
          placeholder: "self.nom .. ' ' .. self.prenom", ''}
      }
      H.label {
        H.input {id: 'field-notnull', type: 'checkbox'}
        ' Requis'
      }
      _fieldFormulaSection!
      _fieldReprSection!
      H.div {class: 'fields-form-actions',
        H.button {id: 'field-add-btn', 'Ajouter'}
        H.button {id: 'field-cancel-btn', class: 'hidden', 'Annuler'}
      }
    }
  }

{
  make_fields_panel: make_fields_panel
}
