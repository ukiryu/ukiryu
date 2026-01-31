# frozen_string_literal: true

module Ukiryu
  module Definition
    module Sources
      # Load tool definitions from a YAML string
      #
      # This source handles YAML content provided directly as a string,
      # useful for definitions obtained via command-line flags or
      # programmatic generation.
      class StringSource < Source
        # The YAML content
        # @return [String] the YAML string
        attr_reader :content

        # The SHA256 hash of the content
        # @return [String] hexadecimal hash
        attr_reader :content_hash

        # Create a new string-based definition source
        #
        # @param content [String] the YAML content
        # @raise [ArgumentError] if content is not a String
        # @raise [DefinitionLoadError] if content is empty
        def initialize(content)
          @content = validate_content!(content)
          @content_hash = sha256(@content)
        end

        # Load the YAML definition content
        #
        # @return [String] the YAML content
        def load
          @content
        end

        # Get the source type
        #
        # @return [Symbol] :string
        def source_type
          :string
        end

        # Get a unique cache key for this string source
        #
        # The cache key is based on the SHA256 hash of the content,
        # ensuring identical strings produce identical cache keys.
        #
        # @return [String] unique cache key
        def cache_key
          "string:#{content_hash}"
        end

        # Get the size of the content in bytes
        #
        # @return [Integer] content size
        def size
          @content.bytesize
        end

        private

        # Validate the content
        #
        # @param content [String] the content to validate
        # @return [String] the validated content
        # @raise [ArgumentError] if content is not a String
        # @raise [DefinitionLoadError] if content is empty
        def validate_content!(content)
          unless content.is_a?(String)
            raise ArgumentError,
                  "Definition content must be a String, got #{content.class}"
          end

          if content.empty?
            raise Ukiryu::Errors::DefinitionLoadError,
                  'Definition content cannot be empty'
          end

          # Strip leading/trailing whitespace but preserve internal formatting
          content.strip
        end
      end
    end
  end
end
