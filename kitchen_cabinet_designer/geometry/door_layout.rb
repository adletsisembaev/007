# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Fronts: the zone covered by doors / drawer fronts, and door layout.
    #
    # Overlay fronts sit in front of the carcass (Y from -front_thickness to
    # 0) and cover it minus the edge gaps; they may be extended up or down.
    # Inset fronts sit inside the carcass opening, `inset_gap` from the
    # panels and `inset_setback` behind the front edge.
    module DoorLayout
      CONTAINER = 'FRONTS'

      class << self
        # Box covered by all fronts of the cabinet.
        def zone(params, m)
          tf = params['front_thickness']
          if params['front_mount'] == 'inset'
            gap = params['inset_gap']
            y0 = params['inset_setback']
            Box.new(m.thickness + gap, y0, m.interior_z0 + gap,
                    m.width - m.thickness - gap, y0 + tf, m.interior_z1 - gap)
          else
            Box.new(params['edge_gap_left'], -tf,
                    m.z_bottom + params['edge_gap_bottom'] - params['front_extend_bottom'],
                    m.width - params['edge_gap_right'], 0.0,
                    m.z_top - params['edge_gap_top'] + params['front_extend_top'])
          end
        end

        # Door boxes for 1 or 2 doors as [name, Box].
        def doors(params, m, count)
          z = zone(params, m)
          return [['DOOR', z]] if count == 1

          width = (z.x1 - z.x0 - params['front_gap']) / 2.0
          [
            ['DOOR_LEFT', Box.new(z.x0, z.y0, z.z0, z.x0 + width, z.y1, z.z1)],
            ['DOOR_RIGHT', Box.new(z.x1 - width, z.y0, z.z0, z.x1, z.y1, z.z1)]
          ]
        end

        def build(params, m, count)
          doors(params, m, count).map do |name, box|
            PartSpec.box(name: name, container: CONTAINER, material: :front, box: box)
          end
        end

        # Number of doors for a cabinet type (nil if the type has no doors).
        def door_count(cabinet_type)
          { 'single_door' => 1, 'two_doors' => 2 }[cabinet_type]
        end
      end
    end
  end
end
