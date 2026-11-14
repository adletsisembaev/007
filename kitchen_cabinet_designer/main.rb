# frozen_string_literal: true

require 'sketchup.rb'

module KitchenCabinetDesigner
  # Load order matters: pure-Ruby modules first, then SketchUp-dependent ones.
  %w[
    constants
    l10n
    settings
    validation
    geometry/part_spec
    geometry/carcass_layout
    geometry/layout
    sketchup/panel_builder
    sketchup/placement
    sketchup/cabinet_builder
    ui/dialog_controller
  ].each { |file| Sketchup.require(File.join(PLUGIN_ROOT, file)) }

  class << self
    # PNG icons are used when present (all platforms). Windows also accepts
    # the SVG source, which is the fallback before the PNGs are generated.
    def icon_path(size)
      png = File.join(ICON_DIR, "cabinet_#{size}.png")
      return png if File.exist?(png)

      File.join(ICON_DIR, 'cabinet.svg')
    end

    def build_commands
      open_cmd = UI::Command.new(L10n.t('command.open')) { DialogController.show }
      open_cmd.small_icon = icon_path(24)
      open_cmd.large_icon = icon_path(32)
      open_cmd.tooltip = L10n.t('command.open.tooltip')
      open_cmd.status_bar_text = L10n.t('command.open.status')
      open_cmd.menu_text = L10n.t('command.open')

      edit_cmd = UI::Command.new(L10n.t('command.edit')) do
        DialogController.show(load_selection: true)
      end
      edit_cmd.tooltip = L10n.t('command.edit')
      edit_cmd.status_bar_text = L10n.t('command.edit.status')
      edit_cmd.menu_text = L10n.t('command.edit')
      edit_cmd.set_validation_proc do
        model = Sketchup.active_model
        model && CabinetBuilder.selected_cabinet(model) ? MF_ENABLED : MF_GRAYED
      end

      [open_cmd, edit_cmd]
    end

    def setup_ui
      open_cmd, edit_cmd = build_commands

      submenu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
      submenu.add_item(open_cmd)
      submenu.add_item(edit_cmd)

      toolbar = UI::Toolbar.new(PLUGIN_NAME)
      toolbar.add_item(open_cmd)
      never_shown = defined?(TB_NEVER_SHOWN) ? TB_NEVER_SHOWN : -1
      if toolbar.get_last_state == never_shown
        toolbar.show
      else
        toolbar.restore
      end

      UI.add_context_menu_handler do |menu|
        model = Sketchup.active_model
        if model && CabinetBuilder.selected_cabinet(model)
          menu.add_separator
          menu.add_item(edit_cmd)
        end
      end
    end
  end

  unless file_loaded?(__FILE__)
    setup_ui
    file_loaded(__FILE__)
  end
end
