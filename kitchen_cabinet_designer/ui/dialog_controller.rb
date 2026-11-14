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
                   clear_target refresh_materials close].freeze

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
          'lastUsed' => Settings::CATEGORIES.to_h { |c| [c, Settings.last_used(c)] },
          'materials' => Materials.list(Sketchup.active_model)
        }
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
        outcome = CabinetBuilder.create(Sketchup.active_model, params)
        @edit_target = outcome.instance if outcome.ok
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
