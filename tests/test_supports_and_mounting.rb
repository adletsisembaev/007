# frozen_string_literal: true

require_relative 'test_helper'

class TestSupportsAndMounting < Minitest::Test
  include TestSupport

  def build(category, overrides = {})
    KCD::Geometry::Layout.build(valid_params(category, overrides))
  end

  def supports(parts)
    parts.select { |p| p.container == 'SUPPORTS' }
  end

  def test_legs_with_plinth_default
    parts = build('base')
    names = supports(parts).map(&:name)
    assert_equal %w[LEG_1 LEG_2 LEG_3 LEG_4 PLINTH_FRONT], names
    plinth = part(parts, 'PLINTH_FRONT').bounds
    assert_equal [0.0, 50.0, 0.0, 600.0, 66.0, 100.0], plinth.to_a
    leg = part(parts, 'LEG_1')
    assert_equal :cylinder, leg.shape_type
    assert_equal [50.0, 100.0], leg.shape[:center]
    assert_equal 20.0, leg.shape[:radius]
    assert_equal [0.0, 100.0], [leg.shape[:z0], leg.shape[:z1]]
    rear = part(parts, 'LEG_3')
    assert_equal [50.0, 496.0], rear.shape[:center] # 556 - 60
  end

  def test_middle_legs_for_wide_cabinets
    assert_equal 4, supports(build('base', 'width' => 790, 'support_type' => 'legs')).size
    wide = supports(build('base', 'width' => 800, 'support_type' => 'legs'))
    assert_equal 6, wide.size
    assert_equal [400.0, 100.0], wide.find { |p| p.name == 'LEG_5' }.shape[:center]
    assert_equal 4, supports(build('base', 'width' => 1200, 'support_type' => 'legs',
                                           'middle_legs_from' => 0)).size
  end

  def test_plinth_box
    parts = build('base', 'support_type' => 'plinth_box')
    assert_equal %w[PLINTH_FRONT PLINTH_REAR], supports(parts).map(&:name)
    assert_equal [0.0, 540.0, 0.0, 600.0, 556.0, 100.0], part(parts, 'PLINTH_REAR').bounds.to_a
  end

  def test_no_supports
    params = valid_params('base', 'support_type' => 'none')
    parts = KCD::Geometry::Layout.build(params)
    assert_empty supports(parts)
    assert_equal 0.0, part(parts, 'BOTTOM').bounds.z0
  end

  def test_hanging_rail_behind_inset_back
    parts = build('wall', 'back_mode' => 'inset', 'back_inset' => 16, 'hanging_rail' => true)
    rail = part(parts, 'HANGING_RAIL')
    assert_equal 'MOUNTING', rail.container
    # back rear face at 320 - 16 = 304; rail 10 thick under the 16 mm top
    assert_equal [16.0, 304.0, 654.0, 584.0, 314.0, 704.0], rail.bounds.to_a
    assert_no_overlaps(parts)
  end

  def test_hanging_rail_in_wall_gap_runs_full_width
    parts = build('wall', 'back_mode' => 'overlay', 'wall_gap' => 10, 'hanging_rail' => true)
    rail = part(parts, 'HANGING_RAIL').bounds
    assert_equal [0.0, 320.0, 654.0, 600.0, 330.0, 704.0], rail.to_a
    assert_no_overlaps(parts)
  end

  def test_hanging_rail_must_fit
    result = KCD::Validation.check(KCD::Settings.defaults('wall').merge(
                                     'back_mode' => 'overlay', 'wall_gap' => 0, 'hanging_rail' => true
                                   ))
    refute result.ok?
    assert_equal ['rail_thickness'], result.errors.map(&:field)
    assert_match(/available 0 mm/, result.errors.first.message)
  end
end
