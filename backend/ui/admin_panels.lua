local H = require('html')
local _adminUsersSection
_adminUsersSection = function()
  return H.div({
    id = 'admin-users-section',
    H.div({
      class = 'admin-section-header',
      H.h2({
        'Utilisateurs'
      }),
      H.button({
        id = 'admin-create-user-btn',
        class = 'toolbar-btn',
        '＋ Créer'
      })
    }),
    H.ul({
      id = 'admin-users-list',
      ''
    })
  })
end
local _adminGroupsSection
_adminGroupsSection = function()
  return H.div({
    id = 'admin-groups-section',
    class = 'hidden',
    H.div({
      class = 'admin-section-header',
      H.h2({
        'Groupes'
      }),
      H.button({
        id = 'admin-create-group-btn',
        class = 'toolbar-btn',
        '＋ Créer'
      })
    }),
    H.ul({
      id = 'admin-groups-list',
      ''
    })
  })
end
local _snapshotExportBox
_snapshotExportBox = function()
  return H.div({
    class = 'snapshot-export-box',
    H.h3({
      'Exporter'
    }),
    H.p({
      'Téléchargez la définition complète de l\'application sous forme de fichier YAML.'
    }),
    H.div({
      class = 'snapshot-export-options',
      H.label({
        H.input({
          id = 'snapshot-compress-checkbox',
          type = 'checkbox',
          value = 'compress'
        }),
        H.span({
          ' Compresser (zstd) - recommandé pour les exports avec données'
        })
      })
    }),
    H.div({
      class = 'snapshot-export-btns',
      H.button({
        id = 'snapshot-export-schema-btn',
        class = 'toolbar-btn',
        '⬇ Structure seule'
      }),
      H.button({
        id = 'snapshot-export-full-btn',
        class = 'toolbar-btn',
        '⬇ Structure + données'
      })
    })
  })
end
local _snapshotImportBox
_snapshotImportBox = function()
  return H.div({
    class = 'snapshot-import-box',
    H.h3({
      'Importer'
    }),
    H.p({
      'Importez un fichier .tdb.yaml exporté depuis TGui.'
    }),
    H.div({
      class = 'snapshot-import-file-row',
      H.label({
        ['for'] = 'snapshot-file-input',
        class = 'toolbar-btn',
        '📂 Choisir un fichier'
      }),
      H.input({
        id = 'snapshot-file-input',
        type = 'file',
        accept = '.yaml,.yml,.tdb.yaml,.zst,.tdb.yaml.zst',
        class = 'hidden'
      }),
      H.span({
        id = 'snapshot-file-name',
        class = 'snapshot-file-name',
        ''
      })
    }),
    H.div({
      id = 'snapshot-diff-box',
      class = 'hidden snapshot-diff-box',
      H.h4({
        'Modifications détectées'
      }),
      H.div({
        id = 'snapshot-diff-content',
        ''
      }),
      H.div({
        class = 'snapshot-import-mode',
        H.label({
          H.input({
            id = 'snapshot-mode-merge',
            type = 'radio',
            name = 'snapshot-mode',
            value = 'merge',
            checked = true
          }),
          H.span({
            ' Fusion (recommandé) — crée ce qui manque, ignore l\'existant'
          })
        })
      }),
      H.p({
        id = 'snapshot-import-error',
        class = 'error hidden',
        ''
      }),
      H.div({
        class = 'modal-actions',
        H.button({
          id = 'snapshot-import-confirm-btn',
          class = 'toolbar-btn',
          '⬆ Importer'
        })
      })
    }),
    H.div({
      id = 'snapshot-import-result',
      class = 'hidden snapshot-import-result',
      ''
    })
  })
end
local _adminSnapshotSection
_adminSnapshotSection = function()
  return H.div({
    id = 'admin-snapshot-section',
    class = 'hidden',
    H.div({
      class = 'admin-section-header',
      H.h2({
        'Export / Import'
      })
    }),
    _snapshotExportBox(),
    _snapshotImportBox()
  })
end
local _appsInstalledBox
_appsInstalledBox = function()
  return H.div({
    class = 'apps-installed-box',
    H.h3({
      'Applications installées'
    }),
    H.p({
      'Gérez les applications installées sur cette instance.'
    }),
    H.div({
      id = 'apps-list',
      class = 'apps-list',
      ''
    }),
    H.div({
      class = 'modal-actions',
      H.button({
        id = 'apps-purge-open-btn',
        class = 'toolbar-btn',
        disabled = 'disabled',
        'Éléments obsolètes…'
      })
    })
  })
