# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Drawer fronts and drawer boxes (see docs/ARCHITECTURE.md, section 7.6).
    #
    # Front heights are listed top to bottom in `drawer_heights`
    # ("140; 140; 0"). A value of 0 or an empty list means "auto": the height
    # left after the fixed fronts and the gaps is shared equally.
    #
    # Each drawer is its own group DRAWER_<n> containing DRAWER_FRONT_<n> and
    # a DRAWER_BOX_<n> group with BOX_BOTTOM, BOX_SIDE_LEFT, BOX_SIDE_RIGHT,
    # BOX_FRONT and BOX_BACK. The box bottom sits under the sides, front and
    # back (applied bottom).
    module DrawerLayout
      MIN_FRONT_HEIGHT = 50.0
      MIN_BOX_HEIGHT = 60.0
      MIN_BOX_DEPTH = 150.0
      MIN_BOX_INNER_WIDTH = 50.0
      SLIDE_LENGTH_STEP = 50.0
      SUM_TOLERANCE = 0.1

      Drawer = Struct.new(:index, :front, :box_x0, :box_x1, :box_y0, :box_depth,
                          :box_z0, :box_height, keyword_init: true)

      # Result of planning: drawers, or problems as [field, l10n_key, vars].
      Plan = Struct.new(:drawers, :problems, keyword_init: true) do
        def ok?
          problems.empty?
        end
      end

      class << self
        def plan(params, m)
          problems = []
          zone = DoorLayout.zone(params, m)
          heights = front_heights(params, zone, problems)
          return Plan.new(drawers: [], problems: problems) unless problems.empty?

          fronts = stack_fronts(zone, heights, params['front_gap'])
          box = box_footprint(params, m, problems)
          return Plan.new(drawers: [], problems: problems) unless problems.empty?

          drawers = fronts.each_with_index.map do |front, i|
            z0, height = box_vertical(params, m, front, i, problems)
            Drawer.new(index: i + 1, front: front, box_x0: box[:x0], box_x1: box[:x1],
                       box_y0: box[:y0], box_depth: box[:depth], box_z0: z0, box_height: height)
          end
          Plan.new(drawers: drawers, problems: problems)
        end

        def build(params, m)
          result = plan(params, m)
          unless result.ok?
            field, key, = result.problems.first
            raise LayoutError, "Invalid drawer configuration (#{field}: #{key})"
          end

          result.drawers.flat_map { |drawer| drawer_parts(params, drawer) }
        end

        # Parses "140; 140; 0" into [140.0, 140.0, 0.0]. Returns nil on error.
        def parse_heights(text)
          tokens = text.to_s.strip.split(/[;\s]+/).reject(&:empty?)
          tokens.map do |token|
            value = Float(token.tr(',', '.'))
            return nil unless value.finite? && value >= 0

            value
          end
        rescue ArgumentError
          nil
        end

        # Largest standard slide length (multiple of 50 mm) that fits.
        def auto_depth(available)
          (available / SLIDE_LENGTH_STEP).floor * SLIDE_LENGTH_STEP
        end

        private

        def front_heights(params, zone, problems)
          count = params['drawer_count']
          values = parse_heights(params['drawer_heights'])
          if values.nil?
            problems << ['drawer_heights', 'error.drawer_heights_format', {}]
            return nil
          end
          values = Array.new(count, 0.0) if values.empty?
          if values.size != count
            problems << ['drawer_heights', 'error.drawer_heights_count',
                         { count: count, given: values.size }]
            return nil
          end

          available = zone.z1 - zone.z0 - (count - 1) * params['front_gap']
          fixed = values.reject(&:zero?)
          autos = values.count(&:zero?)
          if autos.zero?
            if (fixed.sum - available).abs > SUM_TOLERANCE
              problems << ['drawer_heights', 'error.drawer_heights_sum',
                           { sum: fixed.sum, expected: available }]
              return nil
            end
            heights = values
          else
            auto = (available - fixed.sum) / autos
            heights = values.map { |v| v.zero? ? auto : v }
          end

          if heights.min < MIN_FRONT_HEIGHT
            problems << ['drawer_heights', 'error.drawer_front_small',
                         { min: MIN_FRONT_HEIGHT, value: heights.min }]
            return nil
          end
          heights
        end

        # Front boxes from top to bottom.
        def stack_fronts(zone, heights, gap)
          top = zone.z1
          heights.map do |h|
            box = Box.new(zone.x0, zone.y0, top - h, zone.x1, zone.y1, top)
            top = top - h - gap
            box
          end
        end

        def box_footprint(params, m, problems)
          t = m.thickness
          x0 = t + params['slide_clearance']
          x1 = m.width - t - params['slide_clearance']
          if x1 - x0 - 2 * params['drawer_side_thickness'] < MIN_BOX_INNER_WIDTH
            problems << ['slide_clearance', 'error.drawer_width', { min: MIN_BOX_INNER_WIDTH }]
            return nil
          end

          y0 = params['drawer_front_clearance']
          y0 += params['inset_setback'] + params['front_thickness'] if params['front_mount'] == 'inset'
          limit = m.depth - params['slide_depth_clearance']
          available = [limit - y0, m.usable_depth - y0].min
          depth = params['drawer_box_depth']
          if depth.zero?
            depth = auto_depth(available)
          elsif depth > available + EPSILON
            problems << ['drawer_box_depth', 'error.drawer_depth', { max: available }]
            return nil
          end
          if depth < MIN_BOX_DEPTH
            problems << ['drawer_box_depth', 'error.drawer_depth_small', { min: MIN_BOX_DEPTH }]
            return nil
          end
          { x0: x0, x1: x1, y0: y0, depth: depth }
        end

        # Vertical position of the box behind front i: [z0, height].
        def box_vertical(params, m, front, index, problems)
          z0 = [front.z0, m.interior_z0].max + params['drawer_bottom_clearance']
          z_limit = [front.z1 - params['drawer_top_clearance'], m.interior_z1].min
          available = z_limit - z0
          height = params['drawer_box_height'].zero? ? available : params['drawer_box_height']
          if height > available + EPSILON
            problems << ['drawer_box_height', 'error.drawer_box_tall',
                         { index: index + 1, max: available }]
          elsif height < MIN_BOX_HEIGHT
            problems << ['drawer_heights', 'error.drawer_box_low',
                         { index: index + 1, value: height, min: MIN_BOX_HEIGHT }]
          end
          [z0, height]
        end

        def drawer_parts(params, d)
          n = d.index
          container = "DRAWER_#{n}"
          box_container = "#{container}/DRAWER_BOX_#{n}"
          ts = params['drawer_side_thickness']
          tb = params['drawer_bottom_thickness']
          x0 = d.box_x0
          x1 = d.box_x1
          y0 = d.box_y0
          y1 = y0 + d.box_depth
          z0 = d.box_z0
          zb = z0 + tb
          z1 = z0 + d.box_height

          [
            PartSpec.box(name: "DRAWER_FRONT_#{n}", container: container, material: :front,
                         role: 'DRAWER_FRONT', box: d.front),
            box_part('BOX_BOTTOM', box_container, Box.new(x0, y0, z0, x1, y1, zb)),
            box_part('BOX_SIDE_LEFT', box_container, Box.new(x0, y0, zb, x0 + ts, y1, z1)),
            box_part('BOX_SIDE_RIGHT', box_container, Box.new(x1 - ts, y0, zb, x1, y1, z1)),
            box_part('BOX_FRONT', box_container, Box.new(x0 + ts, y0, zb, x1 - ts, y0 + ts, z1)),
            box_part('BOX_BACK', box_container, Box.new(x0 + ts, y1 - ts, zb, x1 - ts, y1, z1))
          ]
        end

        def box_part(name, container, box)
          PartSpec.box(name: name, container: container, material: :drawer_box, box: box)
        end
      end
    end
  end
end
