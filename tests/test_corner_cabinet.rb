# frozen_string_literal: true

require_relative 'test_helper'

class TestCornerCabinet < Minitest::Test
  include TestSupport

  def build(category, overrides = {})
    KCD::Geometry::Layout.build(valid_params(category, { 'cabinet_type' => 'corner' }.merge(overrides)))
  end

  def errors_for(category, overrides)
    KCD::Validation.check(KCD::Settings.defaults(category).merge('cabinet_type' => 'corner')
                                                            .merge(overrides)).errors.map(&:field)
  end

  def test_left_blind_panel_and_door
    parts = build('base', 'width' => 1000, 'blind_width' => 600)
    panel = part(parts, 'BLIND_PANEL').bounds
    door = part(parts, 'DOOR').bounds
    assert_equal 'FRONTS', part(parts, 'BLIND_PANEL').container
    assert_equal [1.0, 599.0], [panel.x0, panel.x1]
    assert_equal [601.0, 999.0], [door.x0, door.x1]
    assert_equal panel.to_a.values_at(1, 2, 4, 5), door.to_a.values_at(1, 2, 4, 5)
    assert_no_overlaps(parts)
  end

  def test_right_blind_side_mirrors
    parts = build('wall', 'width' => 900, 'blind_width' => 350, 'corner_side' => 'right')
    assert_equal [1.0, 549.0], part(parts, 'DOOR').bounds.to_a.values_at(0, 3)
    assert_equal [551.0, 899.0], part(parts, 'BLIND_PANEL').bounds.to_a.values_at(0, 3)
  end

  def test_inset_corner_fronts
    parts = build('base', 'width' => 1000, 'blind_width' => 500, 'front_mount' => 'inset')
    panel = part(parts, 'BLIND_PANEL').bounds
    assert_equal [18.0, 499.0], [panel.x0, panel.x1]
    assert_no_overlaps(parts)
  end

  def test_corner_has_shelves_and_validation
    assert(build('base', 'width' => 1000, 'blind_width' => 500).any? { |p| p.name == 'SHELF_1' })
    assert_equal ['blind_width'], errors_for('base', 'width' => 600, 'blind_width' => 550)
    assert_equal ['blind_width'], errors_for('base', 'width' => 600, 'blind_width' => 90)
    assert_equal ['blind_width'], errors_for('base', 'width' => 600, 'blind_width' => 700)
    assert_empty errors_for('base', 'width' => 600, 'blind_width' => 300)
  end
end
