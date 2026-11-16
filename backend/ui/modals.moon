-- backend/ui/modals.moon
-- Common modals of the SPA (extracted from backend/index.moon, no functional change).

H = require 'html'

_changePasswordDialog = ->
  H.div {id: 'change-password-dialog', class: 'modal-overlay hidden',
    H.div {class: 'modal-box',
      H.h2 {'Changer le mot de passe'}
      H.input {id: 'cp-current', type: 'password', placeholder: 'Mot de passe actuel'}
      H.input {id: 'cp-new', type: 'password', placeholder: 'Nouveau mot de passe'}
      H.input {id: 'cp-confirm', type: 'password', placeholder: 'Confirmer le nouveau'}
      H.p {id: 'cp-error', class: 'error', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'cp-submit-btn', 'Enregistrer'}
        H.button {id: 'cp-cancel-btn', 'Annuler'}
      }
    }
  }

_createUserDialog = ->
  H.div {id: 'create-user-dialog', class: 'modal-overlay hidden',
    H.div {class: 'modal-box',
      H.h2 {'Créer un utilisateur'}
      H.input {id: 'cu-username', type: 'text',     placeholder: "Nom d'utilisateur"}
      H.input {id: 'cu-email',    type: 'email',    placeholder: 'Email (optionnel)'}
      H.input {id: 'cu-password', type: 'password', placeholder: 'Mot de passe'}
      H.p {id: 'cu-error', class: 'error', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'cu-submit-btn', 'Créer'}
        H.button {id: 'cu-cancel-btn', 'Annuler'}
      }
    }
  }

_createGroupDialog = ->
  H.div {id: 'create-group-dialog', class: 'modal-overlay hidden',
    H.div {class: 'modal-box',
      H.h2 {'Créer un groupe'}
      H.input {id: 'cg-name',        type: 'text', placeholder: 'Nom du groupe'}
      H.input {id: 'cg-description', type: 'text', placeholder: 'Description (optionnel)'}
      H.p {id: 'cg-error', class: 'error', ''}
      H.div {class: 'modal-actions',
        H.button {id: 'cg-submit-btn', 'Créer'}
        H.button {id: 'cg-cancel-btn', 'Annuler'}
      }
    }
  }

_yamlModal = ->
  H.div {id: 'yaml-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {id: 'yaml-modal-title', class: 'modal-title', ''}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'yaml-modal-preview-btn', class: 'toolbar-btn', '▶ Aperçu'}
          H.button {id: 'yaml-modal-save-btn', class: 'btn-primary', '💾 Enregistrer'}
          H.button {id: 'yaml-modal-close-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {class: 'yaml-modal-body',
        H.div {class: 'yaml-editor-pane',
          H.div {id: 'yaml-cm-editor', ''}
          H.div {id: 'yaml-validation-msg', class: 'yaml-validation-msg hidden', ''}
        }
        H.div {id: 'schema-browser', class: 'schema-browser', ''}
      }
    }
  }

_widgetPluginModal = ->
  H.div {id: 'widget-plugin-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Plugins widgets'}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'widget-plugin-new-btn', class: 'toolbar-btn', '＋ Nouveau'}
          H.button {id: 'widget-plugin-delete-btn', class: 'toolbar-btn toolbar-btn--danger', '🗑 Supprimer'}
          H.button {id: 'widget-plugin-save-btn', class: 'btn-primary', '💾 Enregistrer'}
          H.button {id: 'widget-plugin-modal-close-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {class: 'yaml-modal-body widget-plugin-modal-body',
        H.div {class: 'yaml-editor-pane',
          H.div {class: 'widget-plugin-meta-row',
            H.div {class: 'widget-plugin-meta-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-select', 'Plugins existants'}
              H.select {id: 'widget-plugin-select', ''}
            }
            H.div {class: 'widget-plugin-meta-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-name', 'Nom'}
              H.input {id: 'widget-plugin-name', type: 'text', placeholder: 'my_widget_plugin'}
            }
            H.div {class: 'widget-plugin-meta-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-description', 'Description'}
              H.input {id: 'widget-plugin-description', type: 'text', placeholder: 'Description'}
            }
            H.div {class: 'widget-plugin-meta-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-scope', 'Portée'}
              H.select {id: 'widget-plugin-scope',
                H.option {value: '', 'Bibliothèque (globale)'}
              }
            }
          }
          H.div {class: 'widget-plugin-editors-row',
            H.div {class: 'widget-plugin-editor-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-template-language', 'Template language'}
              H.select {id: 'widget-plugin-template-language',
                H.option {value: 'pug', 'Pug'}
                H.option {value: 'html', 'HTML'}
              }
              H.label {class: 'formula-hint', 'Template'}
              H.div {id: 'widget-plugin-template-editor', style: 'border: 1px solid #2a2a2a;', ''}
            }
            H.div {class: 'widget-plugin-editor-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-script-language', 'Script language'}
              H.select {id: 'widget-plugin-script-language',
                H.option {value: 'coffeescript', 'CoffeeScript'}
                H.option {value: 'javascript', 'JavaScript'}
              }
              H.label {class: 'formula-hint', 'Script'}
              H.div {id: 'widget-plugin-script-editor', style: 'border: 1px solid #2a2a2a;', ''}
            }
            H.div {class: 'widget-plugin-editor-col',
              H.label {class: 'formula-hint', ['for']: 'widget-plugin-manifest-editor', 'Manifest (YAML)'}
              H.div {id: 'widget-plugin-manifest-editor', style: 'border: 1px solid #2a2a2a;', ''}
            }
          }
        }
      }
    }
  }

_formulaModal = ->
  H.div {id: 'formula-modal', class: 'modal-overlay hidden',
    H.div {class: 'modal-box modal-box--editor',
      H.div {class: 'modal-editor-header',
        H.span {class: 'modal-title', 'Éditeur de formule'}
        H.div {class: 'modal-editor-actions',
          H.button {id: 'formula-modal-apply-btn', class: 'btn-primary', 'Appliquer'}
          H.button {id: 'formula-modal-close-btn', class: 'toolbar-btn', '✕'}
        }
      }
      H.div {id: 'formula-cm-editor', ''}
    }
  }

make_modals = ->
  H.div {
    _changePasswordDialog!
    _createUserDialog!
    _createGroupDialog!
    _yamlModal!
    _widgetPluginModal!
    _formulaModal!
  }

{
  make_modals: make_modals
}
