# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Carcass layout shared by base and wall cabinets.
    #
    # Joinery: side panels run the full carcass height; bottom, top (or rails)
    # and shelves sit between the sides.
    #
    # Back panel modes (see docs/ARCHITECTURE.md, section 7.2):
    #   overlay - applied to the rear; sides, bottom and top are shortened
    #             by the back thickness.
    #   inset   - placed between the panels, `back_inset` mm in front of the
    #             rear edge. Optionally held in a groove cut into the sides,
    #             the bottom and the top panel. With back_inset = 0 the groove
    #             opens to the rear edge and becomes a rebate.
    #   none    - no back panel.
    module CarcassLayout
      CONTAINER = 'CARCASS'

      # Derived values used by the layout and by Validation.
      Metrics = Struct.new(
        :width, :height, :depth, :thickness,
        :z_bottom, :z_top, :top,
        :back_mode, :back_thickness,
        :panel_depth,          # depth of sides, bottom and top
        :back_y0, :back_y1,    # back panel front / rear face (Y)
        :groove,               # true if panels are grooved
        :groove_depth,
        :groove_y0, :groove_y1, # groove (or rebate) extent along Y
        :back_overlap,         # how far the back enters each groove
        :interior_z0, :interior_z1, # clear interior height range
        :usable_depth,         # front edge to the frontmost obstacle at the back
        keyword_init: true
      )

      class << self
        # top: 'top_panel', 'rails' or 'none'
        def metrics(params, z_bottom, top)
          w = params['width']
          h = params['height']
          d = params['depth']
          t = params['thickness']
          tb = params['back_thickness']
          mode = params['back_mode']
          zc = z_bottom.to_f
          zt = zc + h

          case mode
          when 'overlay'
            panel_depth = d - tb
            y0 = d - tb
            y1 = d
          when 'inset'
            panel_depth = d
            y1 = d - params['back_inset']
            y0 = y1 - tb
          else
            panel_depth = d
            y0 = y1 = d
          end

          groove = mode == 'inset' && params['back_groove'] ? true : false
          groove_depth = groove ? params['groove_depth'] : 0.0
          groove_y0 = groove ? y0 - params['groove_extra_width'] : nil
          overlap = groove ? groove_depth - params['groove_play'] : 0.0

          Metrics.new(
            width: w, height: h, depth: d, thickness: t,
            z_bottom: zc, z_top: zt, top: top,
            back_mode: mode, back_thickness: tb,
            panel_depth: panel_depth,
            back_y0: y0, back_y1: y1,
            groove: groove, groove_depth: groove_depth,
            groove_y0: groove_y0, groove_y1: groove ? y1 : nil,
            back_overlap: overlap,
            interior_z0: zc + t,
            interior_z1: top == 'none' ? zt : zt - t,
            usable_depth: groove ? groove_y0 : y0
          )
        end

        def build(params, z_bottom, top)
          m = metrics(params, z_bottom, top)
          parts = [side(m, :left), side(m, :right), bottom(m)]
          case top
          when 'top_panel' then parts << top_panel(m)
          when 'rails' then parts.concat(rails(m, params['rail_width']))
          end
          parts << back(m) unless m.back_mode == 'none'
          parts.concat(shelves(m, params))
          parts
        end

        # Drawer cabinets have no shelves: the drawers fill the interior.
        def effective_shelf_count(params)
          params['cabinet_type'] == 'drawers' ? 0 : params['shelf_count'].to_i
        end

        # Shelf spacing (clear gap between shelves / panels) for n shelves.
        def shelf_spacing(m, count)
          clear = m.interior_z1 - m.interior_z0
          (clear - count * m.thickness) / (count + 1)
        end

        private

        def side(m, which)
          t = m.thickness
          w = m.width
          dp = m.panel_depth
          zc = m.z_bottom
          zt = m.z_top
          name = which == :left ? 'SIDE_LEFT' : 'SIDE_RIGHT'
          x0 = which == :left ? 0.0 : w - t
          x1 = x0 + t
          return panel(name, Box.new(x0, 0, zc, x1, dp, zt)) unless m.groove

          g = m.groove_depth
          gy0 = m.groove_y0
          gy1 = m.groove_y1
          if which == :left
            # Groove on the inner (right) face of the left side.
            points = [[0, 0], [t, 0], [t, gy0], [t - g, gy0], [t - g, gy1], [t, gy1],
                      [t, dp], [0, dp]]
            boxes = [Box.new(0, 0, zc, t, gy0, zt),
                     Box.new(0, gy0, zc, t - g, gy1, zt),
                     Box.new(0, gy1, zc, t, dp, zt)]
          else
            # Groove on the inner (left) face of the right side.
            points = [[x0, 0], [x1, 0], [x1, dp], [x0, dp], [x0, gy1], [x0 + g, gy1],
                      [x0 + g, gy0], [x0, gy0]]
            boxes = [Box.new(x0, 0, zc, x1, gy0, zt),
                     Box.new(x0 + g, gy0, zc, x1, gy1, zt),
                     Box.new(x0, gy1, zc, x1, dp, zt)]
          end
          PartSpec.profile(name: name, container: CONTAINER, material: :carcass,
                           plane: :xy, points: points, from: zc, to: zt,
                           boxes: solid(boxes))
        end

        def bottom(m)
          t = m.thickness
          zc = m.z_bottom
          horizontal_panel('BOTTOM', m, zc, zc + t, :top_face)
        end

        def top_panel(m)
          zt = m.z_top
          horizontal_panel('TOP', m, zt - m.thickness, zt, :bottom_face)
        end

        # Horizontal panel between the sides. When grooved, the groove is cut
        # into the face that looks into the cabinet (`groove_face`).
        def horizontal_panel(name, m, z0, z1, groove_face)
          t = m.thickness
          x0 = t
          x1 = m.width - t
          dp = m.panel_depth
          return panel(name, Box.new(x0, 0, z0, x1, dp, z1)) unless m.groove

          g = m.groove_depth
          gy0 = m.groove_y0
          gy1 = m.groove_y1
          if groove_face == :top_face
            points = [[0, z0], [dp, z0], [dp, z1], [gy1, z1], [gy1, z1 - g], [gy0, z1 - g],
                      [gy0, z1], [0, z1]]
            middle = Box.new(x0, gy0, z0, x1, gy1, z1 - g)
          else
            points = [[0, z0], [gy0, z0], [gy0, z0 + g], [gy1, z0 + g], [gy1, z0], [dp, z0],
                      [dp, z1], [0, z1]]
            middle = Box.new(x0, gy0, z0 + g, x1, gy1, z1)
          end
          boxes = [Box.new(x0, 0, z0, x1, gy0, z1), middle, Box.new(x0, gy1, z0, x1, dp, z1)]
          PartSpec.profile(name: name, container: CONTAINER, material: :carcass,
                           plane: :yz, points: points, from: x0, to: x1,
                           boxes: solid(boxes))
        end

        def rails(m, rail_width)
          t = m.thickness
          zt = m.z_top
          x0 = t
          x1 = m.width - t
          [
            panel('RAIL_FRONT', Box.new(x0, 0, zt - t, x1, rail_width, zt)),
            panel('RAIL_REAR', Box.new(x0, m.back_y0 - rail_width, zt - t, x1, m.back_y0, zt))
          ]
        end

        def back(m)
          w = m.width
          t = m.thickness
          zc = m.z_bottom
          zt = m.z_top
          box =
            if m.back_mode == 'overlay'
              Box.new(0, m.back_y0, zc, w, m.back_y1, zt)
            else
              e = m.back_overlap
              top_z = m.top == 'top_panel' ? zt - t + e : zt
              Box.new(t - e, m.back_y0, zc + t - e, w - t + e, m.back_y1, top_z)
            end
          PartSpec.box(name: 'BACK', container: CONTAINER, material: :back, box: box)
        end

        def shelves(m, params)
          count = effective_shelf_count(params)
          return [] if count <= 0

          t = m.thickness
          spacing = shelf_spacing(m, count)
          y0 = params['shelf_front_setback']
          y1 = m.back_y0
          (1..count).map do |k|
            z0 = m.interior_z0 + k * spacing + (k - 1) * t
            panel("SHELF_#{k}", Box.new(t, y0, z0, m.width - t, y1, z0 + t))
          end
        end

        def panel(name, box)
          PartSpec.box(name: name, container: CONTAINER, material: :carcass, box: box)
        end

        # Drops zero-thickness boxes produced by a rebate (groove at the edge).
        def solid(boxes)
          boxes.select { |b| b.min_size > EPSILON }
        end
      end
    end
  end
end
