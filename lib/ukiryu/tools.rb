# frozen_string_literal: true

require_relative 'tools/base'
require_relative 'tools/generator'

module Ukiryu
  # Tools namespace for tool-specific classes
  #
  # This namespace provides lazy-autoloaded tool classes.
  # When you reference Ukiryu::Tools::Imagemagick, it automatically
  # generates the class if it doesn't exist.
  #
  # Platform aliases are also supported - e.g., Ping resolves to PingBsd
  # on macOS or PingGnu on Linux.
  #
  # @example
  #   Ukiryu::Tools::Imagemagick.new.tap do |tool|
  #     options = tool.options_for(:convert)
  #     options.set(inputs: ["image.png"], resize: "50%")
  #     options.run
  #   end
  #
  # @example Platform alias
  #   # Automatically uses PingBsd on macOS, PingGnu on Linux
  #   Ukiryu::Tools::Ping.new.execute(:ping, host: 'localhost', count: 1)
  module Tools
    class << self
      # Autoload tool classes via const_missing
      #
      # When you reference Ukiryu::Tools::Imagemagick, this method automatically
      # generates the class if it doesn't exist.
      #
      # Platform aliases are resolved first - e.g., Ping resolves to PingBsd
      # on macOS or PingGnu on Linux based on the current platform.
      #
      # @param name [String, Symbol] the constant name
      # @return [Class] the generated tool class
      def const_missing(name)
        # Convert CamelCase constant name to snake_case tool name
        # e.g., PingBsd -> ping_bsd, PingGnu -> ping_gnu, Ping -> ping
        tool_name_str = name.to_s
                            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # Add underscore before caps that follow lowercase
                            .gsub(/([a-z\d])([A-Z])/, '\1_\2') # Add underscore between lowercase and uppercase
                            .downcase

        tool_name = tool_name_str.to_sym

        # First, check if it's a platform alias
        # Look for tools that implement this alias for the current platform
        platform_impl = find_platform_implementation(tool_name)
        return Generator.generate_and_const_set(platform_impl) if platform_impl

        # If not an alias, try to generate the tool directly
        generated = Generator.generate_and_const_set(tool_name)
        return generated if generated

        # If nothing found, let the error propagate
        nil
      end

      private

      # Find a platform-specific implementation for a tool alias
      #
      # @param alias_name [Symbol] the alias to resolve
      # @return [Symbol, nil] the platform-specific tool name
      def find_platform_implementation(alias_name)
        register_path = Register.default_register_path
        return nil unless register_path && Dir.exist?(register_path)

        tools_dir = File.join(register_path, 'tools')
        return nil unless Dir.exist?(tools_dir)

        current_platform = Platform.detect

        # Search through all tool directories
        Dir.entries(tools_dir).each do |tool_dir|
          next if tool_dir.start_with?('.')

          tool_path = File.join(tools_dir, tool_dir)
          next unless File.directory?(tool_path)

          # Look for YAML files in this directory
          Dir.entries(tool_path).each do |yaml_file|
            next unless yaml_file.end_with?('.yaml')

            yaml_path = File.join(tool_path, yaml_file)
            profile = YAML.load_file(yaml_path, symbolize_names: true)

            # Check if this tool implements the alias and matches current platform
            # Note: implements field is a string in YAML, convert to symbol for comparison
            next unless profile[:implements]&.to_sym == alias_name

            # Check platform compatibility
            profiles = profile[:profiles] || []
            compatible = profiles.any? do |p|
              platforms = p[:platforms] || p[:platform]
              platforms.nil? || platforms.map(&:to_sym).include?(current_platform)
            end

            return tool_dir.to_sym if compatible
          end
        end

        nil
      end
    end
  end
end
