# frozen_string_literal: true

# Writes the dialog's 'init' message and the 'locale' messages for both
# languages (as Ruby would send them) to the JSON file ARGV[0].
require_relative '../test_helper'
require 'json'

K = KitchenCabinetDesigner

def locale_payload(code)
  K::L10n.locale = code
  { 'locale' => code, 'locales' => K::L10n::AVAILABLE, 'strings' => K::L10n.strings,
    'presets' => K::MaterialLibrary.dialog_presets }
end

init = {
  'type' => 'init', 'version' => 'test',
  'categories' => K::Settings::CATEGORIES,
  'cabinetTypes' => K::Settings::CABINET_TYPES.map do |t|
    { 'id' => t[:id], 'categories' => t[:categories], 'implemented' => t[:implemented] }
  end,
  'defaults' => K::Settings::CATEGORIES.to_h { |c| [c, K::Settings.defaults(c)] },
  'lastUsed' => K::Settings::CATEGORIES.to_h { |c| [c, K::Settings.defaults(c)] },
  'materials' => [{ 'name' => 'Egger W1000', 'color' => '#f2f1ec', 'textured' => false },
                  { 'name' => 'KCD Дуб сонома', 'color' => '#d2b78e', 'textured' => true }]
}.merge(locale_payload('ru'))

locales = %w[ru en].to_h { |c| [c, locale_payload(c).merge('type' => 'locale')] }
File.write(ARGV[0], JSON.generate({ init: init, locales: locales }))
