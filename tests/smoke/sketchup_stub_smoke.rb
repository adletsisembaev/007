# frozen_string_literal: false
#
# Smoke test of the SketchUp-dependent modules against a minimal stub of the
# SketchUp API (only the calls this extension makes). It catches wrong
# method names, broken call chains and operation handling (commit/abort).
# It does NOT prove that SketchUp itself produces correct geometry.
#
# Run: ruby tests/smoke/sketchup_stub_smoke.rb
class Numeric; def mm; self / 25.4; end; end
module Geom
  class Point3d; attr_reader :x,:y,:z; def initialize(x,y,z); @x,@y,@z=x,y,z; end; end
  class Vector3d; attr_reader :x,:y,:z; def initialize(x,y,z); @x,@y,@z=x,y,z; end
    def dot(o); x*o.x+y*o.y+z*o.z; end; def reverse; Vector3d.new(-x,-y,-z); end; end
  class Transformation; attr_reader :t
    def initialize(t=[0,0,0]); @t=t; end
    def self.translation(v); new([v.x,v.y,v.z]); end
    def *(o); Transformation.new(@t.zip(o.t).map(&:sum)); end; end
end
module Attr; def set_attribute(d,k,v); (@attrs||={})[[d,k]]=v; end; def get_attribute(d,k,dflt=nil); (@attrs||={}).fetch([d,k],dflt); end; end
module Sketchup
  class Vertex; attr_reader :position; def initialize(p); @position=p; end; end
  class Face; attr_reader :normal; def initialize(n); @normal=n; end
    def vertices; [Vertex.new(Geom::Point3d.new(0,0,0))]; end
    def position_material(m, pts, front); raise 'bad pts' unless pts.size == 4; $positioned += 1; end
    def reverse!; @normal=@normal.reverse; end
    def pushpull(d); raise "neg" unless d>0; $pushes << [@normal, d]; end; end
  class Entities < Array
    attr_accessor :parent
    def add_group; g=Group.new; g.parent=self; push(g); g; end
    def add_face(pts); f=Face.new(Geom::Vector3d.new(0,0,-1)); push f; f; end
    def add_circle(*a); [:edges]; end
    def add_instance(defn, tr); i=ComponentInstance.new(defn, tr); defn.instances<<i; push i; i; end
    def clear!; clear; end
  end
  class Group; include Attr; attr_accessor :name, :material, :parent; def entities; @e||=Entities.new; end; end
  class ComponentDefinition; include Attr; attr_accessor :name, :description
    def group?; false; end; def image?; false; end
    def initialize(n); @name=n; end; def entities; @e||=Entities.new; end; def instances; @i||=[]; end; end
  class ComponentInstance; include Attr; attr_accessor :transformation, :definition, :parent
    def initialize(d,t); @definition=d; @transformation=t; end; def valid?; true; end
    def make_unique; self; end; def model; $model; end; end
  class Definitions < Array; def add(n); d=ComponentDefinition.new(n); push d; d; end; def [](n); n.is_a?(String) ? find{|d| d.name==n} : super; end; end
  class Color; attr_reader :red,:green,:blue; def initialize(r,g,b); @red,@green,@blue=r,g,b; end; end
  class Texture; attr_accessor :size, :path; def initialize(p); @path=p; end; def width; 800.0 / 25.4; end; end
  class Material; include Attr; attr_accessor :name, :color; attr_reader :texture
    def initialize(n); @name=n; @color=Color.new(255,255,255); @texture=nil; end
    def texture=(p); raise "no file #{p}" unless File.exist?(p); @texture=Texture.new(p); end; end
  class Materials < Array; def [](n); n.is_a?(String) ? find{|m| m.name==n} : super; end; def add(n); m=Material.new(n); push m; m; end; end
  class Selection < Array; def add(e); push e; end; end
  class Model; attr_reader :definitions, :entities, :selection, :ops
    def initialize; @definitions=Definitions.new; @entities=Entities.new; @selection=Selection.new; @ops=[]; @materials=Materials.new; end
    attr_reader :materials
    def start_operation(n, ui); @ops << [:start, n]; end
    def commit_operation; @ops << :commit; end
    def active_path; nil; end
    def abort_operation; @ops << :abort; end
  end
