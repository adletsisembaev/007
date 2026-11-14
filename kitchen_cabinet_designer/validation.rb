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

      def check_construction(params, errors, _warnings)
        t = params['thickness']

        min_width = 2 * t + MIN_INTERIOR
        if params['width'] < min_width
          errors << Issue.new('width', L10n.t('error.width_thickness', min: fmt(min_width)))
        end

        min_height = 2 * t + MIN_INTERIOR
        if params['height'] < min_height
          errors << Issue.new('height', L10n.t('error.height_thickness', min: fmt(min_height)))
        end

        panel_depth = params['depth'] - params['back_thickness']
        return unless panel_depth < MIN_PANEL_DEPTH

        errors << Issue.new('back_thickness',
                            L10n.t('error.back_depth', min: fmt(MIN_PANEL_DEPTH)))
      end
    end
  end
end
