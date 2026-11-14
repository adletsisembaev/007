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
  class Face; attr_reader :normal; def initialize(n); @normal=n; end
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
    def initialize(n); @name=n; end; def entities; @e||=Entities.new; end; def instances; @i||=[]; end; end
  class ComponentInstance; include Attr; attr_accessor :transformation, :definition, :parent
    def initialize(d,t); @definition=d; @transformation=t; end; def valid?; true; end
    def make_unique; self; end; def model; $model; end; end
  class Definitions < Array; def add(n); d=ComponentDefinition.new(n); push d; d; end; def [](n); n.is_a?(String) ? find{|d| d.name==n} : super; end; end
  class Color; attr_reader :red,:green,:blue; def initialize(r,g,b); @red,@green,@blue=r,g,b; end; end
  class Material; attr_accessor :name, :color; def initialize(n); @name=n; @color=Color.new(255,255,255); end; end
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
module KitchenCabinetDesigner; PLUGIN_ID='kitchen_cabinet_designer'; PLUGIN_NAME='KCD'; VERSION='t'; PLUGIN_ROOT=File.expand_path('../../kitchen_cabinet_designer', __dir__); end
%w[constants l10n settings validation geometry/part_spec geometry/carcass_layout geometry/base_cabinet geometry/wall_cabinet geometry/door_layout geometry/drawer_layout geometry/layout sketchup/materials sketchup/panel_builder sketchup/placement sketchup/cabinet_builder].each{|f| require File.join(KitchenCabinetDesigner::PLUGIN_ROOT,f)}
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
p m3.materials.map{|x| [x.name, x.color.red]}
p K::Materials.list(m3).first
g=o.instance.definition.entities.find{|e| e.name=='CARCASS'}.entities.first; p g.material&.name
o=K::CabinetBuilder.create(m3, K::Settings.defaults('base').merge('cabinet_type'=>'drawers'))
e=o.instance.definition.entities
p e.map(&:name)
d1=e.find{|g| g.name=='DRAWER_1'}.entities
p d1.map(&:name), d1.find{|g| g.name=='DRAWER_BOX_1'}.entities.map(&:name)
class Sketchup::Entities; def add_face(p); nil; end; end
m2=Sketchup::Model.new; $model=m2
begin; K::CabinetBuilder.create(m2, K::Settings.defaults('wall')); rescue => e; p e.class, e.message; end
p m2.ops
