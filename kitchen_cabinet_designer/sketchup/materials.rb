# frozen_string_literal: true

module KitchenCabinetDesigner
  # Resolves material specs (see MaterialLibrary) to SketchUp materials.
  #
  # * "model:<name>"  - the existing model material is used unchanged;
  # * "preset:<key>"  - one material per preset, created on first use (with
  #                     its texture) and found again by an attribute tag, so
  #                     every cabinet using the preset shares it;
  # * "color:#rrggbb" - one material per colour, created on first use;
  # * "ral:<code>"    - one material per RAL colour;
  # * "user:<id>"     - one material per item of the user's library;
  # * "same:front"    - whatever the fronts use (plinth board).
  # Creation happens inside the cabinet operation, so Undo removes it.
  module Materials
    SLOTS = {
      carcass: 'carcass',
      front: 'front',
      back: 'back',
      drawer_box: 'drawer_box',
      hardware: 'hardware',
      plinth: 'plinth'
    }.freeze

    # Texture direction parameter per slot (hardware has none).
    GRAIN_KEYS = {
      carcass: 'carcass_grain', front: 'front_grain', back: 'back_grain',
      drawer_box: 'drawer_box_grain', plinth: 'plinth_grain'
    }.freeze

    FALLBACK_COLOR = '#c8c8c8'

    class << self
      # Returns { slot => Sketchup::Material } for the slots in `used`
      # (all slots when nil), so unused materials are not added to the model.
      def resolve(model, params, used = nil)
        SLOTS.each_with_object({}) do |(slot, prefix), out|
          next if used && !used.include?(slot)

          parsed = parsed_spec(params, prefix)
          next unless parsed

          out[slot] = material_for(model, parsed)
        end
      end

      # { slot => 'length' | 'width' } for slots whose texture is aligned.
      def grains(params)
        GRAIN_KEYS.each_with_object({}) do |(slot, key), out|
          value = params[key]
          value = params['front_grain'] if slot == :plinth && follows_front?(params)
          out[slot] = value if %w[length width].include?(value)
        end
      end

      # Materials of the model for the dialog: [{ 'name', 'color', 'textured' }].
      def list(model)
        return [] unless model

        model.materials.map do |m|
          { 'name' => m.name, 'color' => hex(m.color), 'textured' => !m.texture.nil? }
        end.sort_by { |m| m['name'].downcase }
      end

      private

      def follows_front?(params)
        MaterialLibrary.parse(params['plinth_material'])&.fetch(:kind) == :same
      end

      def parsed_spec(params, prefix)
        parsed = MaterialLibrary.parse(params["#{prefix}_material"])
        parsed = MaterialLibrary.parse(params['front_material']) if parsed && parsed[:kind] == :same
        parsed
      end

      def material_for(model, parsed)
        case parsed[:kind]
        when :model
          model.materials[parsed[:value]] ||
            create(model, parsed[:value], FALLBACK_COLOR, nil)
        when :color
          tagged(model, 'color', parsed[:value]) ||
            create(model, MaterialLibrary.material_name(parsed), parsed[:value], ['color', parsed[:value]])
        when :preset
          tagged(model, 'preset', parsed[:value]) || create_preset(model, parsed)
        when :ral
          tagged(model, 'ral', parsed[:value]) ||
            create(model, MaterialLibrary.material_name(parsed), RalColors.find(parsed[:value])[1],
                   ['ral', parsed[:value]])
        when :user
          tagged(model, 'user', parsed[:value]) || create_user(model, parsed)
        end
      end

      def tagged(model, key, value)
        model.materials.find { |m| m.get_attribute(DICT, key) == value }
      end

      def create_preset(model, parsed)
        preset = MaterialLibrary.preset(parsed[:value])
        path = MaterialLibrary.texture_path(preset)
        textured = path && File.exist?(path)
        # A colour set on a textured material would tint the texture.
        material = create(model, MaterialLibrary.material_name(parsed),
                          textured ? nil : preset[:color], ['preset', preset[:key]])
        if textured
          material.texture = path
          size = preset[:size].mm
          material.texture.size = [size, size] if material.texture
        end
        material
      end

      # A library item that was deleted meanwhile becomes a grey material.
      def create_user(model, parsed)
        item = UserLibrary.find(parsed[:value])
        path = UserLibrary.texture_path(item)
        textured = path && File.exist?(path)
        color = textured ? nil : (item ? item['color'] : FALLBACK_COLOR)
        material = create(model, MaterialLibrary.material_name(parsed), color, ['user', parsed[:value]])
        if textured
          material.texture = path
          size = item['size'].to_f.positive? ? item['size'].to_f.mm : UserLibrary::DEFAULT_TEXTURE_SIZE.mm
          material.texture.size = [size, size] if material.texture
        end
        material
      end

      def create(model, name, color_hex, tag)
        material = model.materials.add(name)
        if color_hex
          rgb = Validation.parse_color(color_hex) || Validation.parse_color(FALLBACK_COLOR)
          material.color = Sketchup::Color.new(*rgb)
        end
        material.set_attribute(DICT, tag[0], tag[1]) if tag
        material
      end

      def hex(color)
        format('#%02x%02x%02x', color.red, color.green, color.blue)
      rescue StandardError
        FALLBACK_COLOR
      end
    end
  end
end
