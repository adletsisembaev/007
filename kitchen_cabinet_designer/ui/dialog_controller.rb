# frozen_string_literal: true

require 'json'

module KitchenCabinetDesigner
  # Owns the UI::HtmlDialog and the JavaScript <-> Ruby bridge.
  #
  # JavaScript calls Ruby with sketchup.<callback>(jsonString). Ruby answers
  # with KCD.receive(message), where message is a JSON object with a "type"
  # field: init, params, validation, result, status.
  module DialogController
    CALLBACKS = %w[ready validate create_cabinet update_cabinet load_selected
                   clear_target refresh_materials set_locale library_add_color
                   library_add_texture library_add_folder library_remove export close].freeze

    class << self
      # Opens the dialog (or brings it to front). With load_selection: true
      # the selected cabinet is loaded into the form for editing.
      def show(load_selection: false)
        if @dialog&.visible?
          @dialog.bring_to_front
          load_selected if load_selection
          return
        end

        @load_on_ready = load_selection
        @edit_target = nil
        @dialog = build_dialog
        @dialog.show
      end

      private

      def build_dialog
        dialog = UI::HtmlDialog.new(
          dialog_title: L10n.t('dialog.title'),
          preferences_key: "#{PLUGIN_ID}_main_dialog",
          scrollable: true,
          resizable: true,
          width: 480,
          height: 820,
          min_width: 400,
          min_height: 480,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        dialog.set_file(File.join(DIALOG_DIR, 'main.html'))
        CALLBACKS.each do |name|
          dialog.add_action_callback(name) do |_context, payload|
            safe_callback(name) { dispatch(name, payload) }
          end
        end
        dialog.set_on_closed do
          @dialog = nil
          @edit_target = nil
        end
        dialog
      end

      def dispatch(name, payload)
        case name
        when 'ready'          then on_ready
        when 'validate'       then on_validate(parse_payload(payload))
        when 'create_cabinet' then on_create(parse_payload(payload))
        when 'update_cabinet' then on_update(parse_payload(payload))
        when 'load_selected'  then load_selected
        when 'clear_target'   then @edit_target = nil
        when 'refresh_materials' then send_materials
        when 'set_locale' then on_set_locale(payload)
        when 'library_add_color' then on_library_add_color(parse_payload(payload))
        when 'library_add_texture' then on_library_add_texture
        when 'library_add_folder' then on_library_add_folder
        when 'library_remove' then on_library_remove(payload)
        when 'export' then on_export(parse_payload(payload))
        when 'close'          then @dialog&.close
        end
      end

      # Every callback is wrapped so that a Ruby exception never leaves the
      # dialog waiting; the error is reported in the dialog and in the
      # Ruby Console.
      def safe_callback(name)
        yield
      rescue StandardError => e
        warn "#{PLUGIN_NAME}: error in callback '#{name}': #{e.class}: #{e.message}"
        warn e.backtrace.first(15).join("\n") if e.backtrace
        key = e.is_a?(Geometry::LayoutError) || e.is_a?(PanelBuilder::BuildError) ? 'error.geometry' : 'error.internal'
        send_message('type' => 'result', 'ok' => false,
                     'message' => L10n.t(key, message: e.message), 'errors' => [], 'warnings' => [])
      end

      def parse_payload(payload)
        data = payload.is_a?(String) ? JSON.parse(payload) : payload
        raise ArgumentError, L10n.t('error.payload') unless data.is_a?(Hash)

        data
      rescue JSON::ParserError
        raise ArgumentError, L10n.t('error.payload')
      end

      def on_ready
        send_message(init_payload)
        if @load_on_ready
          @load_on_ready = false
          load_selected
        end
      end

      def init_payload
        {
          'type' => 'init',
          'version' => VERSION,
          'strings' => L10n.strings,
          'categories' => Settings::CATEGORIES,
          'cabinetTypes' => Settings::CABINET_TYPES.map do |type|
            { 'id' => type[:id], 'categories' => type[:categories],
              'implemented' => type[:implemented] }
          end,
          'defaults' => Settings::CATEGORIES.to_h { |c| [c, Settings.defaults(c)] },
          'lastUsed' => Settings::CATEGORIES.to_h { |c| [c, Settings.last_used(c)] }
        }.merge(locale_payload).merge(
          'materials' => Materials.list(Sketchup.active_model),
          'library' => UserLibrary.dialog_items,
          'exportOptions' => Exporter.options
        )
      end

      # Everything that depends on the interface language.
      def locale_payload
        {
          'locale' => L10n.locale,
          'locales' => L10n::AVAILABLE,
          'strings' => L10n.strings,
          'presets' => MaterialLibrary.dialog_presets,
          'ral' => RalColors.dialog_list
        }
      end

      # ---- user material library ------------------------------------------

      def on_library_add_color(data)
        item = UserLibrary.add_color(data['name'], data['color'])
        send_library(item['id'])
      rescue UserLibrary::Error
        send_status('error', L10n.t('material.custom_invalid'))
      end

      IMAGE_FILTER = 'Images|*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff||'

      def on_library_add_texture
        path = UI.openpanel(L10n.t('library.choose_image'), '', IMAGE_FILTER)
        return if path.nil? || path.empty?

        item = UserLibrary.add_texture(path)
        send_library(item['id'])
      rescue UserLibrary::Error, SystemCallError
        send_status('error', L10n.t('library.bad_image'))
      end

      def on_library_add_folder
        folder = UI.select_directory(title: L10n.t('library.choose_folder'))
        return if folder.nil? || folder.empty?

        items = UserLibrary.add_folder(folder)
        if items.empty?
          send_status('error', L10n.t('library.empty_folder'))
        else
          send_library(nil)
          send_status('ok', L10n.t('library.added_count', count: items.size))
        end
      rescue SystemCallError
        send_status('error', L10n.t('library.bad_image'))
      end

      def on_library_remove(payload)
        id = payload.to_s.delete('"')
        UserLibrary.remove(id)
        send_library(nil)
      end

      def send_library(added_id)
        send_message('type' => 'library', 'library' => UserLibrary.dialog_items, 'added' => added_id)
      end

      # ---- cut list / estimate --------------------------------------------

      def on_export(options)
        result = Exporter.run(Sketchup.active_model, options)
        level = result['level'] || (result['ok'] ? 'ok' : 'error')
        send_status(level, result['message'])
      end

      # Switches the language; the dialog re-labels itself without losing
      # the values being edited. Menu and toolbar texts change on restart.
      def on_set_locale(payload)
        code = payload.is_a?(String) ? payload.delete('"') : payload.to_s
        return unless L10n.save_locale(code)

        send_message(locale_payload.merge('type' => 'locale'))
      end

      # Validation answer, with front-view preview data when valid.
      def on_validate(params)
        result = Validation.check(params)
        message = result.to_h.merge('type' => 'validation')
        if result.ok?
          begin
            message['preview'] = Geometry::Layout.preview(result.params)
          rescue Geometry::LayoutError => e
            message['ok'] = false
            message['errors'] = [{ 'field' => nil, 'message' => L10n.t('error.geometry', message: e.message) }]
          end
        end
        send_message(message)
      end

      def send_materials
        send_message('type' => 'materials', 'materials' => Materials.list(Sketchup.active_model))
      end

      def on_create(params)
        # Creating never starts editing: Update only ever changes a cabinet the
        # user explicitly loaded with Load Selected / Edit Cabinet.
        outcome = CabinetBuilder.create(Sketchup.active_model, params)
        send_result(outcome)
      end

      def on_update(params)
        model = Sketchup.active_model
        target = @edit_target
        unless target&.valid? && target.model == model && CabinetBuilder.cabinet?(target)
          @edit_target = nil
          send_target(nil)
          send_status('error', L10n.t('msg.target_lost'))
          return
        end

        stored = CabinetBuilder.read_params(target) || {}
        if stored['category'] && stored['category'] != params['category'].to_s
          send_status('error', L10n.t('msg.category_change',
                                      category: L10n.t("category.#{stored['category']}")))
          return
        end

        if editing_inside?(model, target)
          send_status('error', L10n.t('msg.close_edit_context'))
          return
        end

        scope = ask_update_scope(target)
        if scope.nil?
          send_status('info', L10n.t('msg.cancelled'))
          return
        end

        outcome = CabinetBuilder.update(model, target, params, scope: scope)
        send_result(outcome)
      end

      # True if the user is currently editing inside this cabinet (or another
      # copy of it). Its geometry must not be regenerated in that state.
      def editing_inside?(model, instance)
        path = model.active_path
        return false if path.nil?

        path.any? { |e| e.respond_to?(:definition) && e.definition == instance.definition }
      end

      # Asks whether all copies of a shared definition should be updated.
      # Returns :all, :single or nil (cancelled).
      def ask_update_scope(instance)
        count = instance.definition.instances.size
        return :all if count <= 1

        answer = UI.messagebox(L10n.t('msg.copies', count: count), MB_YESNOCANCEL)
        case answer
        when IDYES then :all
        when IDNO then :single
        end
      end

      def load_selected
        model = Sketchup.active_model
        cabinet = CabinetBuilder.selected_cabinet(model)
        unless cabinet
          send_status('error', L10n.t('msg.no_selection'))
          return
        end

        @edit_target = cabinet
        send_message('type' => 'params', 'params' => CabinetBuilder.read_params(cabinet))
        send_target(cabinet)
        send_status('info', L10n.t('msg.loaded', name: cabinet.definition.name))
      end

      def send_result(outcome)
        send_message(outcome.to_h.merge('type' => 'result'))
        return unless outcome.ok

        send_target(@edit_target)
        send_materials
      end

      def send_target(instance)
        name = instance&.valid? ? instance.definition.name : nil
        send_message('type' => 'target', 'name' => name)
      end

      def send_status(level, text)
        send_message('type' => 'status', 'level' => level, 'message' => text)
      end

      def send_message(message)
        return unless @dialog

        @dialog.execute_script("window.KCD && KCD.receive(#{JSON.generate(message)});")
      end
    end
  end
end