end
local _appsInstallBox
_appsInstallBox = function()
  return H.div({
    class = 'apps-install-box',
    H.h3({
      'Installer ou mettre à jour'
    }),
    H.p({
      'Choisissez un paquet .tdbapp.yaml pour prévisualiser les changements avant de les appliquer.'
    }),
    H.div({
      class = 'snapshot-import-file-row',
      H.label({
        ['for'] = 'apps-package-input',
        class = 'toolbar-btn',
        '📂 Choisir un fichier'
      }),
      H.input({
        id = 'apps-package-input',
        type = 'file',
        accept = '.yaml,.yml,.tdbapp.yaml',
        class = 'hidden'
      }),
      H.span({
        id = 'apps-package-name',
        class = 'snapshot-file-name',
        ''
      })
    }),
    H.label({
      class = 'apps-downgrade-row',
      H.input({
        id = 'apps-allow-downgrade',
        type = 'checkbox'
      }),
      H.span({
        ' Autoriser une version antérieure'
      })
    }),
    H.p({
      id = 'apps-plan-errors',
      class = 'error hidden',
      ''
    }),
    H.div({
      id = 'apps-plan-box',
      class = 'hidden snapshot-diff-box',
      ''
    }),
    H.div({
      class = 'modal-actions',
      H.button({
        id = 'apps-apply-btn',
        class = 'toolbar-btn',
        disabled = 'disabled',
        'Appliquer'
      })
    }),
    H.div({
      id = 'apps-apply-report',
      class = 'hidden snapshot-import-result',
      ''
    })
  })
end
local _appsExportBox
_appsExportBox = function()
  return H.div({
    class = 'apps-export-box',
    H.h3({
      'Exporter une application'
    }),
    H.p({
      "Publiez la définition complète de l'application sous forme de paquet installable."
    }),
    H.div({
      class = 'apps-export-form',
      H.label({
        ['for'] = 'apps-export-id',
        'Identifiant (ex. org.exemple.biblio)'
      }),
      H.input({
        id = 'apps-export-id',
        type = 'text',
        placeholder = 'org.exemple.biblio'
      }),
      H.label({
        ['for'] = 'apps-export-name',
        'Nom'
      }),
      H.input({
        id = 'apps-export-name',
        type = 'text',
        placeholder = 'Ma bibliothèque'
      }),
      H.label({
        ['for'] = 'apps-export-version',
        'Version (x.y.z)'
      }),
      H.input({
        id = 'apps-export-version',
        type = 'text',
        placeholder = '1.0.0'
      }),
      H.label({
        ['for'] = 'apps-export-description',
        'Description'
      }),
      H.input({
        id = 'apps-export-description',
        type = 'text',
        placeholder = 'Description'
      }),
      H.label({
        ['for'] = 'apps-export-seed',
        "Lignes d'amorçage (une par ligne, espace:champCle)"
      }),
      H.textarea({
        id = 'apps-export-seed',
        rows = '3',
        placeholder = 'livres:isbn',
        ''
      })
    }),
    H.p({
      id = 'apps-export-error',
      class = 'error hidden',
      ''
    }),
    H.div({
      class = 'modal-actions',
      H.button({
        id = 'apps-export-btn',
        class = 'toolbar-btn',
        '⬇ Exporter le paquet'
      })
    })
  })
end
local _appsPurgeBox
_appsPurgeBox = function()
  return H.div({
    id = 'apps-purge-box',
    class = 'hidden apps-purge-box',
    H.h3({
      'Purger les éléments obsolètes'
    }),
    H.p({
      id = 'apps-purge-app-name',
      ''
    }),
    H.div({
      id = 'apps-purge-items',
      class = 'apps-purge-items',
      ''
    }),
    H.div({
      class = 'modal-actions',
      H.button({
        id = 'apps-purge-preview-btn',
        class = 'toolbar-btn',
        'Aperçu des pertes'
      })
    }),
    H.div({
      id = 'apps-purge-preview',
      class = 'hidden',
      ''
    }),
    H.label({
      ['for'] = 'apps-purge-confirm-input',
      'Saisissez exactement le nom indiqué pour confirmer'
    }),
    H.input({
      id = 'apps-purge-confirm-input',
      type = 'text',
      placeholder = ''
    }),
    H.p({
      id = 'apps-purge-confirm-hint',
      class = 'formula-hint',
      ''
    }),
    H.div({
      class = 'modal-actions',
      H.button({
        id = 'apps-purge-confirm-btn',
        class = 'toolbar-btn toolbar-btn--danger',
        disabled = 'disabled',
        'Purger définitivement'
      })
    }),
    H.div({
      id = 'apps-purge-report',
      class = 'hidden snapshot-import-result',
      ''
    })
  })
end
local _adminAppsSection
_adminAppsSection = function()
  return H.div({
    id = 'admin-apps-section',
    class = 'hidden',
    H.div({
      class = 'admin-section-header',
      H.h2({
        'Applications'
      })
    }),
    _appsInstalledBox(),
    _appsInstallBox(),
    _appsExportBox(),
    _appsPurgeBox()
  })
end
local make_admin_panel
make_admin_panel = function()
  return H.div({
    id = 'admin-panel',
    class = 'hidden admin-panel',
    _adminUsersSection(),
    _adminGroupsSection(),
    _adminSnapshotSection(),
    _adminAppsSection()
  })
end
return {
  make_admin_panel = make_admin_panel
}
