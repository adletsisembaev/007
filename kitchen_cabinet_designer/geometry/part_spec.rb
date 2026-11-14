# frozen_string_literal: true

module KitchenCabinetDesigner
  # Pure-Ruby geometry layer. Nothing in this namespace calls the SketchUp
  # API: layouts compute PartSpec objects in millimetres in the cabinet's local
  # coordinate system (origin = front-left-bottom, X = width, Y = depth
  # towards the wall, Z = up). PanelBuilder turns them into SketchUp geometry.
  module Geometry
    EPSILON = 1.0e-6

    # Raised when parameters pass field validation but still cannot produce
    # consistent geometry.
    class LayoutError < StandardError; end

    # Axis-aligned box in millimetres.
    class Box
      attr_reader :x0, :y0, :z0, :x1, :y1, :z1

      def initialize(x0, y0, z0, x1, y1, z1)
        @x0, @x1 = [x0.to_f, x1.to_f].minmax
        @y0, @y1 = [y0.to_f, y1.to_f].minmax
        @z0, @z1 = [z0.to_f, z1.to_f].minmax
      end

      def size
        [x1 - x0, y1 - y0, z1 - z0]
      end

      def volume
        size.inject(:*)
      end

      def min_size
        size.min
      end

      # Volume shared with another box (0.0 when they only touch).
      def intersection_volume(other)
        dx = [x1, other.x1].min - [x0, other.x0].max
        dy = [y1, other.y1].min - [y0, other.y0].max
        dz = [z1, other.z1].min - [z0, other.z0].max
        return 0.0 if dx <= EPSILON || dy <= EPSILON || dz <= EPSILON

        dx * dy * dz
      end

      def union(other)
        Box.new([x0, other.x0].min, [y0, other.y0].min, [z0, other.z0].min,
                [x1, other.x1].max, [y1, other.y1].max, [z1, other.z1].max)
      end

      def contains?(other, tolerance = EPSILON)
        other.x0 >= x0 - tolerance && other.x1 <= x1 + tolerance &&
          other.y0 >= y0 - tolerance && other.y1 <= y1 + tolerance &&
          other.z0 >= z0 - tolerance && other.z1 <= z1 + tolerance
      end

      def to_a
        [x0, y0, z0, x1, y1, z1]
      end

      def to_s
        format('Box(x %.2f..%.2f, y %.2f..%.2f, z %.2f..%.2f)', x0, x1, y0, y1, z0, z1)
      end
    end

    # Description of one cabinet part.
    #
    # shape is one of:
    #   { type: :box, box: Box }
    #   { type: :profile, plane: :xy | :yz | :xz, points: [[u, v], ...],
    #     from: Float, to: Float }
    #       A closed 2D outline extruded perpendicular to its plane:
    #         :xy -> points are (x, y), extruded along Z from..to
    #         :yz -> points are (y, z), extruded along X from..to
    #         :xz -> points are (x, z), extruded along Y from..to
    #   { type: :cylinder, center: [x, y], radius: Float, z0:, z1:, segments: }
    #
    # boxes is an exact decomposition of the solid into axis-aligned boxes
    # (bounding box for cylinders). It is used for bounds, cut sizes and the
    # overlap tests.
    class PartSpec
      PLANES = %i[xy yz xz].freeze

      attr_reader :name, :role, :container, :material, :shape, :boxes

      def self.box(name:, box:, material:, container: nil, role: nil)
        new(name: name, role: role, container: container, material: material,
            shape: { type: :box, box: box }, boxes: [box])
      end

      def self.profile(name:, plane:, points:, from:, to:, boxes:, material:,
                       container: nil, role: nil)
        raise ArgumentError, "unknown plane #{plane.inspect}" unless PLANES.include?(plane)

        clean = clean_outline(points)
        raise LayoutError, "#{name}: outline needs at least 3 distinct points" if clean.size < 3

        from, to = [from.to_f, to.to_f].minmax
        new(name: name, role: role, container: container, material: material,
            shape: { type: :profile, plane: plane, points: clean, from: from, to: to },
            boxes: boxes)
      end

      def self.cylinder(name:, center:, radius:, z0:, z1:, material:, container: nil,
                        role: nil, segments: 24)
        cx, cy = center.map(&:to_f)
        r = radius.to_f
        z0, z1 = [z0.to_f, z1.to_f].minmax
        bounds = Box.new(cx - r, cy - r, z0, cx + r, cy + r, z1)
        new(name: name, role: role, container: container, material: material,
            shape: { type: :cylinder, center: [cx, cy], radius: r, z0: z0, z1: z1,
                     segments: segments },
            boxes: [bounds])
      end

      # Removes consecutive duplicate points and a closing point equal to the
      # first one. SketchUp's add_face fails on duplicate vertices.
      def self.clean_outline(points)
        out = []
        points.each do |u, v|
          pt = [u.to_f, v.to_f]
          out << pt if out.empty? || !same_point?(out.last, pt)
        end
        out.pop if out.size > 1 && same_point?(out.first, out.last)
        out
      end

      def self.same_point?(a, b)
        (a[0] - b[0]).abs < EPSILON && (a[1] - b[1]).abs < EPSILON
      end

      def initialize(name:, role:, container:, material:, shape:, boxes:)
        @name = name.to_s
        @role = (role || name).to_s
        @container = container.to_s
        @material = material
        @shape = shape
        @boxes = boxes
        raise LayoutError, "#{@name}: part has no volume" if boxes.empty?
      end

      def shape_type
        shape[:type]
      end

      def bounds
        boxes.reduce { |acc, box| acc.union(box) }
      end

      # Blank size (largest dimension first), rounded to 0.1 mm.
      def cut_size
        bounds.size.map { |v| v.round(1) }.sort.reverse
      end

      def min_size
        boxes.map(&:min_size).min
      end
    end
  end
end
