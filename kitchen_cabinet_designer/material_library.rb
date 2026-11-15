# frozen_string_literal: true

module KitchenCabinetDesigner
  # Built-in material presets and the material "spec" format used in params.
  #
  # A material parameter (e.g. params['front_material']) is a spec string:
  #   "preset:<key>"     - a library preset (plain colour or texture)
  #   "color:#rrggbb"    - a custom colour
  #   "model:<name>"     - an existing material of the SketchUp model
  #   "ral:<code>"       - a RAL Classic colour (see RalColors)
  #   "user:<id>"        - an item of the user's own library (UserLibrary)
  #   "same:front"       - the same material as the fronts (plinth board)
  # Older versions stored a bare material name; it is read as "model:<name>".
  #
  # Pure Ruby (no SketchUp API) so it can be unit-tested; Materials turns
  # specs into Sketchup::Material objects.
  module MaterialLibrary
    # color is the average colour, used for previews and as the material's
    # colour; texture is a file in the textures folder; size is the real
    # size of one texture tile in mm.
    PRESETS = [
      { key: 'white',       color: '#f4f4f2' },
      { key: 'ivory',       color: '#ede6d6' },
      { key: 'beige',       color: '#d9c7a7' },
      { key: 'cappuccino',  color: '#a68a6d' },
      { key: 'light_grey',  color: '#cfd1d2' },
      { key: 'grey',        color: '#8d9194' },
      { key: 'anthracite',  color: '#3c4044' },
      { key: 'black',       color: '#1e1f21' },
      { key: 'sage',        color: '#a3b09a' },
      { key: 'olive',       color: '#7d8461' },
      { key: 'navy',        color: '#283a55' },
      { key: 'terracotta',  color: '#b5653f' },
      { key: 'oak_natural', color: '#c39d6b', texture: 'oak_natural.jpg', size: 800 },
      { key: 'oak_sonoma',  color: '#d2b78e', texture: 'oak_sonoma.jpg', size: 800 },
      { key: 'ash_white',   color: '#e0dace', texture: 'ash_white.jpg', size: 800 },
      { key: 'walnut',      color: '#6c4931', texture: 'walnut.jpg', size: 800 },
      { key: 'wenge',       color: '#46342a', texture: 'wenge.jpg', size: 800 },
      { key: 'concrete',    color: '#93928e', texture: 'concrete.jpg', size: 1200 },
      { key: 'marble',      color: '#e9e7e3', texture: 'marble.jpg', size: 1200 }
    ].freeze

    PRESET_KEYS = PRESETS.map { |p| p[:key] }.freeze
    NAME_MAX = 100
    TEXTURE_DIR = File.join(PLUGIN_ROOT, 'textures').freeze

    class << self
      def preset(key)
        PRESETS.find { |p| p[:key] == key.to_s }
      end

      # Parses a spec. Returns { kind: :preset|:color|:model, value: String }
      # or nil if the spec is invalid.
      def parse(spec)
        text = spec.to_s.strip
        return nil if text.empty?

        kind, value = text.split(':', 2)
        case kind
        when 'preset' then preset(value) ? { kind: :preset, value: value } : nil
        when 'color' then color_value(value)
        when 'model' then model_value(value)
        when 'ral' then RalColors.find(value) ? { kind: :ral, value: RalColors.find(value)[0] } : nil
        when 'user' then UserLibrary::ID_PATTERN.match?(value.to_s) ? { kind: :user, value: value } : nil
        when 'same' then value == 'front' ? { kind: :same, value: 'front' } : nil
        else model_value(text) # legacy: bare material name
        end
      end

      # Normalized spec string, or nil if invalid.
      def normalize(spec)
        parsed = parse(spec)
        parsed && "#{parsed[:kind]}:#{parsed[:value]}"
      end

      # Name of the SketchUp material created for a preset or custom colour.
      def material_name(parsed)
        case parsed[:kind]
        when :preset then "KCD #{L10n.t("material.#{parsed[:value]}")}"
        when :color then "KCD #{parsed[:value]}"
        when :ral then "KCD RAL #{parsed[:value]}"
        when :user then "KCD #{UserLibrary.find(parsed[:value])&.fetch('name', nil) || parsed[:value]}"
        else parsed[:value]
        end
      end

      def texture_path(preset)
        preset[:texture] && File.join(TEXTURE_DIR, preset[:texture])
      end

      # Data for the dialog: presets with labels and thumbnails.
      def dialog_presets
        PRESETS.map do |p|
          {
            'key' => p[:key],
            'label' => L10n.t("material.#{p[:key]}"),
            'color' => p[:color],
            'texture' => p[:texture] ? "../textures/#{p[:texture]}" : nil
          }
        end
      end

      private

      def color_value(value)
        hex = value.to_s.strip.downcase
        /\A#\h{6}\z/.match?(hex) ? { kind: :color, value: hex } : nil
      end

      def model_value(value)
        name = value.to_s.strip
        return nil if name.empty? || name.length > NAME_MAX || name.match?(/[[:cntrl:]]/)

        { kind: :model, value: name }
      end
    end
  end
end
