# frozen_string_literal: true

module KitchenCabinetDesigner
  # Resolves the material slots used by PartSpec (:carcass, :front, :back,
  # :drawer_box, :hardware) to SketchUp materials.
  #
  # Rules:
  # * a material that already exists in the model under the given name is
  #   used unchanged (its colour or texture is never modified);
  # * otherwise a new material with that name and the chosen colour is
  #   created. This runs inside the cabinet operation, so Undo removes it.
  module Materials
    SLOTS = {
      carcass: 'carcass',
      front: 'front',
      back: 'back',
      drawer_box: 'drawer_box',
      hardware: 'hardware'
    }.freeze

    class << self
      # Returns { slot => Sketchup::Material } for the slots in `used`
      # (all slots when nil), so unused materials are not added to the model.
      def resolve(model, params, used = nil)
        SLOTS.each_with_object({}) do |(slot, prefix), out|
          next if used && !used.include?(slot)

          name = params["#{prefix}_material"]
          next if name.nil? || name.empty?

          out[slot] = find_or_create(model, name, params["#{prefix}_color"])
        end
      end

      # Materials of the model for the dialog: [{ 'name', 'color' }].
      def list(model)
        return [] unless model

        model.materials.map { |m| { 'name' => m.name, 'color' => hex(m.color) } }
                       .sort_by { |m| m['name'].downcase }
      end

      private

      def find_or_create(model, name, color_hex)
        existing = model.materials[name]
        return existing if existing

        material = model.materials.add(name)
        rgb = Validation.parse_color(color_hex) || [200, 200, 200]
        material.color = Sketchup::Color.new(*rgb)
        material
      end

      def hex(color)
        format('#%02x%02x%02x', color.red, color.green, color.blue)
      rescue StandardError
        '#c8c8c8'
      end
    end
  end
end
