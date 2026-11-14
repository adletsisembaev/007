# frozen_string_literal: true

require_relative 'test_helper'

class TestMaterialsAndPreview < Minitest::Test
  include TestSupport

  def check(category, overrides = {})
    KCD::Validation.check(KCD::Settings.defaults(category).merge(overrides))
  end

  def test_material_defaults_and_empty_name_fallback
    params = check('base', 'front_material' => '   ').params
    assert_equal 'KCD Front', params['front_material']
    assert_equal '#c9a46b', params['front_color']
    refute check('wall').params.key?('drawer_box_material')
  end

  def test_custom_material_names_are_kept
    params = check('base', 'carcass_material' => '  Egger W1000 ST9  ').params
    assert_equal 'Egger W1000 ST9', params['carcass_material']
  end

  def test_invalid_material_and_colour
    assert_equal ['carcass_material'], check('base', 'carcass_material' => "bad\tname").errors.map(&:field)
    assert_equal ['carcass_material'], check('base', 'carcass_material' => 'x' * 101).errors.map(&:field)
    assert_equal ['front_color'], check('base', 'front_color' => 'red').errors.map(&:field)
    assert_equal ['front_color'], check('base', 'front_color' => '#12345').errors.map(&:field)
    assert_equal '#aabbcc', check('base', 'front_color' => '#AABBCC').params['front_color']
  end

  def test_parse_color
    assert_equal [255, 0, 16], KCD::Validation.parse_color('#ff0010')
    assert_nil KCD::Validation.parse_color('ff0010')
  end

  def test_every_part_uses_a_known_material_slot
    slots = %i[carcass front back drawer_box hardware]
    [['base', { 'cabinet_type' => 'drawers' }], ['base', {}], ['wall', { 'hanging_rail' => true,
                                                                          'back_mode' => 'inset' }]].each do |cat, o|
      KCD::Geometry::Layout.build(valid_params(cat, o)).each do |p|
        assert_includes slots, p.material, p.name
      end
    end
  end

  def test_preview_projects_all_parts_far_to_near
    params = valid_params('base', 'cabinet_type' => 'two_doors')
    preview = KCD::Geometry::Layout.preview(params)
    parts = KCD::Geometry::Layout.build(params)
    assert_equal parts.size, preview['rects'].size
    assert_equal [0.0, 0.0, 600.0, 820.0], preview['bounds']
    # fronts are nearest to the viewer and must be drawn last
    assert_equal %w[DOOR_LEFT DOOR_RIGHT], preview['rects'].last(2).map { |r| r['name'] }.sort
    assert(preview['rects'].all? { |r| r['x1'] > r['x0'] && r['z1'] > r['z0'] })
  end
end
