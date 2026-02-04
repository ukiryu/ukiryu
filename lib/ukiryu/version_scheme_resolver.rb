# frozen_string_literal: true

require 'versionian'

module Ukiryu
  # Resolves version scheme specifications to Versionian scheme objects.
  #
  # Schemes are defined inline in implementation YAML files in the register.
  # This resolver handles two modes:
  # 1. Reference to Versionian built-in schemes (semantic, calver, etc.)
  # 2. Inline declarative scheme definitions (Hash)
  #
  # @example Reference built-in scheme
  #   scheme = VersionSchemeResolver.resolve(:semantic)
  #
  # @example Inline declaration
  #   scheme = VersionSchemeResolver.resolve(
  #     { 'name' => 'custom', 'type' => 'declarative', 'components' => [...] }
  #   )
  class VersionSchemeResolver
    class << self
      # Resolve a scheme specification to a Versionian VersionScheme object.
      #
      # @param scheme_spec [String, Hash, Symbol] Scheme name (symbol/string) or inline declaration (hash)
      # @return [Versionian::VersionScheme] Resolved scheme object
      def resolve(scheme_spec)
        if scheme_spec.is_a?(Hash)
          load_inline_scheme(scheme_spec)
        elsif scheme_spec.is_a?(String) || scheme_spec.is_a?(Symbol)
          load_builtin_scheme(scheme_spec)
        else
          raise ArgumentError, "Invalid scheme specification: #{scheme_spec.inspect}"
        end
      end

      # Check if a scheme spec is inline (Hash) or reference (String/Symbol)
      #
      # @param scheme_spec [String, Hash, Symbol] Scheme specification
      # @return [Boolean] true if inline declaration
      def inline?(scheme_spec)
        scheme_spec.is_a?(Hash)
      end

      # Check if a scheme spec is a reference (String/Symbol)
      #
      # @param scheme_spec [String, Hash, Symbol] Scheme specification
      # @return [Boolean] true if reference
      def reference?(scheme_spec)
        scheme_spec.is_a?(String) || scheme_spec.is_a?(Symbol)
      end

      private

      # Load a Versionian built-in scheme by name.
      #
      # @param name [String, Symbol] Scheme name
      # @return [Versionian::VersionScheme] Loaded scheme
      def load_builtin_scheme(name)
        name_sym = name.to_sym
        ::Versionian.get_scheme(name_sym)
      end

      # Load an inline declarative scheme.
      #
      # @param declaration [Hash] Scheme declaration hash (string keys)
      # @return [::Versionian::VersionScheme] Loaded scheme
      def load_inline_scheme(declaration)
        ::Versionian::SchemeLoader.from_hash(declaration)
      end
    end
  end
end
