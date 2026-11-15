# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'

class TestCutList < Minitest::Test
  include TestSupport

  CL = KitchenCabinetDesigner::Geometry::CutList
  REPORT = KitchenCabinetDesigner::Geometry::Report

  def cabinets(*list)
    list.map { |name, category, overrides, count| { name: name, params: valid_params(category, overrides), count: count } }
  end

  def row_for(rows, part)
    rows.find { |r| r.parts.any? { |p| p.end_with?(": #{part}") } }
  end

  def test_side_panel_row_edges_and_cut_size
    rows = CL.rows(cabinets(['CABINET_600_BASE', 'base', {}, 2]))
    side = row_for(rows, 'SIDE_LEFT')
    assert_equal [16.0, 720.0, 556.0], [side.thickness, side.length, side.width]
    assert_equal 4, side.quantity, 'two sides x two cabinets'
    assert_equal({ l1: 1.0, l2: 0.0, w1: 0.0, w2: 0.0 }, side.edges, 'front edge is a long edge')
    assert_equal [720.0, 555.0], [side.cut_length, side.cut_width]
  end

  def test_doors_are_banded_all_around
    rows = CL.rows(cabinets(['C', 'base', { 'cabinet_type' => 'two_doors', 'edge_front' => 2 }, 1]))
    door = row_for(rows, 'DOOR_LEFT')
    assert_equal 2, door.quantity, 'left and right doors are identical and merged'
    assert_equal({ l1: 2.0, l2: 2.0, w1: 2.0, w2: 2.0 }, door.edges)
    assert_in_delta door.length - 4, door.cut_length, 1e-9
    assert_in_delta door.width - 4, door.cut_width, 1e-9
  end

  def test_thin_edges_are_not_subtracted
    rows = CL.rows(cabinets(['C', 'base', { 'cabinet_type' => 'drawers', 'edge_box' => 0.4 }, 1]))
    box_side = row_for(rows, 'BOX_SIDE_LEFT')
    assert_equal 0.4, box_side.edges[:l2], 'top edge of the box side'
    assert_equal box_side.width, box_side.cut_width
  end

  def test_hardware_is_excluded_and_plinth_follows_fronts
    rows = CL.rows(cabinets(['C', 'base', { 'front_material' => 'preset:walnut' }, 1]))
    refute(rows.any? { |r| r.parts.any? { |p| p.include?('LEG_') } })
    plinth = row_for(rows, 'PLINTH_FRONT')
    assert_equal 'Walnut', plinth.material
    assert_equal 'length', plinth.grain, 'textured walnut keeps the front grain setting'
    back = row_for(rows, 'BACK')
    assert_equal 4.0, back.thickness
    assert_nil back.grain, 'plain white back has no grain'
  end

  def test_board_areas_and_sheets
    rows = CL.rows(cabinets(['C', 'base', {}, 1]))
    areas = CL.board_areas(rows)
    assert(areas.keys.any? { |m, t| m == 'White' && t == 16.0 })
    assert_equal 1, CL.sheets(1.0, 2800, 2070, 15)
    assert_equal 2, CL.sheets(5.5, 2800, 2070, 15)
    assert_equal 0, CL.sheets(0, 2800, 2070, 15)
  end

  def test_hardware_counts
    hw = CL.hardware(cabinets(['A', 'base', { 'cabinet_type' => 'two_doors' }, 2],
                              ['B', 'base', { 'cabinet_type' => 'drawers' }, 1],
                              ['W', 'wall', { 'hanging_rail' => true, 'back_mode' => 'inset' }, 1]))
    assert_equal 10, hw[:counts][:hinges], '2 doors x 2 hinges x 2 cabinets + 2 for the wall door'
    assert_equal 4 + 3 + 1, hw[:counts][:handles]
    assert_equal({ 500 => 3 }, hw[:slides])
    assert_equal 4 * 3, hw[:counts][:legs]
    assert_equal 2, hw[:counts][:wall_hangers]
    assert_in_delta 0.568, hw[:rail_m], 1e-9
    assert_equal 3, CL.hinges_for(1200)
  end

  def test_csv_output_russian_and_english
    rows = CL.rows(cabinets(['C', 'base', { 'cabinet_type' => 'two_doors' }, 1]))
    hw = CL.hardware(cabinets(['C', 'base', { 'cabinet_type' => 'two_doors' }, 1]))
    options = REPORT::Options.new(sheet_length: 2800, sheet_width: 2070, waste_percent: 15,
                                  edge_allowance_percent: 10)
    KCD::L10n.locale = 'ru'
    cut = REPORT.cut_list_csv(rows)
    assert cut.start_with?("﻿")
    assert_includes cut, 'Кромка Д1'
    assert_includes cut.lines[1], ';'
    assert_match(/;555,0?;|;555;/, cut, 'decimal comma or integer in ru')
    estimate = REPORT.estimate_csv(rows, hw, options)
    assert_includes estimate, 'Петли'
    lines = estimate.delete_prefix("﻿").split("\r\n")
    total = lines.find { |l| l.start_with?('ИТОГО') }
    refute_nil total
    refs = total.scan(/H(\d+)/).flatten.map(&:to_i)
    refute_empty refs
    refs.each do |r|
      assert_match(/=F#{r}\*G#{r}\z/, lines[r - 1], "row #{r} must hold its own formula")
    end
  ensure
    KCD::L10n.locale = 'en'
  end

  def test_csv_english_uses_commas
    rows = CL.rows(cabinets(['C', 'wall', {}, 1]))
    cut = REPORT.cut_list_csv(rows)
    assert_includes cut, 'Edge L1'
    assert_includes cut.lines[1], ','
  end
end

class TestRalAndLibrary < Minitest::Test
  KCD = KitchenCabinetDesigner
  LIB = KCD::MaterialLibrary

  def test_ral_specs
    assert_equal({ kind: :ral, value: '9010' }, LIB.parse('ral:9010'))
    assert_equal 'ral:7016', LIB.normalize('ral:RAL 7016')
    assert_nil LIB.parse('ral:1234')
    assert_equal 'RAL 9010 Pure white', KCD::RalColors.label(KCD::RalColors.find('9010'), 'en')
    assert_equal 'RAL 9010 Чисто-белый', KCD::RalColors.label(KCD::RalColors.find('9010'), 'ru')
    assert(KCD::RalColors::TABLE.all? { |r| r[1].match?(/\A#\h{6}\z/) })
    assert_equal KCD::RalColors::TABLE.size, KCD::RalColors::BY_CODE.size, 'unique codes'
  end

  def test_same_front_and_user_specs
    assert_equal({ kind: :same, value: 'front' }, LIB.parse('same:front'))
    assert_nil LIB.parse('same:carcass')
    assert_equal :user, LIB.parse('user:a1b2c3d4e5f6')[:kind]
    assert_nil LIB.parse('user:../../etc')
  end

  def test_user_library_round_trip
    Dir.mktmpdir do |dir|
      KCD::UserLibrary.dir = File.join(dir, 'lib')
      color = KCD::UserLibrary.add_color('Sirca XX-123', '#AA3311')
      assert_equal '#aa3311', color['color']
      assert_raises(KCD::UserLibrary::Error) { KCD::UserLibrary.add_color('x', 'red') }

      image = File.join(dir, 'Egger H1145 ST10 Дуб.jpg')
      File.binwrite(image, 'fake-jpeg')
      texture = KCD::UserLibrary.add_texture(image)
      assert_equal 'Egger H1145 ST10 Дуб', texture['name']
      assert File.exist?(KCD::UserLibrary.texture_path(texture)), 'image copied into the library'
      assert_raises(KCD::UserLibrary::Error) { KCD::UserLibrary.add_texture(File.join(dir, 'none.jpg')) }

      folder = File.join(dir, 'decors')
      Dir.mkdir(folder)
      %w[a.png b.JPG notes.txt].each { |f| File.binwrite(File.join(folder, f), 'x') }
      assert_equal 2, KCD::UserLibrary.add_folder(folder).size

      assert_equal 4, KCD::UserLibrary.items.size
      url = KCD::UserLibrary.dialog_items.find { |i| i['id'] == texture['id'] }['texture']
      assert url.start_with?('file://')
      refute_includes url, ' '
      assert_equal 'KCD Sirca XX-123', LIB.material_name(kind: :user, value: color['id'])

      assert KCD::UserLibrary.remove(texture['id'])
      refute File.exist?(KCD::UserLibrary.texture_path(texture))
      assert_equal 3, KCD::UserLibrary.items.size
    ensure
      KCD::UserLibrary.dir = nil
    end
  end

  def test_hdf_back_offsets_and_validation
    params = KCD::Validation.check(KCD::Settings.defaults('wall').merge('back_offset_side' => 5,
                                                                         'back_offset_top' => 0)).params
    back = KCD::Geometry::Layout.build(params).find { |p| p.name == 'BACK' }.bounds
    assert_equal [5.0, 595.0, 2.0, 720.0], back.to_a.values_at(0, 3, 2, 5)
  end
end
