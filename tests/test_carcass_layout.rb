# frozen_string_literal: true

require_relative 'test_helper'

class TestCarcassLayout < Minitest::Test
  include TestSupport

  def build(category, overrides = {})
    KCD::Geometry::Layout.build(valid_params(category, overrides))
  end

  def test_base_cabinet_parts_and_names
    parts = build('base')
    assert_equal %w[SIDE_LEFT SIDE_RIGHT BOTTOM TOP BACK].sort, parts.map(&:name).sort
    assert(parts.all? { |p| p.container == 'CARCASS' })
  end

  def test_base_cabinet_dimensions
    parts = build('base')
    left = part(parts, 'SIDE_LEFT').bounds
    assert_equal [0.0, 0.0, 100.0, 16.0, 556.0, 820.0], left.to_a
    bottom = part(parts, 'BOTTOM').bounds
    assert_equal [16.0, 0.0, 100.0, 584.0, 556.0, 116.0], bottom.to_a
    top = part(parts, 'TOP').bounds
    assert_equal [16.0, 0.0, 804.0, 584.0, 556.0, 820.0], top.to_a
    back = part(parts, 'BACK').bounds
    assert_equal [0.0, 556.0, 100.0, 600.0, 560.0, 820.0], back.to_a
  end

  def test_wall_cabinet_starts_at_zero
    parts = build('wall')
    overall = parts.map(&:bounds).reduce(:union)
    assert_equal [0.0, 0.0, 0.0, 600.0, 320.0, 720.0], overall.to_a
  end

  def test_overall_size_matches_parameters
    [
      ['base', { 'width' => 300, 'height' => 720, 'depth' => 560, 'thickness' => 16 }],
      ['base', { 'width' => 1200, 'height' => 900, 'depth' => 600, 'thickness' => 19, 'plinth_height' => 0 }],
      ['base', { 'width' => 450.5, 'thickness' => 18, 'back_thickness' => 8 }],
      ['wall', { 'width' => 400, 'height' => 360, 'depth' => 300, 'thickness' => 18 }],
      ['wall', { 'width' => 900, 'height' => 960, 'depth' => 350, 'thickness' => 22, 'back_thickness' => 3 }]
    ].each do |category, overrides|
      params = valid_params(category, overrides)
      parts = KCD::Geometry::Layout.build(params)
      zc = KCD::Geometry::Layout.carcass_bottom(params)
      overall = parts.map(&:bounds).reduce(:union)
      expected = [0.0, 0.0, zc, params['width'], params['depth'], zc + params['height']]
      expected.zip(overall.to_a).each do |e, a|
        assert_in_delta e, a, 1.0e-9, "#{category} #{overrides}: overall #{overall}"
      end
    end
  end

  def test_no_overlapping_parts_across_parameter_grid
    [16, 18, 19, 25].each do |t|
      [300, 600, 1000].each do |w|
        [3, 4, 8].each do |tb|
          %w[base wall].each do |category|
            assert_no_overlaps(build(category, 'width' => w, 'thickness' => t, 'back_thickness' => tb))
          end
        end
      end
    end
  end

  def test_volume_equals_sum_of_parts
    params = valid_params('base')
    parts = KCD::Geometry::Layout.build(params)
    w, h, d, t, tb = params.values_at('width', 'height', 'depth', 'thickness', 'back_thickness')
    expected = 2 * t * (d - tb) * h + 2 * (w - 2 * t) * (d - tb) * t + w * tb * h
    actual = parts.sum { |p| p.boxes.sum(&:volume) }
    assert_in_delta expected, actual, 1.0e-6
  end

  def test_cut_sizes
    parts = build('base')
    assert_equal [720.0, 556.0, 16.0], part(parts, 'SIDE_LEFT').cut_size
    assert_equal [568.0, 556.0, 16.0], part(parts, 'BOTTOM').cut_size
    assert_equal [720.0, 600.0, 4.0], part(parts, 'BACK').cut_size
  end
end
