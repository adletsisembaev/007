# frozen_string_literal: true

require_relative 'test_helper'

class TestCarcassLayout < Minitest::Test
  include TestSupport

  def build(category, overrides = {})
    KCD::Geometry::Layout.build(valid_params(category, overrides))
  end

  def carcass(parts)
    parts.select { |p| p.container == 'CARCASS' }
  end

  # ------------------------------------------------------------ base, defaults

  def test_default_base_cabinet_parts
    parts = build('base')
    assert_equal %w[BACK BOTTOM RAIL_FRONT RAIL_REAR SHELF_1 SIDE_LEFT SIDE_RIGHT],
                 carcass(parts).map(&:name).sort
  end

  def test_default_base_cabinet_dimensions
    parts = build('base')
    # overlay back 4 mm, plinth 100 mm
    assert_equal [0.0, 0.0, 100.0, 16.0, 556.0, 820.0], part(parts, 'SIDE_LEFT').bounds.to_a
    assert_equal [584.0, 0.0, 100.0, 600.0, 556.0, 820.0], part(parts, 'SIDE_RIGHT').bounds.to_a
    assert_equal [16.0, 0.0, 100.0, 584.0, 556.0, 116.0], part(parts, 'BOTTOM').bounds.to_a
    assert_equal [16.0, 0.0, 804.0, 584.0, 100.0, 820.0], part(parts, 'RAIL_FRONT').bounds.to_a
    assert_equal [16.0, 456.0, 804.0, 584.0, 556.0, 820.0], part(parts, 'RAIL_REAR').bounds.to_a
    assert_equal [0.0, 556.0, 100.0, 600.0, 560.0, 820.0], part(parts, 'BACK').bounds.to_a
  end

  def test_single_shelf_is_centred_in_interior
    parts = build('base', 'shelf_count' => 1)
    shelf = part(parts, 'SHELF_1').bounds
    # interior 116..804 = 688; (688 - 16) / 2 = 336
    assert_in_delta 452.0, shelf.z0, 1e-9
    assert_in_delta 468.0, shelf.z1, 1e-9
    assert_in_delta 556.0, shelf.y1, 1e-9
  end

  def test_shelves_equally_spaced
    params = valid_params('wall', 'shelf_count' => 3)
    parts = KCD::Geometry::Layout.build(params)
    shelves = (1..3).map { |k| part(parts, "SHELF_#{k}").bounds }
    gaps = [shelves[0].z0 - 16.0, shelves[1].z0 - shelves[0].z1,
            shelves[2].z0 - shelves[1].z1, (720.0 - 16.0) - shelves[2].z1]
    gaps.each { |g| assert_in_delta gaps.first, g, 1e-9 }
  end

  def test_top_panel_and_open_top
    top = build('base', 'top_construction' => 'top_panel')
    assert_equal [16.0, 0.0, 804.0, 584.0, 556.0, 820.0], part(top, 'TOP').bounds.to_a
    open = build('base', 'top_construction' => 'none')
    refute(open.any? { |p| p.name.start_with?('TOP', 'RAIL') })
  end

  def test_no_back_panel
    parts = build('base', 'back_mode' => 'none')
    refute(parts.any? { |p| p.name == 'BACK' })
    assert_equal 560.0, part(parts, 'SIDE_LEFT').bounds.y1
    assert_equal 560.0, part(parts, 'RAIL_REAR').bounds.y1
  end

  # ------------------------------------------------------------ inset backs

  def test_inset_back_without_groove
    parts = build('wall', 'back_mode' => 'inset', 'back_inset' => 20, 'back_thickness' => 8)
    assert_equal [16.0, 292.0, 16.0, 584.0, 300.0, 704.0], part(parts, 'BACK').bounds.to_a
    assert_equal 320.0, part(parts, 'SIDE_LEFT').bounds.y1
    assert_equal :box, part(parts, 'SIDE_LEFT').shape_type
  end

  def test_grooved_back_geometry
    params = { 'back_mode' => 'inset', 'back_inset' => 16, 'back_thickness' => 4,
               'back_groove' => true, 'groove_depth' => 8, 'groove_play' => 1,
               'groove_extra_width' => 0.5 }
    parts = build('wall', params)
    back = part(parts, 'BACK').bounds
    # back enters each groove by 8 - 1 = 7 mm
    assert_equal [9.0, 300.0, 9.0, 591.0, 304.0, 711.0], back.to_a

    left = part(parts, 'SIDE_LEFT')
    assert_equal :profile, left.shape_type
    assert_equal 8, left.shape[:points].size
    assert_equal 3, left.boxes.size
    assert_equal [8.0, 299.5, 0.0, 16.0, 304.0, 720.0],
                 notch_of(left).to_a

    bottom = part(parts, 'BOTTOM')
    assert_equal :yz, bottom.shape[:plane]
    top = part(parts, 'TOP')
    assert_equal :yz, top.shape[:plane]
    assert_no_overlaps(parts)
  end

  def test_rebate_when_back_inset_is_zero
    parts = build('wall', 'back_mode' => 'inset', 'back_inset' => 0, 'back_groove' => true)
    left = part(parts, 'SIDE_LEFT')
    assert_equal 6, left.shape[:points].size, 'rebate outline is an L with 6 points'
    assert_equal 2, left.boxes.size
    assert_equal 320.0, part(parts, 'BACK').bounds.y1
    assert_no_overlaps(parts)
  end

  def test_groove_ignored_for_overlay_back
    parts = build('base', 'back_mode' => 'overlay', 'back_groove' => true)
    assert_equal :box, part(parts, 'SIDE_LEFT').shape_type
  end

  def test_grooved_back_with_rails_reaches_top_of_sides
    parts = build('base', 'back_mode' => 'inset', 'back_groove' => true, 'back_inset' => 16,
                          'top_construction' => 'rails')
    back = part(parts, 'BACK').bounds
    assert_equal 820.0, back.z1
    assert_equal part(parts, 'RAIL_REAR').bounds.y1, back.y0
    assert_no_overlaps(parts)
  end

  # ------------------------------------------------------------ global checks

  def test_overall_size_matches_parameters
    grid.each do |category, overrides|
      params = valid_params(category, overrides)
      parts = KCD::Geometry::Layout.build(params).select { |p| %w[CARCASS SUPPORTS].include?(p.container) }
      zc = KCD::Geometry::Layout.carcass_bottom(params)
      overall = parts.map(&:bounds).reduce(:union)
      expected = [0.0, 0.0, 0.0, params['width'], params['depth'], zc + params['height']]
      expected.zip(overall.to_a).each do |e, a|
        assert_in_delta e, a, 1e-9, "#{category} #{overrides}: overall #{overall}"
      end
    end
  end

  def test_no_overlapping_parts_across_parameter_grid
    grid.each do |category, overrides|
      assert_no_overlaps(build(category, overrides))
    end
  end

  def test_all_parts_have_real_thickness
    grid.each do |category, overrides|
      build(category, overrides).each do |p|
        assert_operator p.min_size, :>=, 0.5, "#{p.name} in #{category} #{overrides}"
      end
    end
  end

  # The outline actually drawn in SketchUp must describe the same solid as
  # the box decomposition used by the overlap tests.
  def test_profile_outlines_match_box_decomposition
    checked = 0
    grid.each do |category, overrides|
      build(category, overrides).select { |p| p.shape_type == :profile }.each do |p|
        shape = p.shape
        volume = polygon_area(shape[:points]).abs * (shape[:to] - shape[:from])
        assert_in_delta p.boxes.sum(&:volume), volume, 1e-6, "#{p.name} #{overrides}"
        refute self_intersecting?(shape[:points]), "#{p.name} outline crosses itself"
        checked += 1
      end
    end
    assert_operator checked, :>, 50
  end

  private

  def polygon_area(points)
    points.each_with_index.sum do |(x0, y0), i|
      x1, y1 = points[(i + 1) % points.size]
      x0 * y1 - x1 * y0
    end / 2.0
  end

  # True if two non-adjacent edges of the outline properly cross.
  def self_intersecting?(points)
    edges = points.each_index.map { |i| [points[i], points[(i + 1) % points.size]] }
    edges.each_with_index.any? do |(a, b), i|
      edges.each_with_index.any? do |(c, d), j|
        next false if (i - j).abs <= 1 || (i - j).abs == edges.size - 1

        o1 = orient(a, b, c)
        o2 = orient(a, b, d)
        o3 = orient(c, d, a)
        o4 = orient(c, d, b)
        o1 * o2 < 0 && o3 * o4 < 0
      end
    end
  end

  def orient(a, b, c)
    v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    v.abs < 1e-9 ? 0 : v <=> 0
  end

  # Box removed from a grooved left side (difference of bounds and boxes).
  def notch_of(side)
    middle = side.boxes[1]
    bounds = side.bounds
    KCD::Geometry::Box.new(middle.x1, middle.y0, bounds.z0, bounds.x1, middle.y1, bounds.z1)
  end

  def grid
    combos = []
    backs = [
      { 'back_mode' => 'overlay' },
      { 'back_mode' => 'none' },
      { 'back_mode' => 'inset', 'back_inset' => 20 },
      { 'back_mode' => 'inset', 'back_inset' => 16, 'back_groove' => true },
      { 'back_mode' => 'inset', 'back_inset' => 0, 'back_groove' => true }
    ]
    [[16, 300], [18, 600], [19, 1000]].each do |t, w|
      backs.each do |back|
        %w[top_panel rails none].each do |top|
          %w[legs legs_with_plinth plinth_box none].each do |support|
            type = %w[single_door two_doors drawers open][combos.size % 4]
            mount = combos.size.even? ? 'overlay' : 'inset'
            combos << ['base', { 'thickness' => t, 'width' => w, 'top_construction' => top,
                                 'support_type' => support, 'shelf_count' => 2,
                                 'cabinet_type' => type, 'front_mount' => mount,
                                 'shelf_front_setback' => 25 }.merge(back)]
          end
        end
        %w[single_door two_doors open].each do |type|
          combos << ['wall', { 'thickness' => t, 'width' => w, 'shelf_count' => 2,
                               'cabinet_type' => type, 'front_extend_bottom' => 20 }.merge(back)]
        end
        combos << ['wall', { 'thickness' => t, 'width' => w, 'cabinet_type' => 'single_door',
                             'front_mount' => 'inset', 'shelf_front_setback' => 25 }.merge(back)]
      end
    end
    combos
  end
end
