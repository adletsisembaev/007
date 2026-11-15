# frozen_string_literal: true

require_relative 'test_helper'

class TestMaterialsAndPreview < Minitest::Test
  include TestSupport

  LIB = KitchenCabinetDesigner::MaterialLibrary

  def check(category, overrides = {})
    KCD::Validation.check(KCD::Settings.defaults(category).merge(overrides))
  end

  def test_default_materials_are_presets
    params = check('base').params
    assert_equal 'preset:white', params['carcass_material']
    assert_equal 'preset:oak_sonoma', params['front_material']
    refute check('wall').params.key?('drawer_box_material')
  end

  def test_spec_parsing_and_normalization
    assert_equal({ kind: :preset, value: 'walnut' }, LIB.parse('preset:walnut'))
    assert_equal 'color:#aabbcc', LIB.normalize('color:#AABBCC')
    assert_equal 'model:Egger W1000', LIB.normalize('model:  Egger W1000 ')
    assert_equal 'model:KCD Front', LIB.normalize('KCD Front'), 'legacy bare names are model materials'
    assert_nil LIB.parse('preset:unknown')
    assert_nil LIB.parse('color:red')
    assert_nil LIB.parse('model:')
    assert_nil LIB.parse("model:bad\tname")
    assert_nil LIB.parse('model:' + ('x' * 101))
  end

  def test_material_validation
    assert_equal 'color:#123456', check('base', 'front_material' => 'color:#123456').params['front_material']
    assert_equal 'preset:white', check('base', 'carcass_material' => '  ').params['carcass_material']
    assert_equal ['front_material'], check('base', 'front_material' => 'color:#12345').errors.map(&:field)
    assert_equal ['front_material'], check('base', 'front_material' => 'preset:gold').errors.map(&:field)
  end

  def test_every_preset_is_labelled_and_textures_exist
    LIB::PRESETS.each do |preset|
      %w[en ru].each do |code|
        strings = JSON.parse(File.read(File.join(KCD::LOCALE_DIR, "#{code}.json"), encoding: 'UTF-8'))
        assert strings.key?("material.#{preset[:key]}"), "#{code}: no label for #{preset[:key]}"
      end
      assert_match(/\A#\h{6}\z/, preset[:color])
      next unless preset[:texture]

      assert File.exist?(LIB.texture_path(preset)), "missing texture #{preset[:texture]}"
      assert_operator preset[:size], :>, 0
    end
  end

  def test_preset_material_names
    assert_equal 'KCD Walnut', LIB.material_name(kind: :preset, value: 'walnut')
    assert_equal 'KCD #aabbcc', LIB.material_name(kind: :color, value: '#aabbcc')
  end

  def test_parse_color
    assert_equal [255, 0, 16], KCD::Validation.parse_color('#ff0010')
    assert_nil KCD::Validation.parse_color('ff0010')
  end

  def test_every_part_uses_a_known_material_slot
    slots = %i[carcass front back drawer_box hardware]
    [['base', { 'cabinet_type' => 'drawers' }], ['base', { 'cabinet_type' => 'corner' }],
     ['wall', { 'hanging_rail' => true, 'back_mode' => 'inset' }]].each do |cat, o|
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
    assert_equal %w[DOOR_LEFT DOOR_RIGHT], preview['rects'].last(2).map { |r| r['name'] }.sort
    assert(preview['rects'].all? { |r| r['x1'] > r['x0'] && r['z1'] > r['z0'] })
  end
end

class TestRussianLocale < Minitest::Test
  KCD = KitchenCabinetDesigner

  def load(code)
    JSON.parse(File.read(File.join(KCD::LOCALE_DIR, "#{code}.json"), encoding: 'UTF-8'))
  end

  def test_russian_has_every_key_with_the_same_placeholders
    en = load('en')
    ru = load('ru')
    assert_empty en.keys - ru.keys, 'keys missing in ru.json'
    assert_empty ru.keys - en.keys, 'keys only in ru.json'
    en.each do |key, text|
      assert_equal text.scan(/%\{\w+\}/).sort, ru[key].scan(/%\{\w+\}/).sort, "placeholders differ: #{key}"
    end
  end

  def test_russian_messages_end_to_end
    KCD::L10n.locale = 'ru'
    result = KCD::Validation.check(KCD::Settings.defaults('base').merge('width' => 0))
    assert_match(/Ширина: допустимо от 100 до 2400 мм/, result.errors.first.message)
    assert_equal 'KCD Орех', KCD::MaterialLibrary.material_name(kind: :preset, value: 'walnut')
  ensure
    KCD::L10n.locale = 'en'
  end
end
