# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Wall (upper) cabinet: carcass with a top panel and an optional hanging
    # rail. Local Z = 0 is the underside of the carcass; the instance is
    # placed at `mount_height` above the floor (see Placement).
    module WallCabinet
      CONTAINER = 'MOUNTING'

      class << self
        def metrics(params)
          CarcassLayout.metrics(params, 0.0, 'top_panel')
        end

        def build(params)
          parts = CarcassLayout.build(params, 0.0, 'top_panel')
          parts << hanging_rail(params, metrics(params)) if params['hanging_rail']
          parts
        end

        # Y where the rail starts: directly behind the back panel.
        def rail_y(m)
          m.back_mode == 'inset' ? m.back_y1 : m.depth
        end

        # Space behind the back panel up to the wall.
        def rail_space(params, m)
          m.depth + params['wall_gap'] - rail_y(m)
        end

        def rail_box(params, m)
          y0 = rail_y(m)
          y1 = y0 + params['rail_thickness']
          t = m.thickness
          z1 = m.height - t
          z0 = z1 - params['rail_height']
          # Entirely behind the carcass: the rail may run the full width.
          # Otherwise it sits between the side panels.
          x0, x1 = y0 >= m.depth - EPSILON ? [0.0, m.width] : [t, m.width - t]
          Box.new(x0, y0, z0, x1, y1, z1)
        end

        private

        def hanging_rail(params, m)
          PartSpec.box(name: 'HANGING_RAIL', container: CONTAINER, material: :hardware,
                       box: rail_box(params, m))
        end
      end
    end
  end
end
