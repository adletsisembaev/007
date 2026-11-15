# frozen_string_literal: true

module KitchenCabinetDesigner
  # Resolves material specs (see MaterialLibrary) to SketchUp materials.
  #
  # * "model:<name>"  - the existing model material is used unchanged;
  # * "preset:<key>"  - one material per preset, created on first use (with
  #                     its texture) and found again by an attribute tag, so
  #                     every cabinet using the preset shares it;
  # * "color:#rrggbb" - one material per colour, created on first use.
  # Creation happens inside the cabinet operation, so Undo removes it.
  module Materials
    SLOTS = {
      carcass: 'carcass',
      front: 'front',
      back: 'back',
      drawer_box: 'drawer_box',
      hardware: 'hardware'
    }.freeze

    FALLBACK_COLOR = '#c8c8c8'

    class << self
      # Returns { slot => Sketchup::Material } for the slots in `used`
      # (all slots when nil), so unused materials are not added to the model.
      def resolve(model, params, used = nil)
        SLOTS.each_with_object({}) do |(slot, prefix), out|
          next if used && !used.include?(slot)

          parsed = MaterialLibrary.parse(params["#{prefix}_material"])
          next unless parsed

          out[slot] = material_for(model, parsed)
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
        end
      end

      def tagged(model, key, value)
        model.materials.find { |m| m.get_attribute(DICT, key) == value }
      end

      def create_preset(model, parsed)
        preset = MaterialLibrary.preset(parsed[:value])
        material = create(model, MaterialLibrary.material_name(parsed), preset[:color],
                          ['preset', preset[:key]])
        path = MaterialLibrary.texture_path(preset)
        if path && File.exist?(path)
          material.texture = path
          size = preset[:size].mm
          material.texture.size = [size, size] if material.texture
        end
        material
      end

      def create(model, name, color_hex, tag)
        material = model.materials.add(name)
        rgb = Validation.parse_color(color_hex) || Validation.parse_color(FALLBACK_COLOR)
        material.color = Sketchup::Color.new(*rgb)
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
