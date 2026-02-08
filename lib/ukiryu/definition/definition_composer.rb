# frozen_string_literal: true

module Ukiryu
  module Definition
    # Compose tool definitions from multiple sources
    #
    # This class handles merging and composing tool definitions,
    # allowing for profile inheritance and command mixins.
    class DefinitionComposer
      # Merge strategies
      MERGE_STRATEGIES = %i[override replace prepend append].freeze

      # Compose a definition with its includes/inherits
      #
      # @param definition [Models::ToolDefinition] the base definition
      # @param loader [Object] the loader to use for loading dependencies
      # @return [Models::ToolDefinition] the composed definition
      def self.compose(definition, loader: nil)
        @loader = loader || Loader

        # Process inherits first (base definitions)
        definition = process_inherits(definition) if definition.respond_to?(:inherits) && definition.inherits

        # Process includes (additions)
        definition = process_includes(definition) if definition.respond_to?(:includes) && definition.includes

        definition
      end

      # Process inherits clauses
      #
      # @param definition [Models::ToolDefinition] the definition
      # @return [Models::ToolDefinition] the merged definition
      def self.process_inherits(definition)
        inherits = definition.inherits || []
        return definition if inherits.empty?

        # Load base definitions and merge them
        inherits.reverse.reduce(definition) do |current, inherit_spec|
          base_def = load_base_definition(inherit_spec)
          next current unless base_def

          merge_definitions(base_def, current, strategy: :replace)
        end
      end

      # Process includes clauses
      #
      # @param definition [Models::ToolDefinition] the definition
      # @return [Models::ToolDefinition] the merged definition
      def self.process_includes(definition)
        includes = definition.includes || []
        return definition if includes.empty?

        # Load included definitions and merge them
        includes.reduce(definition) do |current, include_spec|
          include_def = load_base_definition(include_spec)
          next current unless include_def

          merge_definitions(current, include_def, strategy: :append)
        end
      end

      # Load a base definition from a spec
      #
      # @param spec [Hash, String] the specification
      # @return [Models::ToolDefinition, nil] the loaded definition
      def self.load_base_definition(spec)
        case spec
        when String
          # Just a tool name, find latest version
          metadata = Discovery.find(spec)
          metadata&.load_definition
        when Hash
          tool = spec[:tool] || spec['tool']
          version = spec[:version] || spec['version']

          metadata = if version
                       Discovery.find(tool, version)
                     else
                       Discovery.find(tool)
                     end

          metadata&.load_definition
        end
      end

      # Merge two definitions
      #
      # @param base [Models::ToolDefinition] the base definition
      # @param addition [Models::ToolDefinition] the definition to merge in
      # @param strategy [Symbol] the merge strategy
      # @return [Models::ToolDefinition] the merged definition
      def self.merge_definitions(base, addition, strategy: :override)
        # Create a merged definition by deep copying and merging
        merged = base.dup

        # Merge profiles
        if addition.profiles
          merged.profiles ||= []

          case strategy
          when :replace
            merged.profiles = addition.profiles.dup
          when :override
            # Merge by profile name, addition overrides base
            merged.profiles = merge_profiles_by_name(base.profiles || [], addition.profiles)
          when :append
            # Append addition profiles
            merged.profiles = (base.profiles || []) + addition.profiles
          when :prepend
            # Prepend addition profiles
            merged.profiles = addition.profiles + (base.profiles || [])
          end
        end

        # Merge commands if profiles have them
        merged.profiles&.each do |profile|
          # Find corresponding profile in addition
          addition_profile = find_profile(addition.profiles, profile.name)
          next unless addition_profile

          # Merge commands
          next unless addition_profile.commands

          profile.commands ||= []
          case strategy
          when :replace
            profile.commands = addition_profile.commands.dup
          when :override
            profile.commands = merge_commands_by_name(profile.commands, addition_profile.commands)
          when :append
            profile.commands = profile.commands + addition_profile.commands
          when :prepend
            profile.commands = addition_profile.commands + profile.commands
          end
        end

        merged
      end

      # Merge profiles by name
      #
      # @param base_profiles [Array] base profiles
      # @param addition_profiles [Array] profiles to merge
      # @return [Array] merged profiles
      def self.merge_profiles_by_name(base_profiles, addition_profiles)
        merged = base_profiles.dup

        addition_profiles.each do |addition_profile|
          existing_index = merged.find_index { |p| p.name == addition_profile.name }

          if existing_index
            # Merge the profile content
            existing = merged[existing_index]
            merged[existing_index] = merge_profile_content(existing, addition_profile)
          else
            # Add new profile
            merged << addition_profile.dup
          end
        end

        merged
      end

      # Merge the content of two profiles
      #
      # @param base [Object] the base profile
      # @param addition [Object] the profile to merge
      # @return [Object] merged profile
      def self.merge_profile_content(base, addition)
        # Create a new profile that merges both
        merged = base.dup

        # Merge commands
        merged.commands = merge_commands_by_name(base.commands || [], addition.commands) if addition.commands

        # Merge other arrays if they exist
        %i[environment options flags arguments].each do |attr|
          if addition.respond_to?(attr) && addition.send(attr)
            base_items = base.respond_to?(attr) ? base.send(attr) : []
            merged.send("#{attr}=", base_items + addition.send(attr))
          end
        end

        # Override scalars
        %i[description option_style].each do |attr|
          merged.send("#{attr}=", addition.send(attr)) if addition.respond_to?(attr) && !addition.send(attr).nil?
        end

        merged
      end

      # Merge commands by name
      #
      # @param base_commands [Array] base commands
      # @param addition_commands [Array] commands to merge
      # @return [Array] merged commands
      def self.merge_commands_by_name(base_commands, addition_commands)
        merged = base_commands.dup

        addition_commands.each do |addition_command|
          existing_index = merged.find_index { |c| c.name == addition_command.name }

          if existing_index
            # Override existing command
            merged[existing_index] = addition_command.dup
          else
            # Add new command
            merged << addition_command.dup
          end
        end

        merged
      end

      # Find a profile by name
      #
      # @param profiles [Array] the profiles array
      # @param name [String] the profile name
      # @return [Object, nil] the profile or nil
      def self.find_profile(profiles, name)
        return nil unless profiles

        profiles.find { |p| p.name == name }
      end

      # Validate that a definition can be composed
      #
      # @param definition [Models::ToolDefinition] the definition to validate
      # @return [Array<String>] array of validation errors (empty if valid)
      def self.validate_composable(definition)
        errors = []

        # Check inherits
        if definition.respond_to?(:inherits) && definition.inherits
          definition.inherits.each do |inherit_spec|
            base_def = load_base_definition(inherit_spec)
            errors << "Cannot inherit from '#{inherit_spec}': definition not found" unless base_def
          end
        end

        # Check includes
        if definition.respond_to?(:includes) && definition.includes
          definition.includes.each do |include_spec|
            include_def = load_base_definition(include_spec)
            errors << "Cannot include '#{include_spec}': definition not found" unless include_def
          end
        end

        errors
      end
    end
  end
end