end
$pushes=[]
$positioned=0
module UI; def self.savepanel(*a); $save_path; end; end
class Geom::Point3d; def offset(v, d); Geom::Point3d.new(x+v.x*d, y+v.y*d, z+v.z*d); end; end
module KitchenCabinetDesigner; PLUGIN_ID='kitchen_cabinet_designer'; PLUGIN_NAME='KCD'; VERSION='t'; PLUGIN_ROOT=File.expand_path('../../kitchen_cabinet_designer', __dir__); end
%w[constants l10n settings validation geometry/part_spec geometry/carcass_layout geometry/base_cabinet geometry/wall_cabinet geometry/door_layout geometry/drawer_layout geometry/cut_list geometry/report ral_colors user_library material_library geometry/layout sketchup/materials sketchup/panel_builder sketchup/placement sketchup/cabinet_builder sketchup/exporter].each{|f| require File.join(KitchenCabinetDesigner::PLUGIN_ROOT,f)}
K=KitchenCabinetDesigner
$model=m=Sketchup::Model.new
def m.entities; super.tap{|e| e.parent=self}; end
o=K::CabinetBuilder.create(m, K::Settings.defaults('base'))
p o.to_h, m.ops, m.definitions.map(&:name)
inst=o.instance; inst.parent=m
p inst.transformation.t.map{|v| (v*25.4).round(3)}
o2=K::CabinetBuilder.create(m, K::Settings.defaults('base').merge('width'=>450))
p o2.message, o2.instance.transformation.t.map{|v| (v*25.4).round(3)}
o3=K::CabinetBuilder.update(m, inst, K::Settings.defaults('base').merge('depth'=>600, 'width'=>800))
p o3.message, inst.transformation.t.map{|v| (v*25.4).round(3)}, m.definitions.map(&:name)
p K::CabinetBuilder.create(m, {'category'=>'base','width'=>'x'}).to_h
p $pushes.size, $pushes.all?{|n,_| n.z>0}
p inst.definition.entities.map(&:name), inst.definition.entities.first.entities.map(&:name)
m3=Sketchup::Model.new; $model=m3
o=K::CabinetBuilder.create(m3, K::Settings.defaults('wall').merge('back_mode'=>'inset','back_groove'=>true,'back_inset'=>16,'hanging_rail'=>true))
p o.message, o.instance.transformation.t.map{|v| (v*25.4).round(3)}
o=K::CabinetBuilder.create(m3, K::Settings.defaults('base').merge('width'=>900))
ents=o.instance.definition.entities
p ents.map(&:name), ents.find{|g| g.name=='SUPPORTS'}.entities.map(&:name)
p m3.ops
p m3.materials.map{|x| [x.name, x.color.red, x.texture && File.basename(x.texture.path), x.texture && (x.texture.size[0]*25.4).round]}
p K::Materials.list(m3).first
o=K::CabinetBuilder.create(m3, K::Settings.defaults('base').merge('front_material'=>'color:#2a6f97','carcass_material'=>'preset:white'))
o=K::CabinetBuilder.create(m3, K::Settings.defaults('base').merge('front_material'=>'color:#2a6f97','carcass_material'=>'model:Missing One'))
p m3.materials.map(&:name)
g=o.instance.definition.entities.find{|e| e.name=='CARCASS'}.entities.first; p g.material&.name
o=K::CabinetBuilder.create(m3, K::Settings.defaults('base').merge('cabinet_type'=>'drawers'))
e=o.instance.definition.entities
p e.map(&:name)
d1=e.find{|g| g.name=='DRAWER_1'}.entities
p d1.map(&:name), d1.find{|g| g.name=='DRAWER_BOX_1'}.entities.map(&:name)
# --- v1.2: RAL, plinth, grain alignment, export
m4=Sketchup::Model.new; $model=m4
def m4.title; 'Кухня'; end
def m4.path; ''; end
o=K::CabinetBuilder.create(m4, K::Settings.defaults('base').merge('cabinet_type'=>'two_doors','carcass_material'=>'ral:9010'))
p o.message, m4.materials.map(&:name), $positioned
K::CabinetBuilder.create(m4, K::Settings.defaults('wall').merge('front_material'=>'preset:walnut'))
require 'tmpdir'
dir = Dir.mktmpdir
$save_path = File.join(dir, 'Кухня_раскрой')
p K::Exporter.run(m4, {'scope'=>'model','sheet_length'=>'2800','sheet_width'=>'2070','waste_percent'=>'15','edge_allowance_percent'=>'10'})
p Dir.children(dir).sort
File.write(ENV['KCD_EXPORT_COPY'] + '/cut.csv', File.read(File.join(dir, 'Кухня_раскрой.csv'))) if ENV['KCD_EXPORT_COPY']
File.write(ENV['KCD_EXPORT_COPY'] + '/estimate.csv', File.read(File.join(dir, 'Кухня_раскрой_смета.csv'))) if ENV['KCD_EXPORT_COPY']
p K::Exporter.run(m4, {'scope'=>'selection'})
p K::Exporter.run(m4, {'sheet_length'=>'0'})
class Sketchup::Entities; def add_face(p); nil; end; end
m2=Sketchup::Model.new; $model=m2
begin; K::CabinetBuilder.create(m2, K::Settings.defaults('wall')); rescue => e; p e.class, e.message; end
p m2.ops
