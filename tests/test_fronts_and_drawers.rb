# frozen_string_literal: true

require_relative 'test_helper'

class TestFrontsAndDrawers < Minitest::Test
  include TestSupport

  def build(category, overrides = {})
    KCD::Geometry::Layout.build(valid_params(category, overrides))
  end

  def errors_for(category, overrides)
    KCD::Validation.check(KCD::Settings.defaults(category).merge(overrides)).errors
  end

  # ----------------------------------------------------------------- doors

  def test_single_overlay_door_on_base_cabinet
    door = part(build('base'), 'DOOR')
    assert_equal 'FRONTS', door.container
    assert_equal :front, door.material
    # 1 mm edge gaps, 18 mm thick, carcass 100..820
    assert_equal [1.0, -18.0, 101.0, 599.0, 0.0, 819.0], door.bounds.to_a
  end

  def test_two_overlay_doors_with_gap
    parts = build('wall', 'cabinet_type' => 'two_doors')
    left = part(parts, 'DOOR_LEFT').bounds
    right = part(parts, 'DOOR_RIGHT').bounds
    assert_in_delta 2.0, right.x0 - left.x1, 1e-9
    assert_in_delta left.size[0], right.size[0], 1e-9
    assert_equal [1.0, 1.0, 599.0, 719.0], [left.x0, left.z0, right.x1, right.z1]
  end

  def test_inset_door
    door = part(build('wall', 'front_mount' => 'inset', 'inset_gap' => 2, 'shelf_count' => 0),
                'DOOR').bounds
    assert_equal [18.0, 0.0, 18.0, 582.0, 18.0, 702.0], door.to_a
  end

  def test_inset_door_with_rails_and_setback
    parts = build('base', 'front_mount' => 'inset', 'inset_setback' => 5, 'shelf_front_setback' => 25)
    door = part(parts, 'DOOR').bounds
    assert_equal [18.0, 5.0, 118.0, 582.0, 23.0, 802.0], door.to_a
    assert_no_overlaps(parts)
  end

  def test_shelves_start_behind_inset_doors
    parts = build('base', 'front_mount' => 'inset', 'inset_setback' => 3, 'shelf_front_setback' => 2)
    assert_in_delta 3.0 + 18.0 + 2.0, part(parts, 'SHELF_1').bounds.y0, 1e-9
    assert_no_overlaps(parts)
  end

  def test_front_extension
    door = part(build('wall', 'front_extend_bottom' => 20, 'front_extend_top' => 5), 'DOOR').bounds
    assert_equal [-19.0, 724.0], [door.z0, door.z1]
  end

  def test_open_cabinet_has_no_fronts
    parts = build('base', 'cabinet_type' => 'open')
    refute(parts.any? { |p| p.container == 'FRONTS' || p.container.start_with?('DRAWER') })
  end

  def test_fronts_validation
    assert_equal ['front_extend_bottom'],
                 errors_for('base', 'front_extend_bottom' => 150).map(&:field)
    assert_empty errors_for('base', 'front_mount' => 'inset')
    assert_empty errors_for('wall', 'front_extend_bottom' => 150)
    result = KCD::Validation.check(KCD::Settings.defaults('base').merge('width' => 900))
    assert result.ok?
    assert_equal ['cabinet_type'], result.warnings.map(&:field)
  end

  # ---------------------------------------------------------------- drawers

  def drawer_params(overrides = {})
    { 'cabinet_type' => 'drawers' }.merge(overrides)
  end

  def test_three_equal_drawers
    parts = build('base', drawer_params)
    fronts = (1..3).map { |n| part(parts, "DRAWER_FRONT_#{n}").bounds }
    # zone 101..819 = 718, minus 2 gaps of 2 mm = 714 / 3 = 238
    fronts.each { |f| assert_in_delta 238.0, f.size[2], 1e-9 }
    assert_in_delta 819.0, fronts[0].z1, 1e-9
    assert_in_delta 2.0, fronts[0].z0 - fronts[1].z1, 1e-9
    assert_in_delta 101.0, fronts[2].z0, 1e-9
    assert_equal 'DRAWER_1', parts.find { |p| p.name == 'DRAWER_FRONT_1' }.container
    refute(parts.any? { |p| p.name.start_with?('SHELF') }, 'drawer cabinets have no shelves')
  end

  def test_drawer_box_geometry
    parts = build('base', drawer_params)
    box_parts = parts.select { |p| p.container == 'DRAWER_3/DRAWER_BOX_3' }
    assert_equal %w[BOX_BACK BOX_BOTTOM BOX_FRONT BOX_SIDE_LEFT BOX_SIDE_RIGHT], box_parts.map(&:name).sort
    bottom = part(box_parts, 'BOX_BOTTOM').bounds
    # x: 16 + 13 .. 584 - 13; y: 2 .. 2 + 500; z: max(101, 116) + 15 = 131
    assert_equal [29.0, 2.0, 131.0, 571.0, 502.0, 135.0], bottom.to_a
    side = part(box_parts, 'BOX_SIDE_LEFT').bounds
    # front 3 top = 101 + 238 = 339; box top = 339 - 30 = 309
    assert_equal [29.0, 2.0, 135.0, 45.0, 502.0, 309.0], side.to_a
    assert_no_overlaps(parts)
  end

  def test_auto_depth_respects_slide_clearance
    params = valid_params('base', drawer_params('depth' => 560))
    m = KCD::Geometry::Layout.metrics(params)
    plan = KCD::Geometry::DrawerLayout.plan(params, m)
    depth = plan.drawers.first.box_depth
    assert_equal 500.0, depth
    assert_operator plan.drawers.first.box_y0 + depth, :<=, 560 - 30
  end

  def test_custom_heights_with_auto
    parts = build('base', drawer_params('drawer_heights' => '140; 0; 0'))
    heights = (1..3).map { |n| part(parts, "DRAWER_FRONT_#{n}").bounds.size[2] }
    assert_in_delta 140.0, heights[0], 1e-9
    assert_in_delta 287.0, heights[1], 1e-9 # (714 - 140) / 2
    assert_in_delta heights[1], heights[2], 1e-9
  end

  def test_custom_heights_exact_sum
    parts = build('base', drawer_params('drawer_count' => 2, 'drawer_heights' => '300;416'))
    assert_in_delta 416.0, part(parts, 'DRAWER_FRONT_2').bounds.size[2], 1e-9
  end

  def test_drawer_validation_messages
    sum = errors_for('base', drawer_params('drawer_count' => 2, 'drawer_heights' => '300;300'))
    assert_equal ['drawer_heights'], sum.map(&:field)
    assert_match(/600 mm but must add up to 716 mm/, sum.first.message)
    assert_equal ['drawer_heights'],
                 errors_for('base', drawer_params('drawer_heights' => '140;0')).map(&:field)
    assert_equal ['drawer_heights'],
                 errors_for('base', drawer_params('drawer_heights' => 'abc')).map(&:field)
    assert_equal ['drawer_box_depth'],
                 errors_for('base', drawer_params('drawer_box_depth' => 540)).map(&:field)
    assert_equal ['drawer_box_height'],
                 errors_for('base', drawer_params('drawer_box_height' => 300)).map(&:field)
    assert_equal ['drawer_heights'],
                 errors_for('base', drawer_params('drawer_count' => 8)).map(&:field)
    assert_equal ['slide_clearance'],
                 errors_for('base', drawer_params('width' => 130, 'support_type' => 'none')).map(&:field)
  end

  def test_drawer_boxes_never_overlap
    [1, 2, 3, 4, 5].each do |count|
      %w[overlay inset].each do |mount|
        %w[top_panel rails none].each do |top|
          params = drawer_params('drawer_count' => count, 'front_mount' => mount,
                                 'top_construction' => top)
          result = KCD::Validation.check(KCD::Settings.defaults('base').merge(params))
          next unless result.ok?

          assert_no_overlaps(KCD::Geometry::Layout.build(result.params))
        end
      end
    end
  end

  def test_inset_drawer_boxes_start_behind_front
    parts = build('base', drawer_params('front_mount' => 'inset'))
    front = part(parts, 'DRAWER_FRONT_1').bounds
    box = part(parts, 'BOX_FRONT').bounds
    assert_in_delta front.y1 + 2.0, box.y0, 1e-9
  end

  def test_drawers_rejected_for_wall
    refute KCD::Validation.check(KCD::Settings.defaults('wall').merge(drawer_params)).ok?
  end
end
