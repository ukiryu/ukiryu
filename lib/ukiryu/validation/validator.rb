# frozen_string_literal: true

require_relative 'constraints'

module Ukiryu
  module Validation
    # Validates option objects using constraint-based validation
    #
    # The Validator class applies a collection of constraints to an options
    # object, ensuring all validation rules are satisfied before execution.
    #
    # This is a proper OOP validator that:
    # - Uses constraint objects (not procedural code)
    # - Returns validation result objects (not string arrays)
    # - Provides clear separation of concerns
    class Validator
      # The options object being validated
      attr_reader :options

      # The command definition containing validation rules
      attr_reader :command_def

      # Collection of constraints to apply
      attr_reader :constraints

      # @param options [Object] the options object to validate
      # @param command_def [Hash] the command definition
      def initialize(options, command_def)
        @options = options
        @command_def = command_def
        @constraints = []
        build_constraints
      end

      # Perform validation
      #
      # @return [Boolean] true if validation passes
      # @raise [ValidationError] if validation fails
      def validate!
        @constraints.each do |constraint|
          constraint.validate(get_constraint_value(constraint), constraint_context)
        end
        true
      rescue Validation::ValidationIssue => e
        raise Ukiryu::ValidationError, e.message
      end

      # Check if validation would pass without raising errors
      #
      # @return [Boolean] true if valid, false otherwise
      def valid?
        validate!
        true
      rescue Ukiryu::ValidationError
        false
      end

      # Get all validation errors
      #
      # @return [Array<String>] list of error messages
      def errors
        errors_list = []
        @constraints.each do |constraint|
          constraint.validate(get_constraint_value(constraint), constraint_context)
        rescue Validation::ValidationIssue => e
          errors_list << e.message
        end
        errors_list
      end

      private

      # Build constraint objects from command definition
      def build_constraints
        build_argument_constraints
        build_option_constraints(@command_def[:options])
        build_option_constraints(@command_def[:post_options])
        build_flag_constraints(@command_def[:flags])
        build_dependency_constraints
      end

      # Build constraints for arguments
      def build_argument_constraints
        return unless @command_def[:arguments]

        @command_def[:arguments].each do |arg_def|
          attr_name = arg_def[:name]
          min = arg_def[:min] || (arg_def[:variadic] ? 1 : 1)

          # Required constraint
          @constraints << RequiredConstraint.new(attr_name, min: min)

          # Type constraint
          @constraints << build_type_constraint(attr_name, arg_def) if arg_def[:type]

          # Cardinality constraint for variadic arguments
          next unless arg_def[:variadic] && arg_def[:max]

          @constraints << CardinalityConstraint.new(attr_name,
                                                    min: min,
                                                    max: arg_def[:max])
        end
      end

      # Build constraints for options
      def build_option_constraints(options)
        return unless options

        options.each do |opt_def|
          attr_name = opt_def[:name]

          # Type constraint
          @constraints << build_type_constraint(attr_name, opt_def) if opt_def[:type]

          # Range constraint
          if opt_def[:range]
            min, max = opt_def[:range]
            @constraints << RangeConstraint.new(attr_name, min: min, max: max)
          end

          # Enum constraint
          @constraints << EnumConstraint.new(attr_name, allowed_values: opt_def[:values]) if opt_def[:values]
        end
      end

      # Build constraints for flags
      def build_flag_constraints(flags)
        return unless flags

        flags.each do |flag_def|
          @constraints << BooleanFlagConstraint.new(flag_def[:name])
        end
      end

      # Build dependency constraints
      def build_dependency_constraints
        dependencies = @command_def[:dependencies] || []
        dependencies.each do |dep|
          @constraints << DependencyConstraint.new(
            dep[:option],
            requires: dep[:requires],
            conflicts: dep[:conflicts],
            implies: dep[:implies]
          )
        end
      end

      # Build a type constraint from a definition
      def build_type_constraint(attr_name, defn)
        validation_opts = {}
        validation_opts[:require_existing] = defn[:must_exist] if defn.key?(:must_exist)
        validation_opts[:allow_empty] = defn[:allow_empty] if defn.key?(:allow_empty)
        validation_opts[:pattern] = defn[:pattern] if defn[:pattern]
        validation_opts[:range] = defn[:range] if defn[:range]
        validation_opts[:min] = defn[:min] if defn[:min]
        validation_opts[:max] = defn[:max] if defn[:max]
        validation_opts[:values] = defn[:values] if defn[:values]

        type = defn[:type]
        validation_opts[:of] = type[:of] if type.is_a?(Hash) && type[:name] == :array && type[:of]
        validation_opts[:keys] = type[:keys] if type.is_a?(Hash) && type[:name] == :hash && type[:keys]

        TypeConstraint.new(attr_name, type, validation_options: validation_opts)
      end

      # Get the value for a constraint
      #
      # For attribute constraints, get the instance variable value.
      # For dependency constraints, get the option's current value.
      def get_constraint_value(constraint)
        case constraint
        when RequiredConstraint, TypeConstraint, RangeConstraint, EnumConstraint,
             BooleanFlagConstraint, CardinalityConstraint
          @options.instance_variable_get("@#{constraint.attribute_name}")
        when DependencyConstraint
          @options.instance_variable_get("@#{constraint.option_name}")
        end
      end

      # Get context for constraint validation
      def constraint_context
        {
          options_accessor: ->(attr_name) { @options.instance_variable_get("@#{attr_name}") }
        }
      end
    end
  end
end
