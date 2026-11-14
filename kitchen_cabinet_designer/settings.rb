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
    #   type:       :mm (Float, millimetres), :enum, :bool, :int, :text,
    #               :material (material name), :color ("#rrggbb")
    #   min/max:    inclusive range for :mm and :int
    #   values:     allowed values for :enum
    #   default:    a value, or a Hash keyed by category
    #   categories: categories the field applies to (default: all)
    FIELDS = {
      'cabinet_type' => {
        type: :enum, values: CABINET_TYPE_IDS, default: 'single_door'
      },

      # Dimensions
      'width' => { type: :mm, min: 100, max: 2400, default: 600 },
      'height' => { type: :mm, min: 100, max: 2800, default: 720 },
      'depth' => {
        type: :mm, min: 100, max: 1000, default: { 'base' => 560, 'wall' => 320 }
      },

      # Carcass construction
      'thickness' => { type: :mm, min: 3, max: 50, default: 16 },
      'top_construction' => {
        type: :enum, values: %w[top_panel rails none], default: 'rails', categories: %w[base]
      },
      'rail_width' => { type: :mm, min: 30, max: 300, default: 100, categories: %w[base] },
      'back_mode' => { type: :enum, values: %w[overlay inset none], default: 'overlay' },
      'back_thickness' => { type: :mm, min: 2, max: 25, default: 4 },
      'back_inset' => { type: :mm, min: 0, max: 200, default: 10 },
      'back_groove' => { type: :bool, default: false },
      'groove_depth' => { type: :mm, min: 1, max: 30, default: 8 },
      'groove_play' => { type: :mm, min: 0, max: 10, default: 1 },
      'groove_extra_width' => { type: :mm, min: 0, max: 3, default: 0.5 },
      'shelf_count' => { type: :int, min: 0, max: 10, default: 1 },
      'shelf_front_setback' => { type: :mm, min: 0, max: 300, default: 0 },

      # Doors and fronts
      'front_mount' => { type: :enum, values: %w[overlay inset], default: 'overlay' },
      'front_thickness' => { type: :mm, min: 3, max: 50, default: 18 },
      'front_gap' => { type: :mm, min: 0, max: 20, default: 2 },
      'edge_gap_left' => { type: :mm, min: 0, max: 20, default: 1 },
      'edge_gap_right' => { type: :mm, min: 0, max: 20, default: 1 },
      'edge_gap_top' => { type: :mm, min: 0, max: 20, default: 1 },
      'edge_gap_bottom' => { type: :mm, min: 0, max: 20, default: 1 },
      'front_extend_top' => { type: :mm, min: 0, max: 200, default: 0 },
      'front_extend_bottom' => { type: :mm, min: 0, max: 200, default: 0 },
      'inset_gap' => { type: :mm, min: 0, max: 20, default: 2 },
      'inset_setback' => { type: :mm, min: 0, max: 50, default: 0 },

      # Drawers (base cabinets only)
      'drawer_count' => { type: :int, min: 1, max: 8, default: 3, categories: %w[base] },
      'drawer_heights' => { type: :text, max_length: 200, default: '', categories: %w[base] },
      'drawer_box_height' => { type: :mm, min: 0, max: 600, default: 0, categories: %w[base] },
      'drawer_box_depth' => { type: :mm, min: 0, max: 1000, default: 0, categories: %w[base] },
      'drawer_side_thickness' => { type: :mm, min: 3, max: 30, default: 16, categories: %w[base] },
      'drawer_bottom_thickness' => { type: :mm, min: 2, max: 25, default: 4, categories: %w[base] },
      'slide_clearance' => { type: :mm, min: 0, max: 50, default: 13, categories: %w[base] },
      'slide_depth_clearance' => { type: :mm, min: 0, max: 200, default: 30, categories: %w[base] },
      'drawer_front_clearance' => { type: :mm, min: 0, max: 50, default: 2, categories: %w[base] },
      'drawer_bottom_clearance' => { type: :mm, min: 0, max: 100, default: 15, categories: %w[base] },
      'drawer_top_clearance' => { type: :mm, min: 0, max: 100, default: 30, categories: %w[base] },

      # Base cabinet supports
      'support_type' => {
        type: :enum, values: %w[legs legs_with_plinth plinth_box none],
        default: 'legs_with_plinth', categories: %w[base]
      },
      'plinth_height' => { type: :mm, min: 0, max: 300, default: 100, categories: %w[base] },
      'plinth_setback' => { type: :mm, min: 0, max: 200, default: 50, categories: %w[base] },
      'plinth_thickness' => { type: :mm, min: 3, max: 50, default: 16, categories: %w[base] },
      'leg_diameter' => { type: :mm, min: 10, max: 120, default: 40, categories: %w[base] },
      'leg_offset_side' => { type: :mm, min: 0, max: 300, default: 50, categories: %w[base] },
      'leg_offset_front' => { type: :mm, min: 0, max: 500, default: 100, categories: %w[base] },
      'leg_offset_rear' => { type: :mm, min: 0, max: 500, default: 60, categories: %w[base] },
      'middle_legs_from' => { type: :mm, min: 0, max: 2400, default: 800, categories: %w[base] },

      # Wall cabinet mounting
      'hanging_rail' => { type: :bool, default: false, categories: %w[wall] },
      'rail_height' => { type: :mm, min: 10, max: 200, default: 50, categories: %w[wall] },
      'rail_thickness' => { type: :mm, min: 2, max: 50, default: 10, categories: %w[wall] },

      # Materials: an existing model material is used as-is; otherwise a
      # material with this name is created with the given colour.
      'carcass_material' => { type: :material, default: 'KCD Carcass' },
      'carcass_color' => { type: :color, default: '#ede9e2' },
      'front_material' => { type: :material, default: 'KCD Front' },
      'front_color' => { type: :color, default: '#c9a46b' },
      'back_material' => { type: :material, default: 'KCD Back' },
      'back_color' => { type: :color, default: '#f4f1ea' },
      'drawer_box_material' => { type: :material, default: 'KCD Drawer Box', categories: %w[base] },
      'drawer_box_color' => { type: :color, default: '#e2dacb', categories: %w[base] },
      'hardware_material' => { type: :material, default: 'KCD Hardware' },
      'hardware_color' => { type: :color, default: '#6b7078' },

      # Placement
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
        case spec[:type]
        when :mm then value.to_f
        when :int then value.to_i
        else value
        end
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
