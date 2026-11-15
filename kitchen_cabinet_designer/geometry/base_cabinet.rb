# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Base (lower) cabinet: carcass standing on legs and/or plinth boards.
    #
    # Local Z = 0 is the floor. The carcass starts at the support height.
    # Support types:
    #   legs             - cylindrical adjustable feet
    #   legs_with_plinth - feet plus a front plinth board (toe kick)
    #   plinth_box       - front and rear plinth boards, no feet
    #   none             - carcass directly at Z = 0
    module BaseCabinet
      CONTAINER = 'SUPPORTS'
      LEG_SEGMENTS = 24

      class << self
        def support_height(params)
          params['support_type'] == 'none' ? 0.0 : params['plinth_height'].to_f
        end

        def legs?(params)
          %w[legs legs_with_plinth].include?(params['support_type'])
        end

        def front_plinth?(params)
          %w[legs_with_plinth plinth_box].include?(params['support_type'])
        end

        def metrics(params)
          CarcassLayout.metrics(params, support_height(params), params['top_construction'])
        end

        def build(params)
          zc = support_height(params)
          parts = CarcassLayout.build(params, zc, params['top_construction'])
          parts.concat(supports(params, metrics(params)))
          parts
        end

        # Leg centres as [name, x, y]. Front-left, front-right, rear-left,
        # rear-right, then the middle pair for wide cabinets.
        def leg_positions(params, panel_depth)
          w = params['width']
          xs = params['leg_offset_side']
          yf = params['leg_offset_front']
          yr = panel_depth - params['leg_offset_rear']
          positions = [[xs, yf], [w - xs, yf], [xs, yr], [w - xs, yr]]
          positions += [[w / 2.0, yf], [w / 2.0, yr]] if middle_legs?(params)
          positions.each_with_index.map { |(x, y), i| ["LEG_#{i + 1}", x, y] }
        end

        def middle_legs?(params)
          params['middle_legs_from'].to_f.positive? && params['width'] >= params['middle_legs_from']
        end

        private

        def supports(params, m)
          zc = m.z_bottom
          return [] if zc <= 0

          parts = []
          if legs?(params)
            radius = params['leg_diameter'] / 2.0
            leg_positions(params, m.panel_depth).each do |name, x, y|
              parts << PartSpec.cylinder(name: name, container: CONTAINER, material: :hardware,
                                         center: [x, y], radius: radius, z0: 0, z1: zc,
                                         segments: LEG_SEGMENTS)
            end
          end
          if front_plinth?(params)
            y0 = params['plinth_setback']
            parts << plinth('PLINTH_FRONT', Box.new(0, y0, 0, m.width, y0 + params['plinth_thickness'], zc))
          end
          if params['support_type'] == 'plinth_box'
            dp = m.panel_depth
            parts << plinth('PLINTH_REAR', Box.new(0, dp - params['plinth_thickness'], 0, m.width, dp, zc))
          end
          parts
        end

        def plinth(name, box)
          PartSpec.box(name: name, container: CONTAINER, material: :plinth, box: box)
        end
      end
    end
  end
end
