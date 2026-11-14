# frozen_string_literal: true

module KitchenCabinetDesigner
  # Computes where cabinet instances are placed in the model.
  #
  # Convention (see docs/ARCHITECTURE.md, section 3):
  # * the default wall is the world X axis (plane Y = 0); cabinets stand in
  #   front of it, i.e. at negative Y;
  # * the instance origin is the cabinet's front-left-bottom corner, so the
  #   origin is placed at y = -(depth + wall_gap);
  # * base cabinets: z = elevation; wall cabinets: z = mount_height.
  module Placement
    class << self
      # Transformation for a newly created cabinet. If `reference` (a cabinet
      # instance of the same category at model level) is given, the new
      # cabinet is placed directly to its right, aligned to the same wall.
      def for_new(params, reference = nil)
        ref_params = reference && CabinetBuilder.read_params(reference)
        if ref_params && ref_params['category'] == params['category']
          offset = vector_mm(
            ref_params['width'].to_f,
            wall_distance(ref_params) - wall_distance(params),
            height_reference(params) - height_reference(ref_params)
          )
          reference.transformation * Geom::Transformation.translation(offset)
        else
          Geom::Transformation.translation(
            vector_mm(0.0, -wall_distance(params), height_reference(params))
          )
        end
      end

      # Transformation of an existing instance after its parameters changed.
      # The wall plane and the left side stay where they were; the height
      # reference follows the new mount height / elevation.
      def for_update(transformation, old_params, new_params)
        offset = vector_mm(
          0.0,
          wall_distance(old_params) - wall_distance(new_params),
          height_reference(new_params) - height_reference(old_params)
        )
        transformation * Geom::Transformation.translation(offset)
      end

      private

      # Distance from the cabinet front plane (local Y = 0) to the wall.
      def wall_distance(params)
        params['depth'].to_f + params['wall_gap'].to_f
      end

      def height_reference(params)
        key = params['category'] == 'wall' ? 'mount_height' : 'elevation'
        params[key].to_f
      end

      def vector_mm(x, y, z)
        Geom::Vector3d.new(x.mm, y.mm, z.mm)
      end
    end
  end
end
