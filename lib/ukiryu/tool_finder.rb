# frozen_string_literal: true

module Ukiryu
  # Tool finding by name, interface, or alias
  #
  # Provides methods to discover tools by various identifiers:
  # - Exact name match
  # - Interface implementation (e.g., :convert, :video_encoder)
  # - Shell aliases
  #
  # @api private
  module ToolFinder
    class << self
      # Find a tool by name, alias, or interface
      #
      # Searches for a tool that matches the given identifier by:
      # 1. Exact name match (fastest)
      # 2. Interface match via ToolIndex (O(1) lookup)
      # 3. Alias match via ToolIndex (O(1) lookup)
      # 4. Returns the first tool that is available on the current platform
      #
      # Debug mode: Set UKIRYU_DEBUG=1 or UKIRYU_DEBUG=true to enable structured debug output
      #
      # @param identifier [String, Symbol] the tool name, interface, or alias
      # @param options [Hash] initialization options
      # @return [Tool, nil] the tool instance or nil if not found
      def find_by(identifier, options = {})
        require_relative 'tool_cache'
        require_relative 'tool'

        identifier = identifier.to_s
        runtime = Ukiryu::Runtime.instance
        platform = options[:platform] || runtime.platform
        shell = options[:shell] || runtime.shell

        # Create logger instance
        logger = Ukiryu::Logger.new

        # 1. Try exact name match first (fastest path)
        begin
          tool = Ukiryu::Tool.get(identifier, options)
          if logger.debug_enabled?
            all_tools = Ukiryu::Register.tools
            logger.debug_section_tool_resolution(
              identifier: identifier,
              platform: platform,
              shell: shell,
              all_tools: all_tools,
              selected_tool: identifier,
              executable: tool.executable
            )
          end
          return tool
        rescue Ukiryu::Errors::ToolNotFoundError, Ukiryu::Errors::ProfileNotFoundError
          # Continue to search by interface/alias
        end

        # 2. Use ToolIndex for O(1) interface lookup
        index = Ukiryu::ToolIndex.instance
        interface_tool_names = index.find_all_by_interface(identifier.to_sym)
        if interface_tool_names.any?
          interface_tool_names.each do |tool_name|
            tool = Ukiryu::Tool.get(tool_name.to_s, options)
            # Return tool only if it's available (executable found)
            return tool if tool.available?
          rescue Ukiryu::Errors::ToolNotFoundError, Ukiryu::Errors::ProfileNotFoundError
            # Tool indexed but not available, continue to next
          end
        end

        # 3. Use ToolIndex for O(1) alias lookup
        alias_tool_name = index.find_by_alias(identifier)
        if alias_tool_name
          begin
            return Ukiryu::Tool.get(alias_tool_name.to_s, options)
          rescue Ukiryu::Errors::ToolNotFoundError, Ukiryu::Errors::ProfileNotFoundError
            # Alias indexed but tool not available, continue
          end
        end

        # 4. Fallback to exhaustive search (should rarely reach here)
        tool = exhaustive_search(identifier, options, platform, shell, logger)
        return tool if tool

        if logger.debug_enabled?
          all_tools = Ukiryu::Register.tools
          logger.debug_section_tool_not_found(
            identifier: identifier,
            platform: platform,
            shell: shell,
            all_tools: all_tools
          )
        end
        nil
      end

      # Find all instances of a tool in PATH and aliases
      #
      # This is an explicit operation - user must ask for it.
      # Returns an array of ExecutableInfo for all matches found.
      #
      # @param tool_name [String, Symbol] the tool to find
      # @param options [Hash] initialization options
      # @return [Array<Models::ExecutableInfo>] all discovery information
      def find_all(tool_name, options = {})
        require_relative 'models/executable_info'
        require_relative 'shell/alias_detector' unless defined?(Shell::AliasDetector)

        shell = options[:shell]&.to_sym || Ukiryu::Runtime.instance.shell
        results = []

        # Check PATH using 'command -v' which can show multiple matches
        path_results = `command -v #{tool_name} 2>/dev/null`
        path_results&.split("\n")&.each do |line|
          line.strip!
          next if line.empty?

          results << Ukiryu::Models::ExecutableInfo.new(
            path: line,
            source: :path,
            shell: shell,
            alias_definition: nil
          )
        end

        # Check shell aliases
        alias_info = Shell::AliasDetector.detect(tool_name.to_s, shell)
        if alias_info
          results << Ukiryu::Models::ExecutableInfo.new(
            path: extract_alias_target(alias_info),
            source: :alias,
            shell: shell,
            alias_definition: alias_info[:definition]
          )
        end

        results
      end

      # Get the tool-specific class (new OOP API)
      #
      # @param tool_name [Symbol, String] the tool name
      # @return [Class] the tool class (e.g., Ukiryu::Tools::Imagemagick)
      def get_class(tool_name)
        Ukiryu::Tools::Generator.generate_and_const_set(tool_name)
      end

      # Extract the command target from an alias definition
      #
      # @param alias_info [Hash] the alias info with :target key
      # @return [String] the extracted command
      def extract_alias_target(alias_info)
        target = alias_info[:target]
        # Extract the first word from the target
        target.split(/\s+/).first
      end

      private

      # Exhaustive fallback search for tools
      #
      # Searches all tools in the register for interface or alias matches.
      # Used when fast index lookups fail.
      #
      # @param identifier [String] the tool name, interface, or alias
      # @param options [Hash] initialization options
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      # @param logger [Logger] the logger instance
      # @return [Tool, nil] the tool instance or nil if not found
      def exhaustive_search(identifier, options, platform, shell, logger)
        require_relative 'tool_cache'
        require_relative 'tool'

        all_tools = Ukiryu::Register.tools

        all_tools.each do |tool_name|
          # Try new architecture first (uses index.yaml)
          tool = nil
          begin
            tool = Ukiryu::Tool.get(tool_name, options.merge(platform: platform, shell: shell))
          rescue Ukiryu::Errors::ToolNotFoundError
            # Fall back to old architecture
            tool_def = Ukiryu::Tools::Generator.load_tool_definition(tool_name)
            next unless tool_def

            # Check if tool matches by interface
            # v2: implements is an array, check if interface is in the array
            # v1: implements is a string, check for equality
            implements_value = tool_def.implements
            interface_match = if implements_value.is_a?(Array)
                                implements_value.map(&:to_sym).include?(identifier.to_sym)
                              else
                                implements_value == identifier.to_s
                              end

            # Check if tool matches by alias
            alias_match = tool_def.aliases&.include?(identifier)

            next unless alias_match || interface_match

            # Check if tool is compatible with current platform/shell
            profile = tool_def.compatible_profile(platform: platform, shell: shell)
            next unless profile

            # Create tool instance
            cache_key = Ukiryu::ToolCache.cache_key_for(tool_name, options)
            cached = Ukiryu::ToolCache.cache[cache_key]

            if cached
              if logger.debug_enabled?
                logger.debug_section_tool_resolution(
                  identifier: identifier,
                  platform: platform,
                  shell: shell,
                  all_tools: all_tools,
                  selected_tool: tool_name,
                  executable: cached.executable
                )
              end
              return cached
            end

            tool = Ukiryu::Tool.new(tool_def, options.merge(platform: platform, shell: shell))
            Ukiryu::ToolCache.set(cache_key, tool)
          end

          next unless tool

          # For new architecture, check if tool matches by interface or alias
          # Get the profile which has implements and aliases
          profile = tool.profile
          next unless profile

          implements_value = profile.implements
          interface_match = if implements_value.is_a?(Array)
                              implements_value.map(&:to_sym).include?(identifier.to_sym)
                            elsif implements_value
                              implements_value.to_sym == identifier.to_sym
                            else
                              false
                            end

          aliases_value = profile.aliases
          alias_match = aliases_value&.include?(identifier)

          next unless alias_match || interface_match

          if logger.debug_enabled?
            logger.debug_section_tool_resolution(
              identifier: identifier,
              platform: platform,
              shell: shell,
              all_tools: all_tools,
              selected_tool: tool_name,
              executable: tool.executable
            )
          end

          return tool
        end

        nil
      end
    end
  end
end
