# frozen_string_literal: true

require 'json'

module KitchenCabinetDesigner
  # Minimal localization layer.
  #
  # Strings live in locales/<code>.json as a flat "key" => "text" map. The same
  # map is sent to the HTML dialog, so Ruby and JavaScript share one source.
  # Missing keys in a translation fall back to English, then to the key itself.
  # Placeholders use the %{name} syntax.
  module L10n
    DEFAULT_LOCALE = 'en'

    class << self
      def locale
        @locale ||= detect_locale
      end

      # Allows forcing a locale (e.g. from tests or a future settings option).
      def locale=(code)
        @locale = code.to_s
        @strings = nil
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
        code = DEFAULT_LOCALE
        if defined?(Sketchup) && Sketchup.respond_to?(:get_locale)
          code = Sketchup.get_locale.to_s[0, 2].downcase
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
