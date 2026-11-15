# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # CSV texts for the cut list and the estimate.
    #
    # Russian: ";" separator and decimal comma (what Russian Excel expects);
    # English: "," and decimal point. Files start with a UTF-8 BOM so Excel
    # detects the encoding. The estimate uses only cell multiplication and
    # addition in formulas (no function names, which Excel localizes).
    module Report
      BOM = "﻿"

      Options = Struct.new(:sheet_length, :sheet_width, :waste_percent, :edge_allowance_percent,
                           keyword_init: true)

      class << self
        def cut_list_csv(rows)
          lines = [header(%w[number material thickness length width quantity edge_l1 edge_l2 edge_w1
                             edge_w2 cut_length cut_width grain area parts])]
          rows.each_with_index do |r, i|
            lines << line([i + 1, r.material, num(r.thickness), num(r.length), num(r.width), r.quantity,
                           edge(r.edges[:l1]), edge(r.edges[:l2]), edge(r.edges[:w1]), edge(r.edges[:w2]),
                           num(r.cut_length), num(r.cut_width), grain(r.grain), num(r.area_m2, 3),
                           r.parts.join(', ')])
          end
          lines << ''
          lines << line([L10n.t('report.edge_note', min: num(CutList::EDGE_SUBTRACT_FROM))])
          BOM + lines.join("\r\n") + "\r\n"
        end

        # options: Options. hardware: CutList.hardware result.
        def estimate_csv(rows, hardware, options)
          lines = []
          totals = []
          row_no = 0
          # Appends a row; row_no is its 1-based spreadsheet row.
          add = lambda do |cells|
            lines << line(cells)
            row_no = lines.size
          end

          add.call([L10n.t('report.title_boards'), '', '', '', '', '', ''])
          add.call(header_cells(%w[material thickness area area_waste unit quantity price sum]))
          CutList.board_areas(rows).sort.each do |(material, thickness), area|
            sheets = CutList.sheets(area, options.sheet_length, options.sheet_width, options.waste_percent)
            with_waste = area * (1 + options.waste_percent / 100.0)
            unit = L10n.t('report.unit_sheet', size: "#{num(options.sheet_length)}x#{num(options.sheet_width)}")
            add.call([material, num(thickness), num(area, 2), num(with_waste, 2), unit, sheets, '',
                      formula(lines.size + 1)])
            totals << row_no
          end

          lines << ''
          add.call([L10n.t('report.title_edges'), '', '', '', '', '', ''])
          add.call(header_cells(%w[material edge_thickness length_m length_allowance unit quantity price sum]))
          CutList.edge_totals(rows).sort.each do |(material, thickness), metres|
            with_allowance = metres * (1 + options.edge_allowance_percent / 100.0)
            add.call([material, num(thickness), num(metres, 2), num(with_allowance, 2), L10n.t('report.unit_m'),
                      num(with_allowance.ceil, 0), '', formula(lines.size + 1)])
            totals << row_no
          end

          lines << ''
          add.call([L10n.t('report.title_hardware'), '', '', '', '', '', ''])
          add.call(header_cells(%w[item note blank blank unit quantity price sum]))
          hardware_lines(hardware).each do |name, note, unit, quantity|
            add.call([name, note, '', '', unit, quantity, '', formula(lines.size + 1)])
            totals << row_no
          end

          lines << ''
          total = totals.empty? ? '0' : "=#{totals.map { |r| "H#{r}" }.join('+')}"
          lines << line([L10n.t('report.total'), '', '', '', '', '', '', total])
          lines << ''
          lines << line([L10n.t('report.price_note')])
          BOM + lines.join("\r\n") + "\r\n"
        end

        def separator
          L10n.locale == 'ru' ? ';' : ','
        end

        private

        def hardware_lines(hardware)
          pcs = L10n.t('report.unit_pcs')
          c = hardware[:counts]
          out = []
          out << [L10n.t('report.hinges'), '', pcs, c[:hinges]] if c[:hinges].positive?
          hardware[:slides].sort.each do |length, pairs|
            out << [L10n.t('report.slides'), "#{length} #{L10n.t('unit.mm')}", L10n.t('report.unit_pairs'), pairs]
          end
          out << [L10n.t('report.handles'), '', pcs, c[:handles]] if c[:handles].positive?
          out << [L10n.t('report.legs'), '', pcs, c[:legs]] if c[:legs].positive?
          out << [L10n.t('report.shelf_supports'), '', pcs, c[:shelf_supports]] if c[:shelf_supports].positive?
          out << [L10n.t('report.wall_hangers'), '', pcs, c[:wall_hangers]] if c[:wall_hangers].positive?
          if hardware[:rail_m].positive?
            out << [L10n.t('report.rail'), '', L10n.t('report.unit_m'), num(hardware[:rail_m], 2)]
          end
          out
        end

        # Quantity (column F) x price (column G) of this row.
        def formula(row)
          "=F#{row}*G#{row}"
        end

        def header(keys)
          line(header_cells(keys))
        end

        def header_cells(keys)
          keys.map { |k| k == 'blank' ? '' : L10n.t("report.col.#{k}") }
        end

        def edge(value)
          value.positive? ? num(value) : ''
        end

        def grain(value)
          value ? L10n.t("report.grain.#{value}") : ''
        end

        def num(value, digits = 1)
          rounded = value.to_f.round(digits)
          text = rounded == rounded.round ? rounded.round.to_s : format("%.#{digits}f", rounded).sub(/0+\z/, '')
          L10n.locale == 'ru' ? text.tr('.', ',') : text
        end

        def line(cells)
          cells.map { |c| quote(c.to_s) }.join(separator)
        end

        # Quotes only what must be quoted, so "0,801" stays a number in a
        # ";"-separated file.
        def quote(text)
          return text unless (text.include?(separator) || text.match?(/["\r\n]/)) && !text.start_with?('=')

          "\"#{text.gsub('"', '""')}\""
        end
      end
    end
  end
end
