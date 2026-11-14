# frozen_string_literal: true

module KitchenCabinetDesigner
  module Geometry
    # Carcass layout: side panels, bottom, top and back panel.
    #
    # Stage 2 version: sides run the full height, bottom and top sit between
    # the sides, the back panel is applied to the rear of the carcass
    # (overlay). Grooved/inset backs, rails and shelves are added in Stage 3.
    module CarcassLayout
      CONTAINER = 'CARCASS'

      class << self
        # params: normalized parameters (see Validation.check)
        # z_bottom: Z of the carcass bottom in the local system (mm)
        def build(params, z_bottom)
          w  = params['width']
          h  = params['height']
          d  = params['depth']
          t  = params['thickness']
          tb = params['back_thickness']
          zc = z_bottom.to_f

          panel_depth = d - tb
          z_top = zc + h

          [
            panel('SIDE_LEFT',  Box.new(0, 0, zc, t, panel_depth, z_top)),
            panel('SIDE_RIGHT', Box.new(w - t, 0, zc, w, panel_depth, z_top)),
            panel('BOTTOM',     Box.new(t, 0, zc, w - t, panel_depth, zc + t)),
            panel('TOP',        Box.new(t, 0, z_top - t, w - t, panel_depth, z_top)),
            PartSpec.box(name: 'BACK', container: CONTAINER, material: :back,
                         box: Box.new(0, panel_depth, zc, w, d, z_top))
          ]
        end

        private

        def panel(name, box)
          PartSpec.box(name: name, container: CONTAINER, material: :carcass, box: box)
        end
      end
    end
  end
end
