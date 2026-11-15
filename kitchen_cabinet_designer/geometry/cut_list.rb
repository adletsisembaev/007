# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Cut list (detail list for sawing and edge banding) and estimate
    # (materials, edge banding, hardware) computed from cabinet parameters.
    #
    # Sizes are finished sizes (as modelled). "Cut size" subtracts edge
    # banding of EDGE_SUBTRACT_FROM mm or thicker from the sides it covers,
    # as is usual for 1-2 mm PVC/ABS edges; thin 0.4 mm edges are not
    # subtracted. Edge naming: L1/L2 = the two long edges, W1/W2 = the two
    # short edges (in Russian cutting practice "Д1, Д2, Ш1, Ш2").
    module CutList
      EDGE_SUBTRACT_FROM = 1.0
      PANEL_SLOTS = %i[carcass front back drawer_box plinth].freeze
      FRONT_ROLES = %w[DOOR DOOR_LEFT DOOR_RIGHT BLIND_PANEL DRAWER_FRONT].freeze
      CARCASS_FRONT_EDGE = /\A(SIDE_LEFT|SIDE_RIGHT|BOTTOM|TOP|RAIL_FRONT|SHELF_\d+)\z/
      BOX_TOP_EDGE = /\A(BOX_SIDE_LEFT|BOX_SIDE_RIGHT|BOX_FRONT|BOX_BACK)\z/
      GRAIN_KEYS = {
        carcass: 'carcass_grain', front: 'front_grain', back: 'back_grain',
        drawer_box: 'drawer_box_grain', plinth: 'plinth_grain'
      }.freeze

      # One line of the cut list.
      Row = Struct.new(:material, :thickness, :length, :width, :edges, :grain,
                       :quantity, :parts, keyword_init: true) do
        def cut_length
          length - subtract(edges[:w1]) - subtract(edges[:w2])
        end

        def cut_width
          width - subtract(edges[:l1]) - subtract(edges[:l2])
        end

        # Total edge length per edge thickness for one part, in mm.
        def edge_lengths
          totals = Hash.new(0.0)
          totals[edges[:l1]] += length if edges[:l1].positive?
          totals[edges[:l2]] += length if edges[:l2].positive?
          totals[edges[:w1]] += width if edges[:w1].positive?
          totals[edges[:w2]] += width if edges[:w2].positive?
          totals
        end

        def area_m2
          length * width * quantity / 1_000_000.0
        end

        private

        def subtract(edge)
          edge >= EDGE_SUBTRACT_FROM ? edge : 0.0
        end
      end

      class << self
        # cabinets: [{ name:, params:, count: }]
        # Returns merged rows: identical parts (material, size, edges,
        # grain) are counted together.
        def rows(cabinets)
          merged = {}
          cabinets.each do |cabinet|
            Layout.build(cabinet[:params]).each do |spec|
              next unless PANEL_SLOTS.include?(spec.material)

              row = part_row(cabinet[:params], spec)
              key = [row.material, row.thickness, row.length, row.width, row.edges.values, row.grain]
              target = merged[key] ||= row.tap { |r| r.quantity = 0 }
              target.quantity += cabinet[:count]
              target.parts << "#{cabinet[:name]}: #{spec.name}" unless target.parts.include?("#{cabinet[:name]}: #{spec.name}")
            end
          end
          merged.values.sort_by { |r| [r.material, -r.thickness, -r.length, -r.width] }
        end

        # Board materials: { [material, thickness] => area_m2 }.
        def board_areas(rows)
          rows.each_with_object(Hash.new(0.0)) { |r, out| out[[r.material, r.thickness]] += r.area_m2 }
        end

        # Edge banding: { [material, edge_thickness] => length_m }.
        def edge_totals(rows)
          rows.each_with_object(Hash.new(0.0)) do |r, out|
            r.edge_lengths.each { |edge, mm| out[[r.material, edge]] += mm * r.quantity / 1000.0 }
          end
        end

        def sheets(area_m2, sheet_length, sheet_width, waste_percent)
          sheet = sheet_length * sheet_width / 1_000_000.0
          return 0 if sheet <= 0 || area_m2 <= 0

          (area_m2 * (1 + waste_percent / 100.0) / sheet).ceil
        end

        # Hardware: { key => quantity } plus slide lengths and rail metres.
        def hardware(cabinets)
          totals = Hash.new(0)
          slides = Hash.new(0)
          rail_m = 0.0
          cabinets.each do |cabinet|
            n = cabinet[:count]
            Layout.build(cabinet[:params]).each do |spec|
              size = spec.bounds.size
              case spec.role
              when 'DOOR', 'DOOR_LEFT', 'DOOR_RIGHT'
                totals[:hinges] += hinges_for(size[2]) * n
                totals[:handles] += n
              when 'DRAWER_FRONT'
                totals[:handles] += n
              when 'BOX_SIDE_LEFT'
                slides[size[1].round] += n
              when 'SHELF_1', /\ASHELF_\d+\z/
                totals[:shelf_supports] += 4 * n
              when /\ALEG_\d+\z/
                totals[:legs] += n
              when 'HANGING_RAIL'
                rail_m += size[0] * n / 1000.0
              end
            end
            totals[:wall_hangers] += 2 * n if cabinet[:params]['category'] == 'wall'
          end
          { counts: totals, slides: slides, rail_m: rail_m }
        end

        # Usual number of hinges for a door of this height.
        def hinges_for(height)
          if height <= 900 then 2
          elsif height <= 1600 then 3
          elsif height <= 2000 then 4
          else 5
          end
        end

        def material_label(params, slot)
          spec = params["#{slot}_material"]
          parsed = MaterialLibrary.parse(spec)
          parsed = MaterialLibrary.parse(params['front_material']) if parsed && parsed[:kind] == :same
          return '-' unless parsed

          case parsed[:kind]
          when :preset then L10n.t("material.#{parsed[:value]}")
          when :color then L10n.t('material.custom_label', hex: parsed[:value])
          when :ral then RalColors.label(RalColors.find(parsed[:value]))
          when :user then UserLibrary.find(parsed[:value])&.fetch('name', nil) || parsed[:value]
          else parsed[:value]
          end
        end

        private

        def part_row(params, spec)
          size = spec.bounds.size
          long_axis, width_axis, thick_axis = [0, 1, 2].sort_by { |i| [-size[i], i] }
          edges = { l1: 0.0, l2: 0.0, w1: 0.0, w2: 0.0 }
          thickness_param, faces = edge_rule(spec.role, long_axis, width_axis)
          edge = thickness_param ? params[thickness_param].to_f : 0.0
          if edge.positive?
            faces.each do |axis, sign|
              next if axis == thick_axis

              key = if axis == width_axis
                      sign.negative? ? :l1 : :l2
                    else
                      sign.negative? ? :w1 : :w2
                    end
              edges[key] = edge
            end
          end
          Row.new(material: material_label(params, spec.material),
                  thickness: size[thick_axis].round(1), length: size[long_axis].round(1),
                  width: size[width_axis].round(1), edges: edges,
                  grain: grain_for(params, spec.material), quantity: 0, parts: [])
        end

        # [edge thickness parameter, faces as [axis, sign]] for a role.
        def edge_rule(role, long_axis, width_axis)
          if FRONT_ROLES.include?(role)
            ['edge_front', [[long_axis, -1], [long_axis, 1], [width_axis, -1], [width_axis, 1]]]
          elsif CARCASS_FRONT_EDGE.match?(role)
            ['edge_carcass', [[1, -1]]]
          elsif BOX_TOP_EDGE.match?(role)
            ['edge_box', [[2, 1]]]
          else
            [nil, []]
          end
        end

        def grain_for(params, slot)
          key = GRAIN_KEYS[slot]
          grain_key = slot == :plinth && MaterialLibrary.parse(params['plinth_material'])&.fetch(:kind) == :same ? 'front_grain' : key
          value = params[grain_key]
          %w[length width].include?(value) && textured?(params, slot) ? value : nil
        end

        def textured?(params, slot)
          parsed = MaterialLibrary.parse(params["#{slot}_material"])
          parsed = MaterialLibrary.parse(params['front_material']) if parsed && parsed[:kind] == :same
          return false unless parsed

          case parsed[:kind]
          when :preset then !MaterialLibrary.preset(parsed[:value])[:texture].nil?
          when :user then UserLibrary.find(parsed[:value])&.fetch('kind', nil) == 'texture'
          when :model then true # unknown here; the grain setting is kept
          else false
          end
        end
      end
    end
  end
end
