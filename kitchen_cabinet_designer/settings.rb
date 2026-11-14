# frozen_string_literal: true

require 'json'

module KitchenCabinetDesigner
  # Parameter schema, default values and persistence of last-used values.
  #
  # All lengths are millimetres (Float). The schema drives generic validation
  # (type and range checks) in Validation; construction rules that involve
  # several parameters are implemented separately in Validation.
  module Settings
    CATEGORIES = %w[base wall].freeze

    # Cabinet types. `implemented: false` types are listed in the UI as
    # "(planned)" and rejected by validation with a clear message.
    CABINET_TYPES = [
      { id: 'single_door', categories: %w[base wall], implemented: true },
      { id: 'two_doors',   categories: %w[base wall], implemented: true },
      { id: 'drawers',     categories: %w[base],      implemented: true },
      { id: 'open',        categories: %w[base wall], implemented: true },
      { id: 'corner',      categories: %w[base wall], implemented: false },
      { id: 'sink',        categories: %w[base],      implemented: false },
      { id: 'appliance',   categories: %w[base wall], implemented: false },
      { id: 'custom',      categories: %w[base wall], implemented: false }
    ].freeze

    CABINET_TYPE_IDS = CABINET_TYPES.map { |type| type[:id] }.freeze

    # Field schema.
    #   type:       :mm (Float, millimetres), :enum, :bool, :int
    #   min/max:    inclusive range for :mm and :int
    #   values:     allowed values for :enum
    #   default:    a value, or a Hash keyed by category
    #   categories: categories the field applies to (default: all)
    FIELDS = {
      'cabinet_type' => {
        type: :enum, values: CABINET_TYPE_IDS, default: 'single_door'
      },
      'width' => { type: :mm, min: 100, max: 2400, default: 600 },
      'height' => { type: :mm, min: 100, max: 2800, default: 720 },
      'depth' => {
        type: :mm, min: 100, max: 1000, default: { 'base' => 560, 'wall' => 320 }
      },
      'thickness' => { type: :mm, min: 3, max: 50, default: 16 },
      'back_thickness' => { type: :mm, min: 2, max: 25, default: 4 },
      'plinth_height' => {
        type: :mm, min: 0, max: 300, default: 100, categories: %w[base]
      },
      'elevation' => {
        type: :mm, min: 0, max: 3000, default: 0, categories: %w[base]
      },
      'mount_height' => {
        type: :mm, min: 0, max: 3000, default: 1400, categories: %w[wall]
      },
      'wall_gap' => { type: :mm, min: 0, max: 300, default: 0 }
    }.freeze

    PREFERENCES_SECTION = PLUGIN_ID

    class << self
      def cabinet_type(id)
        CABINET_TYPES.find { |type| type[:id] == id.to_s }
      end

      def applicable?(key, category)
        spec = FIELDS[key.to_s]
        return false unless spec

        cats = spec[:categories]
        cats.nil? || cats.include?(category.to_s)
      end

      def default_for(key, category)
        spec = FIELDS.fetch(key.to_s)
        value = spec[:default]
        value = value.fetch(category.to_s) if value.is_a?(Hash)
        spec[:type] == :mm ? value.to_f : value
      end

      # Complete default parameter set for a category (String keys).
      def defaults(category)
        category = category.to_s
        params = { 'category' => category }
        FIELDS.each_key do |key|
          params[key] = default_for(key, category) if applicable?(key, category)
        end
        params
      end

      # Defaults overlaid with the values the user used last time. Unknown
      # keys from older versions are dropped. Values are not validated here;
      # they are validated when a cabinet is created.
      def last_used(category)
        params = defaults(category)
        stored = read_preference("last_#{category}")
        return params unless stored.is_a?(Hash)

        stored.each do |key, value|
          params[key] = value if applicable?(key, category)
        end
        params
      end

      def save_last_used(params)
        category = params['category'].to_s
        return unless CATEGORIES.include?(category)

        write_preference("last_#{category}", params)
      end

      private

      def read_preference(name)
        return nil unless defined?(Sketchup) && Sketchup.respond_to?(:read_default)

        raw = Sketchup.read_default(PREFERENCES_SECTION, name, nil)
        raw.is_a?(String) && !raw.empty? ? JSON.parse(raw) : nil
      rescue JSON::ParserError
        nil
      end

      def write_preference(name, value)
        return unless defined?(Sketchup) && Sketchup.respond_to?(:write_default)

        Sketchup.write_default(PREFERENCES_SECTION, name, JSON.generate(value))
      end
    end
  end
end
