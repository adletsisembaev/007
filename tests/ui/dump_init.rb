# frozen_string_literal: true

# Writes the dialog's 'init' message (as Ruby would send it) to ARGV[0].
require_relative '../test_helper'
require 'json'
K = KitchenCabinetDesigner
init = { 'type'=>'init','version'=>'test','strings'=>K::L10n.strings,
  'categories'=>K::Settings::CATEGORIES,
  'cabinetTypes'=>K::Settings::CABINET_TYPES.map{|t| {'id'=>t[:id],'categories'=>t[:categories],'implemented'=>t[:implemented]}},
  'defaults'=>K::Settings::CATEGORIES.to_h{|c|[c,K::Settings.defaults(c)]},
  'lastUsed'=>K::Settings::CATEGORIES.to_h{|c|[c,K::Settings.defaults(c)]},
  'materials'=>[{'name'=>'Oak Veneer','color'=>'#a0703c'},{'name'=>'White Gloss','color'=>'#fafafa'}] }
File.write(ARGV[0], JSON.generate({init: init}))
