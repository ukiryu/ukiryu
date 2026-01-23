# frozen_string_literal: true

module Ukiryu
  module Validation
    # Abstract base class for all constraints
    #
    # Constraints define validation rules that can be applied to values.
    # Each constraint type encapsulates a specific validation logic.
    #
    # @abstract
    class Constraint
      # Validate a value against this constraint
      #
      # @param value [Object] the value to validate
      # @param context [Hash] additional context for validation
      # @return [void]
      # @raise [ValidationError] if validation fails
      def validate(value, context = {})
        raise NotImplementedError, 'Subclasses must implement validate'
      end

      # Check if this constraint applies to the given context
      #
      # @param context [Hash] validation context
      # @return [Boolean] true if constraint should be applied
      def applies_to?(_context)
        true
      end
    end

    # Validates that a value is present (not nil or empty)
    class RequiredConstraint < Constraint
      # The name of the attribute being validated
      attr_reader :attribute_name
      # The minimum required cardinality
      attr_reader :min

      # @param attribute_name [String, Symbol] the attribute name
      # @param min [Integer] minimum cardinality (default: 1)
      def initialize(attribute_name, min: 1)
        @attribute_name = attribute_name
        @min = min
      end

      # @raise [ValidationError] if value is nil or empty when required
      def validate(value, _context = {})
        return if @min.zero?

        is_empty = value.nil? || (value.respond_to?(:empty?) && value.empty?)
        return unless is_empty

        raise ValidationIssue.new(@attribute_name, :required,
                                  "Attribute #{@attribute_name} is required but missing")
      end
    end

    # Validates numeric or array length ranges
    class RangeConstraint < Constraint
      attr_reader :attribute_name, :min, :max

      # @param attribute_name [String, Symbol] the attribute name
      # @param min [Numeric] minimum value
      # @param max [Numeric] maximum value
      def initialize(attribute_name, min:, max:)
        @attribute_name = attribute_name
        @min = min
        @max = max
      end

      # @raise [ValidationError] if value is outside range
      def validate(value, _context = {})
        return if value.nil?

        check_value = value.is_a?(Array) ? value.size : value

        return unless check_value < @min || check_value > @max

        raise ValidationIssue.new(@attribute_name, :range,
                                  "#{@attribute_name} must be between #{@min} and #{@max}, got #{check_value}")
      end
    end

    # Validates that values match one of the allowed values
    class EnumConstraint < Constraint
      attr_reader :attribute_name, :allowed_values

      # @param attribute_name [String, Symbol] the attribute name
      # @param allowed_values [Array] the list of allowed values
      def initialize(attribute_name, allowed_values:)
        @attribute_name = attribute_name
        @allowed_values = allowed_values
      end

      # @raise [ValidationError] if value is not in allowed values
      def validate(value, _context = {})
        return if value.nil?

        if value.is_a?(Array)
          invalid = value - @allowed_values
          unless invalid.empty?
            raise ValidationIssue.new(@attribute_name, :enum,
                                      "#{@attribute_name} contains invalid values: #{invalid.join(', ')}. " \
                                      "Valid values: #{@allowed_values.join(', ')}")
          end
        elsif !@allowed_values.include?(value)
          raise ValidationIssue.new(@attribute_name, :enum,
                                    "#{@attribute_name} must be one of #{@allowed_values.join(', ')}, got #{value}")
        end
      end
    end

    # Validates type constraints using the Type module
    class TypeConstraint < Constraint
      attr_reader :attribute_name, :type, :validation_options

      # @param attribute_name [String, Symbol] the attribute name
      # @param type [Symbol, Hash] the type definition
      # @param validation_options [Hash] additional validation options
      def initialize(attribute_name, type, validation_options: {})
        @attribute_name = attribute_name
        @type = type
        @validation_options = validation_options
      end

      # @raise [ValidationError] if value doesn't match type
      def validate(value, _context = {})
        return if value.nil?

        begin
          Type.validate(value, @type, @validation_options)
        rescue Ukiryu::ValidationError => e
          raise ValidationIssue.new(@attribute_name, :type,
                                    "#{@attribute_name}: #{e.message}")
        end
      end
    end

    # Validates cardinality constraints for variadic arguments
    class CardinalityConstraint < Constraint
      attr_reader :attribute_name, :min, :max

      # @param attribute_name [String, Symbol] the attribute name
      # @param min [Integer] minimum cardinality
      # @param max [Integer, Float] maximum cardinality (Float::INFINITY for no limit)
      def initialize(attribute_name, min:, max:)
        @attribute_name = attribute_name
        @min = min
        @max = max
      end

      # @raise [ValidationError] if array size violates cardinality
      def validate(value, _context = {})
        return if value.nil? || !value.is_a?(Array)

        return unless @max != Float::INFINITY && value.size > @max

        raise ValidationIssue.new(@attribute_name, :cardinality,
                                  "Too many values for #{@attribute_name}: got #{value.size}, max #{@max}")
      end
    end

    # Validates that boolean flags are actually boolean
    class BooleanFlagConstraint < Constraint
      attr_reader :attribute_name

      # @param attribute_name [String, Symbol] the attribute name
      def initialize(attribute_name)
        @attribute_name = attribute_name
      end

      # @raise [ValidationError] if flag is not boolean
      def validate(value, _context = {})
        return if value.nil?

        return if [true, false].include?(value)

        raise ValidationIssue.new(@attribute_name, :boolean,
                                  "Flag #{@attribute_name} must be boolean, got #{value.class}: #{value}")
      end
    end

    # Validates dependency constraints between options
    class DependencyConstraint < Constraint
      attr_reader :option_name, :requires, :conflicts, :implies

      # @param option_name [String, Symbol] the option name
      # @param requires [Array] options that must be present
      # @param conflicts [Array] options that cannot be present
      # @param implies [Hash] options that imply certain values
      def initialize(option_name, requires: nil, conflicts: nil, implies: nil)
        @option_name = option_name
        @requires = requires
        @conflicts = conflicts
        @implies = implies
      end

      # @param value [Object] the value of the dependent option
      # @param context [Hash] must contain :options_accessor to get other values
      # @raise [ValidationError] if dependency constraints are violated
      def validate(_value, context = {})
        accessor = context[:options_accessor]
        raise ArgumentError, 'Dependency validation requires :options_accessor' unless accessor

        validate_requires(accessor)
        validate_conflicts(accessor)
        validate_implies(accessor)
      end

      private

      def validate_requires(accessor)
        return unless @requires

        @requires.each do |required_opt|
          required_value = accessor.call(required_opt)
          if required_value.nil? || (required_value.is_a?(Array) && required_value.empty?)
            raise ValidationIssue.new(@option_name, :dependency,
                                      "Option #{@option_name} requires #{required_opt} to be set")
          end
        end
      end

      def validate_conflicts(accessor)
        return unless @conflicts

        @conflicts.each do |conflict_opt|
          conflict_value = accessor.call(conflict_opt)
          if conflict_value && !conflict_value.nil? && !(conflict_value.is_a?(Array) && conflict_value.empty?)
            raise ValidationIssue.new(@option_name, :dependency,
                                      "Option #{@option_name} conflicts with #{conflict_opt}")
          end
        end
      end

      def validate_implies(accessor)
        return unless @implies

        @implies.each do |implies_opt, implies_def|
          current_value = accessor.call(implies_opt)
          expected_value = implies_def[:value]
          should_be_present = implies_def[:present]

          if should_be_present && (current_value.nil? || (current_value.is_a?(Array) && current_value.empty?))
            raise ValidationIssue.new(@option_name, :dependency,
                                      "Option #{@option_name} implies #{implies_opt} should be set")
          elsif !should_be_present && !current_value.nil?
            raise ValidationIssue.new(@option_name, :dependency,
                                      "Option #{@option_name} implies #{implies_opt} should not be set")
          elsif expected_value && current_value != expected_value
            raise ValidationIssue.new(@option_name, :dependency,
                                      "Option #{@option_name} implies #{implies_opt} should be #{expected_value}, got #{current_value}")
          end
        end
      end
    end

    # Validation issue represents a single validation problem
    #
    # This is a proper error object, not just a string.
    class ValidationIssue < StandardError
      # The attribute name that failed validation
      attr_reader :attribute_name

      # The type of validation that failed
      attr_reader :validation_type

      # Human-readable error message
      attr_reader :message

      # @param attribute_name [String, Symbol] the attribute that failed
      # @param validation_type [Symbol] the type of validation
      # @param message [String] human-readable error message
      def initialize(attribute_name, validation_type, message)
        @attribute_name = attribute_name
        @validation_type = validation_type
        @message = message
        super(message)
      end
    end
  end
end
