# frozen_string_literal: true

module KitchenCabinetDesigner
  # Converts Geometry::PartSpec objects into SketchUp groups.
  #
  # Every part becomes its own group, so touching faces of neighbouring parts
  # never merge. Geometry is created directly in the group's local space with
  # an identity transformation, i.e. group coordinates equal the cabinet's
  # local coordinates. All millimetre values are converted with Numeric#mm
  # right before Geom::Point3d objects are created.
  module PanelBuilder
    class BuildError < StandardError; end

    Z_AXIS_VECTOR = Geom::Vector3d.new(0, 0, 1)
    PLANE_NORMALS = {
      xy: Geom::Vector3d.new(0, 0, 1),
      yz: Geom::Vector3d.new(1, 0, 0),
      xz: Geom::Vector3d.new(0, 1, 0)
    }.freeze

    class << self
      # entities:  Sketchup::Entities to build into (a definition's entities)
      # specs:     Array<Geometry::PartSpec>
      # materials: Hash slot (Symbol) => Sketchup::Material or nil
      # Returns a Hash part-name => Sketchup::Group.
      def render(entities, specs, materials = {})
        containers = {}
        groups = {}
        specs.each do |spec|
          target = container_entities(entities, spec.container, containers)
          groups[spec.name] = build_part(target, spec, materials)
        end
        groups
      end

      private

      # Returns the Entities collection for a container path such as
      # "CARCASS" or "DRAWER_1/DRAWER_BOX_1", creating nested groups once.
      def container_entities(root, path, cache)
        return root if path.nil? || path.empty?
        return cache[path].entities if cache.key?(path)

        segments = path.split('/')
        parent = container_entities(root, segments[0..-2].join('/'), cache)
        group = parent.add_group
        group.name = segments.last
        group.set_attribute(DICT, 'part_role', segments.last)
        cache[path] = group
        group.entities
      end

      def build_part(entities, spec, materials)
        group = entities.add_group
        group.name = spec.name
        case spec.shape_type
        when :box      then build_box(group.entities, spec.shape[:box], spec)
        when :profile  then build_profile(group.entities, spec.shape, spec)
        when :cylinder then build_cylinder(group.entities, spec.shape, spec)
        else raise BuildError, "#{spec.name}: unknown shape #{spec.shape_type.inspect}"
        end

        material = materials[spec.material]
        group.material = material if material
        group.set_attribute(DICT, 'part_role', spec.role)
        group.set_attribute(DICT, 'cut_size_mm', spec.cut_size.join(' x '))
        group
      end

      def build_box(entities, box, spec)
        points = [
          point(box.x0, box.y0, box.z0),
          point(box.x1, box.y0, box.z0),
          point(box.x1, box.y1, box.z0),
          point(box.x0, box.y1, box.z0)
        ]
        extrude(entities, points, Z_AXIS_VECTOR, box.z1 - box.z0, spec)
      end

      def build_profile(entities, shape, spec)
        plane = shape[:plane]
        base = shape[:from]
        points = shape[:points].map { |u, v| profile_point(plane, u, v, base) }
        extrude(entities, points, PLANE_NORMALS.fetch(plane), shape[:to] - shape[:from], spec)
      end

      def build_cylinder(entities, shape, spec)
        cx, cy = shape[:center]
        center = point(cx, cy, shape[:z0])
        edges = entities.add_circle(center, Z_AXIS_VECTOR, shape[:radius].mm, shape[:segments])
        face = entities.add_face(edges)
        raise BuildError, "#{spec.name}: could not create the base face" unless face

        push(face, Z_AXIS_VECTOR, shape[:z1] - shape[:z0], spec)
      end

      # Creates a planar face and extrudes it along `direction` by
      # `distance_mm`. The face normal is aligned with the direction first so
      # that the resulting solid has outward-facing faces.
      def extrude(entities, points, direction, distance_mm, spec)
        face = entities.add_face(points)
        raise BuildError, "#{spec.name}: could not create the base face" unless face

        push(face, direction, distance_mm, spec)
      end

      def push(face, direction, distance_mm, spec)
        raise BuildError, "#{spec.name}: extrusion length must be positive" unless distance_mm > 0

        face.reverse! if face.normal.dot(direction) < 0
        face.pushpull(distance_mm.mm)
      end

      def profile_point(plane, u, v, w)
        case plane
        when :xy then point(u, v, w)
        when :yz then point(w, u, v)
        when :xz then point(u, w, v)
        end
      end

      def point(x, y, z)
        Geom::Point3d.new(x.to_f.mm, y.to_f.mm, z.to_f.mm)
      end
    end
  end
end
