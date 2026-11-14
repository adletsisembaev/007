# frozen_string_literal: true

# Kitchen Cabinet Designer - SketchUp extension loader.
#
# This file is placed directly in the SketchUp "Plugins" folder. It only
# registers the extension; the actual code lives in the
# "kitchen_cabinet_designer" sub-folder and is loaded by SketchUp when the
# extension is enabled in the Extension Manager.

require 'sketchup.rb'
require 'extensions.rb'

module KitchenCabinetDesigner
  PLUGIN_ID   = 'kitchen_cabinet_designer'
  PLUGIN_NAME = 'Kitchen Cabinet Designer'
  VERSION     = '1.0.0'

  # Paths may contain non-ASCII characters (e.g. Windows user names).
  loader_file = __FILE__.dup
  loader_file.force_encoding('UTF-8') if loader_file.respond_to?(:force_encoding)

  PLUGIN_ROOT = File.join(File.dirname(loader_file), PLUGIN_ID).freeze

  unless file_loaded?(loader_file)
    extension = SketchupExtension.new(PLUGIN_NAME, File.join(PLUGIN_ROOT, 'main'))
    extension.description = 'Parametric base and wall kitchen cabinets: carcass, ' \
                            'back panel, plinth, doors and drawers.'
    extension.version     = VERSION
    extension.creator     = 'Kitchen Cabinet Designer'
    extension.copyright   = '2026'
    Sketchup.register_extension(extension, true)
    file_loaded(loader_file)
  end
end
