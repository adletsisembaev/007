# frozen_string_literal: true

require 'json'

module KitchenCabinetDesigner
  # Exports the cut list and the estimate of the cabinets in the model (or
  # of the selected cabinets) as two CSV files.
  module Exporter
    PREFERENCE_KEY = 'export_options'
    DEFAULTS = {
      'sheet_length' => 2800.0,
      'sheet_width' => 2070.0,
      'waste_percent' => 15.0,
      'edge_allowance_percent' => 10.0,
      'scope' => 'model'
    }.freeze
    LIMITS = {
      'sheet_length' => [100.0, 6000.0], 'sheet_width' => [100.0, 3000.0],
      'waste_percent' => [0.0, 100.0], 'edge_allowance_percent' => [0.0, 100.0]
    }.freeze

    class << self
      def options
        stored = read_options
        DEFAULTS.merge(stored.select { |k, _| DEFAULTS.key?(k) })
      end

      # Returns { 'ok', 'message' } for the dialog.
      def run(model, raw)
        opts, error = sanitize(raw)
        return { 'ok' => false, 'message' => error } if error

        save_options(opts)
        cabinets, skipped = collect(model, opts['scope'])
        return { 'ok' => false, 'message' => L10n.t('msg.export_empty') } if cabinets.empty?

        path = ask_path(model)
        return { 'ok' => false, 'message' => L10n.t('msg.cancelled_export'), 'level' => 'info' } unless path

        rows = Geometry::CutList.rows(cabinets)
        report_options = Geometry::Report::Options.new(
          sheet_length: opts['sheet_length'], sheet_width: opts['sheet_width'],
          waste_percent: opts['waste_percent'], edge_allowance_percent: opts['edge_allowance_percent']
        )
        estimate_path = "#{path.sub(/\.csv\z/i, '')}_#{L10n.t('report.file_estimate')}.csv"
        write(path, Geometry::Report.cut_list_csv(rows))
        write(estimate_path, Geometry::Report.estimate_csv(rows, Geometry::CutList.hardware(cabinets),
                                                           report_options))

        count = cabinets.sum { |c| c[:count] }
        message = L10n.t('msg.exported', count: count, parts: rows.sum(&:quantity),
                                         files: "#{File.basename(path)}, #{File.basename(estimate_path)}")
        message += "\n#{L10n.t('msg.export_skipped', names: skipped.join(', '))}" unless skipped.empty?
        { 'ok' => true, 'message' => message }
      end

      # [[{ name:, params:, count: }], skipped_names]
      def collect(model, scope)
        counts = Hash.new(0)
        if scope == 'selection'
          model.selection.each do |entity|
            counts[entity.definition] += 1 if CabinetBuilder.cabinet?(entity)
          end
        else
          model.definitions.each do |definition|
            next if definition.group? || definition.image?
            next unless definition.get_attribute(DICT, 'params')

            counts[definition] = definition.instances.size
          end
        end

        skipped = []
        cabinets = counts.select { |_, n| n.positive? }.filter_map do |definition, n|
          raw = JSON.parse(definition.get_attribute(DICT, 'params').to_s)
          result = Validation.check(raw)
          if result.ok?
            { name: definition.name, params: result.params, count: n }
          else
            skipped << definition.name
            nil
          end
        rescue JSON::ParserError
          skipped << definition.name
          nil
        end
        [cabinets.sort_by { |c| c[:name] }, skipped]
      end

      private

      def sanitize(raw)
        raw = raw.is_a?(Hash) ? raw : {}
        opts = DEFAULTS.dup
        LIMITS.each do |key, (min, max)|
          value = Validation.parse_number(raw.fetch(key, opts[key]))
          return [nil, L10n.t('error.export_option', min: Validation.fmt(min), max: Validation.fmt(max))] if value.nil? || value < min || value > max

          opts[key] = value
        end
        opts['scope'] = raw['scope'] == 'selection' ? 'selection' : 'model'
        [opts, nil]
      end

      def ask_path(model)
        title = model.title.to_s.empty? ? 'kitchen' : model.title
        directory = model.path.to_s.empty? ? '' : File.dirname(model.path)
        path = UI.savepanel(L10n.t('report.save_title'), directory, "#{title}_#{L10n.t('report.file_cut')}.csv")
        return nil if path.nil? || path.empty?

        path.end_with?('.csv') || path.end_with?('.CSV') ? path : "#{path}.csv"
      end

      # Binary mode keeps the CRLF line ends and the UTF-8 BOM exactly.
      def write(path, text)
        File.binwrite(path, text.encode('UTF-8'))
      end

      def read_options
        return {} unless defined?(Sketchup) && Sketchup.respond_to?(:read_default)

        raw = Sketchup.read_default(PLUGIN_ID, PREFERENCE_KEY, nil)
        raw.is_a?(String) && !raw.empty? ? JSON.parse(raw.unpack1('m0').force_encoding('UTF-8')) : {}
      rescue JSON::ParserError, ArgumentError
        {}
      end

      def save_options(opts)
        return unless defined?(Sketchup) && Sketchup.respond_to?(:write_default)

        Sketchup.write_default(PLUGIN_ID, PREFERENCE_KEY, [JSON.generate(opts)].pack('m0'))
      end
    end
  end
end
