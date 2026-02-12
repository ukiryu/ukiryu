# frozen_string_literal: true

require 'uri'
require 'time'

module Ukiryu
  # Type validation and conversion
  #
  # Validates and converts parameters according to their type definitions.
  module Type
    class << self
      # Validate a value against a type definition
      #
      # @param value [Object] the value to validate
      # @param type [Symbol, Hash] the type definition
      # @param options [Hash] additional validation options
      # @return [Object] the validated and converted value
      # @raise [ValidationError] if validation fails
      def validate(value, type, options = {})
        type_definition = normalize_type(type)

        case type_definition[:name]
        when :file
          validate_file(value, options)
        when :string
          validate_string(value, options)
        when :integer
          validate_integer(value, options)
        when :float
          validate_float(value, options)
        when :symbol
          validate_symbol(value, options)
        when :boolean
          validate_boolean(value)
        when :uri
          validate_uri(value, options)
        when :datetime
          validate_datetime(value, options)
        when :hash
          validate_hash(value, options)
        when :array
          validate_array(value, options)
        else
          raise Ukiryu::Errors::ValidationError, "Unknown type: #{type_definition[:name]}"
        end
      end

      # Normalize type definition to hash format
      #
      # @param type [Symbol, String, Hash] the type definition
      # @return [Hash] normalized type definition
      def normalize_type(type)
        if type.is_a?(Hash)
          type
        else
          # Convert string types to symbols for consistency
          type_sym = type.is_a?(String) ? type.to_sym : type
          { name: type_sym }
        end
      end

      # Check if a type is valid
      #
      # @param type [Symbol, Hash] the type to check
      # @return [Boolean]
      def valid_type?(type)
        type_definition = normalize_type(type)
        VALID_TYPES.include?(type_definition[:name])
      end

      private

      VALID_TYPES = %i[file string integer float symbol boolean uri datetime hash array].freeze

      # Validate file type
      def validate_file(value, options)
        value = value.to_s
        raise Ukiryu::Errors::ValidationError, 'File path cannot be empty' if value.empty?

        # Check if file exists (only if require_existing is true)
        if options[:require_existing] && !File.exist?(value)
          raise Ukiryu::Errors::ValidationError,
                "File not found: #{value}"
        end

        value
      end

      # Validate string type
      def validate_string(value, options)
        value = value.to_s
        raise Ukiryu::Errors::ValidationError, 'String cannot be empty' if value.empty? && !options[:allow_empty]

        if options[:pattern] && value !~ options[:pattern]
          raise Ukiryu::Errors::ValidationError,
                "String does not match required pattern: #{options[:pattern]}"
        end

        value
      end

      # Validate integer type
      def validate_integer(value, options)
        value = value.is_a?(String) ? value.strip : value

        begin
          integer = Integer(value)
        rescue ArgumentError, TypeError
          raise Ukiryu::Errors::ValidationError, "Invalid integer: #{value.inspect}"
        end

        if options[:range]
          min, max = options[:range]
          if integer < min || integer > max
            raise Ukiryu::Errors::ValidationError,
                  "Integer #{integer} out of range [#{min}, #{max}]"
          end
        end

        if options[:min] && integer < options[:min]
          raise Ukiryu::Errors::ValidationError,
                "Integer #{integer} below minimum #{options[:min]}"
        end

        if options[:max] && integer > options[:max]
          raise Ukiryu::Errors::ValidationError,
                "Integer #{integer} above maximum #{options[:max]}"
        end

        integer
      end

      # Validate float type
      def validate_float(value, options)
        value = value.is_a?(String) ? value.strip : value

        begin
          float = Float(value)
        rescue ArgumentError, TypeError
          raise Ukiryu::Errors::ValidationError, "Invalid float: #{value.inspect}"
        end

        if options[:range]
          min, max = options[:range]
          if float < min || float > max
            raise Ukiryu::Errors::ValidationError,
                  "Float #{float} out of range [#{min}, #{max}]"
          end
        end

        float
      end

      # Validate symbol type
      def validate_symbol(value, options)
        value = value.is_a?(Symbol) ? value : value.to_s.downcase.to_sym

        if options[:values]
          # Convert values to symbols for comparison (handle both string and symbol values)
          valid_values = options[:values].map { |v| v.is_a?(String) ? v.to_sym : v }
          unless valid_values.include?(value)
            raise Ukiryu::Errors::ValidationError,
                  "Invalid symbol: #{value.inspect}. Valid values: #{options[:values].inspect}"
          end
        end

        value
      end

      # Validate boolean type
      def validate_boolean(value)
        # Accept various boolean representations
        case value
        when TrueClass, FalseClass
          value
        when 'true', '1', 'yes', 'on'
          true
        when 'false', '0', 'no', 'off', ''
          false
        else
          raise Ukiryu::Errors::ValidationError, "Invalid boolean: #{value.inspect}"
        end
      end

      # Validate URI type
      def validate_uri(value, _options)
        value = value.to_s
        raise Ukiryu::Errors::ValidationError, 'URI cannot be empty' if value.empty?

        begin
          uri = URI.parse(value)
          raise Ukiryu::Errors::ValidationError, "Invalid URI: #{value}" unless uri.is_a?(URI::Generic)

          uri.to_s
        rescue URI::InvalidURIError => e
          raise Ukiryu::Errors::ValidationError, "Invalid URI: #{value} - #{e.message}"
        end
      end

      # Validate datetime type
      def validate_datetime(value, _options)
        if value.is_a?(Time) || value.is_a?(DateTime)
          value
        else
          begin
            Time.parse(value.to_s)
          rescue ArgumentError => e
            raise Ukiryu::Errors::ValidationError, "Invalid datetime: #{value.inspect} - #{e.message}"
          end
        end
      end

      # Validate hash type
      def validate_hash(value, options)
        unless value.is_a?(Hash)
          raise Ukiryu::Errors::ValidationError,
                "Hash expected, got #{value.class}: #{value.inspect}"
        end

        if options[:keys]
          unknown_keys = value.keys - options[:keys]
          if unknown_keys.any?
            raise Ukiryu::Errors::ValidationError,
                  "Unknown hash keys: #{unknown_keys.inspect}. Valid keys: #{options[:keys].inspect}"
          end
        end

        value
      end

      # Validate array type
      def validate_array(value, options)
        # Debug logging for executable discovery
        Logger.debug("Type.validate_array value.class: #{value.class}", category: :executable)
        Logger.debug("Type.validate_array value.inspect: #{value.inspect}", category: :executable)
        Logger.debug("Type.validate_array options: #{options.inspect}", category: :executable)

        array = value.is_a?(Array) ? value : [value]

        Logger.debug("Type.validate_array after conversion, array.class: #{array.class}",
                     category: :executable)
        Logger.debug("Type.validate_array after conversion, array.inspect: #{array.inspect}",
                     category: :executable)

        if options[:min] && array.size < options[:min]
          raise Ukiryu::Errors::ValidationError,
                "Array has #{array.size} elements, minimum is #{options[:min]}"
        end

        if options[:max] && array.size > options[:max]
          raise Ukiryu::Errors::ValidationError,
                "Array has #{array.size} elements, maximum is #{options[:max]}"
        end

        if options[:size]
          if options[:size].is_a?(Integer)
            if array.size != options[:size]
              raise Ukiryu::Errors::ValidationError,
                    "Array has #{array.size} elements, expected #{options[:size]}"
            end
          elsif options[:size].is_a?(Array)
            unless options[:size].include?(array.size)
              raise Ukiryu::Errors::ValidationError,
                    "Array has #{array.size} elements, expected one of: #{options[:size].inspect}"
            end
          end
        end

        # Validate element type if specified
        array = array.map { |v| validate(v, options[:of], options) } if options[:of]

        Logger.debug("Type.validate_array returning array.inspect: #{array.inspect}",
                     category: :executable)

        array
      end
    end
  end
end
