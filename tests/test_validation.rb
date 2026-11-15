# frozen_string_literal: true

require_relative 'test_helper'

class TestValidation < Minitest::Test
  include TestSupport

  def check(category, overrides = {})
    KCD::Validation.check(KCD::Settings.defaults(category).merge(overrides))
  end

  def error_fields(result)
    result.errors.map(&:field)
  end

  def test_defaults_are_valid_for_both_categories
    %w[base wall].each do |category|
      assert check(category).ok?, "defaults for #{category} must be valid"
    end
  end

  def test_requested_default_dimensions
    base = KCD::Settings.defaults('base')
    wall = KCD::Settings.defaults('wall')
    assert_equal [600.0, 720.0, 560.0, 16.0, 100.0],
                 base.values_at('width', 'height', 'depth', 'thickness', 'plinth_height')
    assert_equal [600.0, 720.0, 320.0, 16.0],
                 wall.values_at('width', 'height', 'depth', 'thickness')
  end

  def test_strings_and_decimal_comma_are_parsed
    result = check('base', 'width' => '450', 'thickness' => '18,5')
    assert result.ok?
    assert_equal 450.0, result.params['width']
    assert_equal 18.5, result.params['thickness']
  end

  def test_zero_negative_and_non_numeric_are_rejected
    assert_includes error_fields(check('base', 'width' => 0)), 'width'
    assert_includes error_fields(check('base', 'height' => -720)), 'height'
    assert_includes error_fields(check('base', 'depth' => 'abc')), 'depth'
    assert_includes error_fields(check('base', 'depth' => '')), 'depth'
    assert_includes error_fields(check('base', 'thickness' => 'Infinity')), 'thickness'
  end

  def test_unknown_category_is_rejected
    result = KCD::Validation.check('category' => 'tall')
    refute result.ok?
    assert_equal ['category'], error_fields(result)
  end

  def test_planned_types_report_not_implemented
    %w[appliance custom].each do |type|
      result = check('wall', 'cabinet_type' => type)
      refute result.ok?
      assert_match(/Not implemented yet/, result.errors.first.message)
    end
    assert_match(/Not implemented yet/, check('base', 'cabinet_type' => 'sink').errors.first.message)
  end

  def test_drawers_not_available_for_wall_cabinets
    result = check('wall', 'cabinet_type' => 'drawers')
    refute result.ok?
    assert_includes error_fields(result), 'cabinet_type'
  end

  def test_width_must_exceed_two_panels
    result = check('base', 'width' => 100, 'thickness' => 45)
    assert_includes error_fields(result), 'width'
  end

  def test_thickest_back_on_shallowest_cabinet_is_still_valid
    # depth >= 100 and back <= 25 always leave >= 75 mm of side depth.
    assert check('wall', 'depth' => 100, 'back_thickness' => 25).ok?
  end

  def test_category_specific_fields
    base = check('base').params
    wall = check('wall').params
    assert base.key?('plinth_height')
    refute wall.key?('plinth_height')
    assert wall.key?('mount_height')
    refute base.key?('mount_height')
  end

  def test_missing_keys_fall_back_to_defaults
    result = KCD::Validation.check('category' => 'wall', 'width' => 800)
    assert result.ok?
    assert_equal 320.0, result.params['depth']
  end

  def test_all_messages_are_translated
    strings = KCD::L10n.strings
    results = [
      check('base', 'width' => 0), check('base', 'depth' => 'x'),
      check('wall', 'cabinet_type' => 'corner'), check('wall', 'cabinet_type' => 'drawers'),
      check('base', 'width' => 100, 'thickness' => 45)
    ]
    results.flat_map(&:errors).each do |issue|
      refute_match(/\A(error|field|type|category)\./, issue.message, "untranslated: #{issue.message}")
      refute_includes issue.message, '%{', "unfilled placeholder: #{issue.message}"
    end
    assert strings.key?('error.geometry')
  end
end

class TestConstructionValidation < Minitest::Test
  include TestSupport

  def fields_for(category, overrides)
    KCD::Validation.check(KCD::Settings.defaults(category).merge(overrides)).errors.map(&:field)
  end

  def test_groove_depth_limited_by_thickness
    assert_includes fields_for('base', 'back_mode' => 'inset', 'back_groove' => true,
                                       'groove_depth' => 14), 'groove_depth'
    assert_empty fields_for('base', 'back_mode' => 'inset', 'back_groove' => true, 'groove_depth' => 13)
  end

  def test_groove_play_smaller_than_depth
    assert_includes fields_for('wall', 'back_mode' => 'inset', 'back_groove' => true,
                                       'groove_depth' => 6, 'groove_play' => 6), 'groove_play'
  end

  def test_back_inset_too_deep
    assert_includes fields_for('wall', 'back_mode' => 'inset', 'back_inset' => 200, 'depth' => 250),
                    'back_inset'
  end

  def test_rails_must_not_overlap
    assert_includes fields_for('base', 'rail_width' => 300, 'depth' => 400), 'rail_width'
  end

  def test_too_many_shelves
    assert_includes fields_for('wall', 'height' => 200, 'shelf_count' => 5), 'shelf_count'
  end

  def test_shelf_setback_too_large
    assert_includes fields_for('wall', 'shelf_front_setback' => 280), 'shelf_front_setback'
  end

  def test_plinth_height_required_for_supports
    assert_includes fields_for('base', 'plinth_height' => 0), 'plinth_height'
    assert_empty fields_for('base', 'plinth_height' => 0, 'support_type' => 'none')
  end

  def test_leg_rules
    assert_includes fields_for('base', 'leg_offset_side' => 10), 'leg_offset_side'
    assert_includes fields_for('base', 'leg_offset_front' => 70), 'leg_offset_front'
    assert_empty fields_for('base', 'leg_offset_front' => 70, 'support_type' => 'legs')
    assert_includes fields_for('base', 'leg_offset_rear' => 5), 'leg_offset_rear'
    assert_includes fields_for('base', 'width' => 120, 'thickness' => 16, 'leg_diameter' => 60,
                                       'leg_offset_side' => 35), 'leg_offset_side'
  end

  def test_plinth_must_fit_depth
    assert_includes fields_for('base', 'support_type' => 'plinth_box', 'plinth_setback' => 210,
                                       'depth' => 240), 'plinth_setback'
  end

  def test_thin_material_behind_groove_is_a_warning
    result = KCD::Validation.check(KCD::Settings.defaults('wall').merge(
                                     'back_mode' => 'inset', 'back_groove' => true, 'back_inset' => 2
                                   ))
    assert result.ok?
    assert_equal ['back_inset'], result.warnings.map(&:field)
  end

  def test_every_dialog_i18n_key_exists
    html = File.read(File.join(KCD::PLUGIN_ROOT, 'dialogs', 'main.html')).gsub(/<!--.*?-->/m, '')
    keys = html.scan(/data-i18n="([^"]+)"/).flatten.uniq
    missing = keys - KCD::L10n.strings.keys
    assert_empty missing
  end

  def test_every_schema_field_has_a_dialog_input_and_label
    html = File.read(File.join(KCD::PLUGIN_ROOT, 'dialogs', 'main.html'))
    KCD::Settings::FIELDS.each_key do |key|
      assert_includes html, %(data-key="#{key}"), "no input for #{key}"
      assert KCD::L10n.strings.key?("field.#{key}"), "no label for #{key}"
    end
  end
end
