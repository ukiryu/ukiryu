# frozen_string_literal: true

module Ukiryu
  module Options
    # Abstract base class for all option classes
    #
    # This class provides common functionality for all dynamically generated
    # option classes, including batch setting via .set() and execution via .run().
    #
    # @abstract
    class Base
      # Set multiple options at once
      #
      # This method allows batch assignment of options. Each key in the params
      # hash should correspond to an attribute name.
      #
      # @param params [Hash] hash of option names to values
      # @return [self] returns self for method chaining
      #
      # @example Batch setting options
      #   options.set(inputs: ["image.png"], resize: "50%")
      #   options.output = "output.jpg"
      def set(params)
        params.each do |key, value|
          setter = "#{key}="
          send(setter, value) if respond_to?(setter)
        end
        self
      end

      # Validate the options
      #
      # Performs comprehensive validation using constraint-based validation.
      # This includes:
      # - Type checking using TypeConstraint
      # - Required argument checking using RequiredConstraint
      # - Value constraints (min, max, range) using RangeConstraint
      # - Enum value validation using EnumConstraint
      # - Option dependencies using DependencyConstraint
      #
      # @return [Boolean] true if valid
      # @raise [Ukiryu::Errors::ValidationError] if validation fails
      def validate!
        command_def = self.class.command_def
        return true unless command_def

        validator = Validation::Validator.new(self, command_def)
        validator.validate!
      end

      # Check if options are valid without raising errors
      #
      # @return [Boolean] true if valid, false otherwise
      def valid?
        validate!
        true
      rescue Ukiryu::Errors::ValidationError
        false
      end

      # Get validation errors without raising exceptions
      #
      # @return [Array<String>] list of error messages
      def validation_errors
        command_def = self.class.command_def
        return [] unless command_def

        validator = Validation::Validator.new(self, command_def)
        validator.errors
      end

      # Convert options to shell command string
      #
      # @param shell_type [Symbol] the shell type (:bash, :zsh, :fish, :powershell, etc.)
      # @return [String] the formatted shell command (without executable)
      def to_shell(shell_type: :bash)
        raise NotImplementedError, 'Subclasses must implement to_shell'
      end

      # Get the command definition
      #
      # @return [Hash, nil] the command definition from the profile
      def command_def
        self.class.command_def
      end

      # Get the command name
      #
      # @return [Symbol] the command name
      def command_name
        self.class.command_name
      end
    end
  end
end
