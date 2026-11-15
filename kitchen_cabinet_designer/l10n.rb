# frozen_string_literal: true

require 'json'

module KitchenCabinetDesigner
  # Minimal localization layer.
  #
  # Strings live in locales/<code>.json as a flat "key" => "text" map. The same
  # map is sent to the HTML dialog, so Ruby and JavaScript share one source.
  # Missing keys in a translation fall back to English, then to the key itself.
  # Placeholders use the %{name} syntax.
  #
  # Language: the user's choice saved in SketchUp preferences, otherwise
  # Russian (PREFERRED_LOCALE). English is the fallback for missing keys.
  module L10n
    DEFAULT_LOCALE = 'en'
    PREFERRED_LOCALE = 'ru'
    AVAILABLE = %w[ru en].freeze
    PREFERENCE_KEY = 'locale'

    class << self
      def locale
        @locale ||= detect_locale
      end

      # Forces a locale for this session (tests, or after the user's choice).
      def locale=(code)
        @locale = code.to_s
        @strings = nil
      end

      # Switches the language and remembers it for the next SketchUp start.
      def save_locale(code)
        code = code.to_s
        return false unless AVAILABLE.include?(code)

        self.locale = code
        if defined?(Sketchup) && Sketchup.respond_to?(:write_default)
          Sketchup.write_default(PLUGIN_ID, PREFERENCE_KEY, code)
        end
        true
      end

      def strings
        @strings ||= begin
          base = read_locale(DEFAULT_LOCALE)
          locale == DEFAULT_LOCALE ? base : base.merge(read_locale(locale))
        end
      end

      def t(key, vars = {})
        text = strings.fetch(key.to_s, key.to_s)
        return text if vars.empty?

        text.gsub(/%\{(\w+)\}/) do
          name = Regexp.last_match(1)
          value = vars.fetch(name.to_sym) { vars.fetch(name, "%{#{name}}") }
          value.to_s
        end
      end

      private

      def detect_locale
        code = PREFERRED_LOCALE
        if defined?(Sketchup) && Sketchup.respond_to?(:read_default)
          saved = Sketchup.read_default(PLUGIN_ID, PREFERENCE_KEY, nil).to_s
          code = saved if AVAILABLE.include?(saved)
        end
        File.exist?(locale_path(code)) ? code : DEFAULT_LOCALE
      rescue StandardError
        DEFAULT_LOCALE
      end

      def locale_path(code)
        File.join(LOCALE_DIR, "#{code}.json")
      end

      def read_locale(code)
        path = locale_path(code)
        return {} unless File.exist?(path)

        JSON.parse(File.read(path, encoding: 'UTF-8'))
      rescue JSON::ParserError => e
        warn "#{PLUGIN_NAME}: invalid locale file #{path}: #{e.message}"
        {}
      end
    end
  end
end
