# frozen_string_literal: true

module KitchenCabinetDesigner
  # Validates and normalizes cabinet parameters.
  #
  # Validation.check(raw) accepts a Hash coming from the dialog (String or
  # Symbol keys, values as numbers or strings, decimal comma allowed) and
  # returns a Result with normalized params (String keys, Float millimetres),
  # a list of errors and a list of warnings. Geometry is only generated when
  # the result has no errors.
  module Validation
    Issue = Struct.new(:field, :message) do
      def to_h
        { 'field' => field, 'message' => message }
      end
    end

    class Result
      attr_reader :params, :errors, :warnings

      def initialize(params, errors, warnings)
        @params = params
        @errors = errors
        @warnings = warnings
      end

      def ok?
        errors.empty?
      end

      def to_h
        {
          'ok' => ok?,
          'errors' => errors.map(&:to_h),
          'warnings' => warnings.map(&:to_h)
        }
      end
    end

    # Minimum clear interior size (between panels) in mm.
    MIN_INTERIOR = 20.0
    # Minimum depth of the side panels after subtracting the back panel.
    MIN_PANEL_DEPTH = 50.0
    # Material that must remain next to a groove.
    MIN_GROOVE_WALL = 3.0
    MIN_SHELF_SPACING = 30.0
    MIN_PLINTH_HEIGHT = 10.0
    EPSILON_MM = 1.0e-6
    MIN_DOOR_SIZE = 100.0
    # A single door wider than this gets a warning (hinges, sagging).
    WIDE_DOOR = 600.0

    class << self
      def check(raw)
        raw = stringify_keys(raw || {})
        errors = []
        warnings = []

        category = raw['category'].to_s
        unless Settings::CATEGORIES.include?(category)
          errors << Issue.new('category', L10n.t('error.category'))
          return Result.new({}, errors, warnings)
        end

        params = { 'category' => category }
        Settings::FIELDS.each do |key, spec|
          next unless Settings.applicable?(key, category)

          value = raw.key?(key) ? raw[key] : Settings.default_for(key, category)
          coerced = check_field(key, value, spec, errors)
          params[key] = coerced unless coerced.nil?
        end

        check_cabinet_type(params, errors) if params.key?('cabinet_type')
        check_construction(params, errors, warnings) if errors.empty?

        Result.new(params, errors, warnings)
      end

      # Formats a millimetre value for messages: 16.0 -> "16", 0.5 -> "0.5".
      def fmt(value)
        rounded = value.to_f.round(2)
        rounded == rounded.round ? rounded.round.to_s : rounded.to_s
      end

      # Parses a number from a Numeric or a String ("16", "16.5", "16,5").
      # Returns nil if the value is not a finite number.
      def parse_number(value)
        number =
          case value
          when Numeric then value.to_f
          when String
            text = value.strip.tr(',', '.')
            return nil if text.empty?

            Float(text)
          end
        number&.finite? ? number : nil
      rescue ArgumentError, TypeError
        nil
      end

      def field_label(key)
        L10n.t("field.#{key}")
      end

      private

      def stringify_keys(hash)
        hash.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end

      def check_field(key, value, spec, errors)
        case spec[:type]
        when :mm, :int then check_number(key, value, spec, errors)
        when :enum then check_enum(key, value, spec, errors)
        when :bool then parse_bool(value)
        when :text then check_text(key, value, spec, errors)
        when :material then check_material(key, value, spec, errors)
        when :color then check_color(key, value, errors)
        end
      end

      def check_number(key, value, spec, errors)
        number = parse_number(value)
        if number.nil?
          errors << Issue.new(key, L10n.t('error.not_number', field: field_label(key)))
          return nil
        end
        if spec[:type] == :int
          if number != number.round
            errors << Issue.new(key, L10n.t('error.not_integer', field: field_label(key)))
            return nil
          end
          number = number.round
        end
        if number < spec[:min] || number > spec[:max]
          key_name = spec[:type] == :int ? 'error.range_count' : 'error.range'
          errors << Issue.new(key, L10n.t(key_name, field: field_label(key),
                                                    min: fmt(spec[:min]), max: fmt(spec[:max])))
          return nil
        end
        number
      end

      def check_enum(key, value, spec, errors)
        text = value.to_s
        return text if spec[:values].include?(text)

        errors << Issue.new(key, L10n.t('error.enum', field: field_label(key), value: text))
        nil
      end

      def check_text(key, value, spec, errors)
        text = value.to_s.strip
        return text if text.length <= spec[:max_length]

        errors << Issue.new(key, L10n.t('error.text_length', field: field_label(key),
                                                              max: spec[:max_length]))
        nil
      end

      MATERIAL_NAME_MAX = 100

      # Empty names fall back to the default name; control characters are
      # rejected because they cannot be shown in SketchUp's material browser.
      def check_material(key, value, spec, errors)
        name = value.to_s.strip
        name = spec[:default] if name.empty?
        if name.length > MATERIAL_NAME_MAX || name.match?(/[[:cntrl:]]/)
          errors << Issue.new(key, L10n.t('error.material_name', max: MATERIAL_NAME_MAX))
          return nil
        end
        name
      end

      def check_color(key, value, errors)
        text = value.to_s.strip.downcase
        return text if parse_color(text)

        errors << Issue.new(key, L10n.t('error.color', field: field_label(key)))
        nil
      end

      public

      # "#rrggbb" -> [r, g, b] or nil.
      def parse_color(text)
        match = /\A#(\h{2})(\h{2})(\h{2})\z/.match(text.to_s.strip)
        match && match.captures.map { |c| c.to_i(16) }
      end

      private

      def parse_bool(value)
        case value
        when true, 'true', '1', 1, 'on', 'yes' then true
        else false
        end
      end

      def check_cabinet_type(params, errors)
        type = Settings.cabinet_type(params['cabinet_type'])
        type_name = L10n.t("type.#{type[:id]}")
        unless type[:categories].include?(params['category'])
          errors << Issue.new('cabinet_type',
                              L10n.t('error.type_category', type: type_name,
                                                            category: L10n.t("category.#{params['category']}")))
          return
        end
        return if type[:implemented]

        errors << Issue.new('cabinet_type', L10n.t('error.not_implemented', type: type_name))
      end

      def check_construction(params, errors, warnings)
        normalize_dependent(params)
        check_carcass(params, errors)
        return unless errors.empty?

        m = Geometry::Layout.metrics(params)
        check_back(params, m, errors, warnings)
        check_rails(params, m, errors) if params['category'] == 'base'
        check_shelves(params, m, errors)
        check_supports(params, m, errors) if params['category'] == 'base'
        check_hanging_rail(params, m, errors) if params['category'] == 'wall'
        check_fronts(params, m, errors, warnings) if errors.empty?
      end

      # Options that only make sense together with another option.
      def normalize_dependent(params)
        params['back_groove'] = false unless params['back_mode'] == 'inset'
      end

      def check_carcass(params, errors)
        t = params['thickness']
        min_width = 2 * t + MIN_INTERIOR
        if params['width'] < min_width
          errors << Issue.new('width', L10n.t('error.width_thickness', min: fmt(min_width)))
        end
        min_height = 2 * t + MIN_INTERIOR
        return unless params['height'] < min_height

        errors << Issue.new('height', L10n.t('error.height_thickness', min: fmt(min_height)))
      end

      def check_back(params, m, errors, warnings)
        if m.groove
          max_depth = params['thickness'] - MIN_GROOVE_WALL
          if params['groove_depth'] > max_depth
            errors << Issue.new('groove_depth', L10n.t('error.groove_depth', max: fmt(max_depth)))
          end
          if params['groove_play'] >= params['groove_depth']
            errors << Issue.new('groove_play', L10n.t('error.groove_play'))
          end
          inset = params['back_inset']
          if inset.positive? && inset < MIN_GROOVE_WALL
            warnings << Issue.new('back_inset', L10n.t('warn.groove_wall', value: fmt(inset)))
          end
        end
        return unless m.usable_depth < MIN_PANEL_DEPTH

        field = params['back_mode'] == 'inset' ? 'back_inset' : 'back_thickness'
        errors << Issue.new(field, L10n.t('error.back_depth', min: fmt(MIN_PANEL_DEPTH)))
      end

      def check_rails(params, m, errors)
        return unless params['top_construction'] == 'rails'

        max = m.back_y0 / 2.0
        return unless params['rail_width'] > max

        errors << Issue.new('rail_width', L10n.t('error.rails_overlap', max: fmt(max)))
      end

      def check_shelves(params, m, errors)
        count = Geometry::CarcassLayout.effective_shelf_count(params)
        return if count.zero?

        spacing = Geometry::CarcassLayout.shelf_spacing(m, count)
        if spacing < MIN_SHELF_SPACING
          errors << Issue.new('shelf_count', L10n.t('error.shelves', value: fmt(spacing),
                                                                    min: fmt(MIN_SHELF_SPACING)))
        end
        return unless m.back_y0 - Geometry::CarcassLayout.shelf_front(params) < MIN_PANEL_DEPTH

        errors << Issue.new('shelf_front_setback', L10n.t('error.shelf_depth', min: fmt(MIN_PANEL_DEPTH)))
      end

      def check_supports(params, m, errors)
        return if params['support_type'] == 'none'

        if params['plinth_height'] < MIN_PLINTH_HEIGHT
          errors << Issue.new('plinth_height', L10n.t('error.plinth_required', min: fmt(MIN_PLINTH_HEIGHT)))
          return
        end

        dp = m.panel_depth
        plinth_front_end = 0.0
        if Geometry::BaseCabinet.front_plinth?(params)
          plinth_front_end = params['plinth_setback'] + params['plinth_thickness']
          rear_limit = params['support_type'] == 'plinth_box' ? dp - params['plinth_thickness'] : dp
          if plinth_front_end > rear_limit
            errors << Issue.new('plinth_setback', L10n.t('error.plinth_depth'))
            return
          end
        end

        check_legs(params, dp, plinth_front_end, errors) if Geometry::BaseCabinet.legs?(params)
      end

      def check_legs(params, panel_depth, plinth_front_end, errors)
        r = params['leg_diameter'] / 2.0
        w = params['width']
        if params['leg_offset_side'] < r
          errors << Issue.new('leg_offset_side', L10n.t('error.legs_side', min: fmt(r)))
          return
        end
        gap_x = Geometry::BaseCabinet.middle_legs?(params) ? w / 2.0 - params['leg_offset_side'] : w - 2 * params['leg_offset_side']
        if gap_x < 2 * r
          errors << Issue.new('leg_offset_side', L10n.t('error.legs_width'))
          return
        end
        front_min = plinth_front_end + r
        if params['leg_offset_front'] < front_min
          errors << Issue.new('leg_offset_front', L10n.t('error.legs_front', min: fmt(front_min)))
          return
        end
        front_y = params['leg_offset_front']
        rear_y = panel_depth - params['leg_offset_rear']
        return unless params['leg_offset_rear'] < r || rear_y - front_y < 2 * r

        errors << Issue.new('leg_offset_rear', L10n.t('error.legs_depth'))
      end

      def check_fronts(params, m, errors, warnings)
        type = params['cabinet_type']
        doors = Geometry::DoorLayout.door_count(type)
        return unless doors || type == 'drawers'

        zone = Geometry::DoorLayout.zone(params, m)
        if params['front_mount'] == 'inset'
          check_inset_fronts(params, m, zone, errors)
        elsif params['category'] == 'base' && zone.z0 < -EPSILON_MM
          errors << Issue.new('front_extend_bottom', L10n.t('error.front_below_floor'))
        end
        return unless errors.empty?

        if doors
          check_doors(params, m, doors, errors, warnings)
        else
          check_drawers(params, m, errors)
        end
      end

      def check_inset_fronts(_params, m, zone, errors)
        return unless zone.y1 > m.usable_depth - MIN_PANEL_DEPTH

        errors << Issue.new('inset_setback', L10n.t('error.inset_depth'))
      end

      def check_doors(params, m, count, errors, warnings)
        Geometry::DoorLayout.doors(params, m, count).each do |_name, box|
          width, _depth, height = box.size
          if width < MIN_DOOR_SIZE || height < MIN_DOOR_SIZE
            errors << Issue.new('width', L10n.t('error.door_small', min: fmt(MIN_DOOR_SIZE)))
            return
          end
          if count == 1 && width > WIDE_DOOR
            warnings << Issue.new('cabinet_type', L10n.t('warn.wide_door', width: fmt(width)))
          end
        end
      end

      def check_drawers(params, m, errors)
        plan = Geometry::DrawerLayout.plan(params, m)
        # One message per field: the first drawer that fails is enough.
        plan.problems.uniq(&:first).each do |field, key, vars|
          formatted = vars.transform_values { |v| v.is_a?(Float) ? fmt(v) : v }
          errors << Issue.new(field, L10n.t(key, formatted))
        end
      end

      def check_hanging_rail(params, m, errors)
        return unless params['hanging_rail']

        max_height = params['height'] - 2 * params['thickness']
        if params['rail_height'] > max_height
          errors << Issue.new('rail_height', L10n.t('error.rail_height', max: fmt(max_height)))
        end
        available = Geometry::WallCabinet.rail_space(params, m)
        return unless params['rail_thickness'] > available + EPSILON_MM

        errors << Issue.new('rail_thickness',
                            L10n.t('error.rail_fit', need: fmt(params['rail_thickness']),
                                                     available: fmt(available)))
      end
    end
  end
end
