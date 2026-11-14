# frozen_string_literal: true

module KitchenCabinetDesigner
  # Name of the attribute dictionary used on cabinet instances, definitions
  # and part groups.
  DICT = 'KitchenCabinetDesigner'

  # Version of the parameter format stored in the model. Increase it when the
  # stored parameters change incompatibly and add a migration in Settings.
  SCHEMA_VERSION = 1

  DIALOG_DIR = File.join(PLUGIN_ROOT, 'dialogs').freeze
  ICON_DIR   = File.join(PLUGIN_ROOT, 'icons').freeze
  LOCALE_DIR = File.join(PLUGIN_ROOT, 'locales').freeze
end
