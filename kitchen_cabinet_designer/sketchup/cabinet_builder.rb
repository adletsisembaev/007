# frozen_string_literal: true

require 'json'

module KitchenCabinetDesigner
  # Creates and regenerates cabinet components inside undoable operations.
  #
  # Flow: validate -> compute layout (pure Ruby) -> start_operation ->
  # build -> commit. Validation and layout run before the operation starts,
  # so invalid input never touches the model. Any exception raised while the
  # operation is open aborts it, leaving no partial geometry behind.
  module CabinetBuilder
    # Result returned to the dialog controller.
    class Outcome
      attr_reader :ok, :message, :errors, :warnings, :instance

      def initialize(ok:, message:, errors: [], warnings: [], instance: nil)
        @ok = ok
        @message = message
        @errors = errors
        @warnings = warnings
        @instance = instance
      end

      def to_h
        {
          'ok' => ok,
          'message' => message,
          'errors' => errors.map(&:to_h),
          'warnings' => warnings.map(&:to_h)
        }
      end
    end

    class << self
      # Creates a new cabinet. Returns an Outcome.
      def create(model, raw_params)
        validation = Validation.check(raw_params)
        return invalid(validation) unless validation.ok?

        params = validation.params
        specs = Geometry::Layout.build(params)
        reference = reference_instance(model)

        instance = run_operation(model, L10n.t('op.create')) do
          definition = model.definitions.add(unique_definition_name(model, params))
          populate(model, definition, params, specs)
          inst = model.entities.add_instance(definition, Placement.for_new(params, reference))
          write_params(inst, params)
          inst
        end

        Settings.save_last_used(params)
        model.selection.clear
        model.selection.add(instance)
        Outcome.new(ok: true, message: L10n.t('msg.created', name: instance.definition.name),
                    warnings: validation.warnings, instance: instance)
      end

      # Regenerates an existing cabinet with new parameters.
      # scope: :all (every instance of the definition) or :single
      # (the instance is made unique first).
      def update(model, instance, raw_params, scope: :all)
        validation = Validation.check(raw_params)
        return invalid(validation) unless validation.ok?

        params = validation.params
        specs = Geometry::Layout.build(params)

        run_operation(model, L10n.t('op.update')) do
          instance.make_unique if scope == :single && instance.definition.instances.size > 1
          definition = instance.definition
          # Capture the old parameters before the definition is rewritten.
          targets = definition.instances.map { |inst| [inst, read_params(inst) || params] }

          definition.entities.clear!
          populate(model, definition, params, specs)
          rename_definition(model, definition, params)

          targets.each do |inst, old_params|
            inst.transformation = Placement.for_update(inst.transformation, old_params, params)
            write_params(inst, params)
          end
        end

        Settings.save_last_used(params)
        Outcome.new(ok: true, message: L10n.t('msg.updated', name: instance.definition.name),
                    warnings: validation.warnings, instance: instance)
      end

      # True if the entity is a cabinet created by this extension.
      def cabinet?(entity)
        entity.is_a?(Sketchup::ComponentInstance) && entity.valid? && !read_params(entity).nil?
      end

      # Stored parameters of a cabinet instance, or nil.
      def read_params(instance)
        return nil unless instance.respond_to?(:get_attribute)

        raw = instance.get_attribute(DICT, 'params')
        if raw.nil? && instance.respond_to?(:definition)
          raw = instance.definition.get_attribute(DICT, 'params')
        end
        return nil unless raw.is_a?(String)

        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      # The single selected cabinet at model level, or nil.
      def selected_cabinet(model)
        cabinets = model.selection.select { |e| cabinet?(e) }
        cabinets.size == 1 ? cabinets.first : nil
      end

      private

      def invalid(validation)
        Outcome.new(ok: false, message: L10n.t('msg.fix_errors'),
                    errors: validation.errors, warnings: validation.warnings)
      end

      # Runs the block inside one undoable operation. On any exception the
      # operation is aborted and the exception re-raised.
      def run_operation(model, name)
        model.start_operation(name, true)
        result = yield
        model.commit_operation
        result
      rescue StandardError
        model.abort_operation
        raise
      end

      def populate(model, definition, params, specs)
        materials = Materials.resolve(model, params, specs.map(&:material).uniq)
        PanelBuilder.render(definition.entities, specs, materials)
        definition.description = description_for(params)
        write_params(definition, params)
      end

      def write_params(entity, params)
        entity.set_attribute(DICT, 'schema_version', SCHEMA_VERSION)
        entity.set_attribute(DICT, 'plugin_version', VERSION)
        entity.set_attribute(DICT, 'params', JSON.generate(params))
      end

      # Cabinet next to which a new cabinet is placed: the single selected
      # cabinet, if it is at model level (not inside another group).
      def reference_instance(model)
        cabinet = selected_cabinet(model)
        cabinet && cabinet.parent == model ? cabinet : nil
      end

      def base_name(params)
        "CABINET_#{Validation.fmt(params['width'])}_#{params['category'].upcase}"
      end

      # CABINET_600_BASE, CABINET_600_BASE_2, CABINET_600_BASE_3, ...
      def unique_definition_name(model, params, except: nil)
        base = base_name(params)
        candidate = base
        index = 1
        loop do
          existing = model.definitions[candidate]
          return candidate if existing.nil? || existing == except

          index += 1
          candidate = "#{base}_#{index}"
        end
      end

      def rename_definition(model, definition, params)
        base = base_name(params)
        return if definition.name == base || definition.name.match?(/\A#{Regexp.escape(base)}_\d+\z/)

        definition.name = unique_definition_name(model, params, except: definition)
      end

      def description_for(params)
        dims = %w[width height depth].map { |k| Validation.fmt(params[k]) }.join(' x ')
        [
          L10n.t("category.#{params['category']}"),
          L10n.t("type.#{params['cabinet_type']}"),
          "#{dims} mm"
        ].join(' | ')
      end
    end
  end
end
