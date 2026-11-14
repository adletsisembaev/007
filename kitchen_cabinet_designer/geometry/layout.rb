# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Entry point of the geometry layer: turns validated parameters into the
    # complete list of PartSpec objects for one cabinet.
    module Layout
      class << self
        def build(params)
          parts =
            case params['category']
            when 'base' then build_base(params)
            when 'wall' then build_wall(params)
            else raise LayoutError, "Unknown category #{params['category'].inspect}"
            end
          parts.concat(fronts(params, metrics(params)))
          verify!(parts)
          parts
        end

        # Z of the carcass bottom in local coordinates.
        def carcass_bottom(params)
          params['category'] == 'base' ? BaseCabinet.support_height(params) : 0.0
        end

        # Carcass metrics (see CarcassLayout::Metrics) for either category.
        def metrics(params)
          params['category'] == 'base' ? BaseCabinet.metrics(params) : WallCabinet.metrics(params)
        end

      # Front-view preview data for the dialog: one rectangle per part,
      # projected on the XZ plane, farthest parts first.
      def preview(params)
        specs = build(params)
        overall = specs.map(&:bounds).reduce(:union)
        rects = specs.sort_by { |s| -s.bounds.y0 }.map do |spec|
          b = spec.bounds
          { 'name' => spec.name, 'slot' => spec.material.to_s,
            'shape' => spec.shape_type.to_s,
            'x0' => b.x0, 'z0' => b.z0, 'x1' => b.x1, 'z1' => b.z1 }
        end
        { 'bounds' => overall.to_a.values_at(0, 2, 3, 5), 'rects' => rects }
      end

        # Doors or drawers depending on the cabinet type.
        def fronts(params, m)
          doors = DoorLayout.door_count(params['cabinet_type'])
          return DoorLayout.build(params, m, doors) if doors
          return DrawerLayout.build(params, m) if params['cabinet_type'] == 'drawers'

          []
        end

        private

        def build_base(params)
          BaseCabinet.build(params)
        end

        def build_wall(params)
          WallCabinet.build(params)
        end

        # Last line of defence before geometry is created: every part must
        # have a real thickness and a unique name inside its container.
        def verify!(parts)
          parts.each do |part|
            next if part.min_size >= 0.5

            raise LayoutError, "#{part.name} is thinner than 0.5 mm (#{part.min_size.round(3)} mm)"
          end
          duplicates = parts.group_by { |p| [p.container, p.name] }.select { |_, v| v.size > 1 }
          return if duplicates.empty?

          raise LayoutError, "Duplicate part names: #{duplicates.keys.map(&:last).join(', ')}"
        end
      end
    end
  end
end
