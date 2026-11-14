# frozen_string_literal: true

# Loads the pure-Ruby part of the extension (no SketchUp API) for unit tests.
# Run all tests with:  ruby tests/run_all.rb

require 'minitest/autorun'

module KitchenCabinetDesigner
  PLUGIN_ID   = 'kitchen_cabinet_designer'
  PLUGIN_NAME = 'Kitchen Cabinet Designer'
  VERSION     = 'test'
  PLUGIN_ROOT = File.expand_path('../kitchen_cabinet_designer', __dir__)
end

%w[
  constants
  l10n
  settings
  validation
  geometry/part_spec
  geometry/carcass_layout
  geometry/base_cabinet
  geometry/wall_cabinet
  geometry/layout
].each { |file| require File.join(KitchenCabinetDesigner::PLUGIN_ROOT, file) }

module TestSupport
  KCD = KitchenCabinetDesigner

  def valid_params(category, overrides = {})
    raw = KCD::Settings.defaults(category).merge(overrides)
    result = KCD::Validation.check(raw)
    assert result.ok?, "expected valid params, got: #{result.errors.map(&:message).join('; ')}"
    result.params
  end

  # Fails if any two parts share volume.
  def assert_no_overlaps(parts)
    parts.combination(2).each do |a, b|
      a.boxes.each do |box_a|
        b.boxes.each do |box_b|
          volume = box_a.intersection_volume(box_b)
          assert_in_delta 0.0, volume, 1.0e-6,
                          "#{a.container}/#{a.name} overlaps #{b.container}/#{b.name}: #{box_a} vs #{box_b}"
        end
      end
    end
  end

  def part(parts, name)
    found = parts.find { |p| p.name == name }
    refute_nil found, "part #{name} not found"
    found
  end
end
