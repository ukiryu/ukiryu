# frozen_string_literal: true

module Ukiryu
  module Models
    # Command definition for a tool
    #
    # @example
    #   cmd = CommandDefinition.new(
    #     name: 'convert',
    #     description: 'Convert image format',
    #     implements: ['convert'], # v2: command implements interface
    #     options: [OptionDefinition.new(...)],
    #     flags: [FlagDefinition.new(...)]
    #   )
    class CommandDefinition < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :description, :string
      attribute :usage, :string
      attribute :subcommand, :string
      attribute :belongs_to, :string  # Parent command this action belongs to
      attribute :cli_flag, :string    # CLI flag for this action (e.g., '-d' for delete)
      attribute :standalone_executable, :boolean, default: false # DEPRECATED: Use invocation.type instead
      attribute :aliases, :string, collection: true, initialize_empty: true
      attribute :use_env_vars, :string, collection: true, initialize_empty: true
      attribute :implements, :string, collection: true, initialize_empty: true # v2: interfaces this command implements

      # Collections of model objects (lutaml-model handles serialization automatically)
      attribute :options, OptionDefinition, collection: true
      attribute :flags, FlagDefinition, collection: true
      attribute :arguments, ArgumentDefinition, collection: true
      attribute :post_options, OptionDefinition, collection: true
      attribute :env_vars, EnvVarDefinition, collection: true
      attribute :exit_codes, ExitCodes # Exit code definitions for this command

      key_value do
        map 'name', to: :name
        map 'description', to: :description
        map 'usage', to: :usage
        map 'subcommand', to: :subcommand
        map 'options', to: :options
        map 'flags', to: :flags
        map 'arguments', to: :arguments
        map 'post_options', to: :post_options
        map 'env_vars', to: :env_vars
        map 'exit_codes', to: :exit_codes
        map 'use_env_vars', to: :use_env_vars
        map 'belongs_to', to: :belongs_to
        map 'cli_flag', to: :cli_flag
        map 'standalone_executable', to: :standalone_executable
        map 'aliases', to: :aliases
        map 'implements', to: :implements # v2: implements mapping (no collection: true in yaml)
      end

      # Check if this command/action belongs to a parent command
      #
      # @return [Boolean] true if belongs_to is set
      def belongs_to_command?
        !belongs_to.nil? && !belongs_to.empty?
      end

      # Check if this action is expressed as a flag
      #
      # @return [Boolean] true if cli_flag is set
      def flag_action?
        !cli_flag.nil? && !cli_flag.empty?
      end

      # Get an option by name using indexed O(1) lookup
      #
      # @param name [String, Symbol] the option name
      # @return [OptionDefinition, nil] the option
      def option(name)
        return nil unless options

        build_options_index unless @options_index_built
        @options_index[name.to_s]
      end

      # Get a flag by name using indexed O(1) lookup
      #
      # @param name [String, Symbol] the flag name
      # @return [FlagDefinition, nil] the flag
      def flag(name)
        return nil unless flags

        build_flags_index unless @flags_index_built
        @flags_index[name.to_s]
      end

      # Get an argument by name using indexed O(1) lookup
      #
      # @param name [String, Symbol] the argument name
      # @return [ArgumentDefinition, nil] the argument
      def argument(name)
        return nil unless arguments

        build_arguments_index unless @arguments_index_built
        @arguments_index[name.to_s]
      end

      # Get the last argument
      #
      # @return [ArgumentDefinition, nil] the last argument
      def last_argument
        return nil unless arguments

        arguments.find { |a| a.is_a?(ArgumentDefinition) && a.last? }
      end

      # Get regular arguments (not last)
      #
      # @return [Array<ArgumentDefinition>] regular arguments sorted by position
      def regular_arguments
        return [] unless arguments

        args = arguments.select { |a| a.is_a?(ArgumentDefinition) }
        args.reject(&:last?).sort_by(&:numeric_position)
      end

      # Check if command has a subcommand
      #
      # @return [Boolean] true if has subcommand
      def has_subcommand?
        !subcommand.nil? && !subcommand.empty?
      end

      # Check if this command should use a standalone executable
      # (for ImageMagick v6 style where identify/mogrify are separate commands)
      #
      # @return [Boolean] true if standalone_executable is true
      def standalone_executable?
        standalone_executable == true
      end

      # Clear all indexes
      #
      # Call this if collections are modified after initial loading
      #
      # @api private
      def clear_indexes!
        @options_index = nil
        @options_index_built = false
        @flags_index = nil
        @flags_index_built = false
        @arguments_index = nil
        @arguments_index_built = false
      end

      private

      # Build the options index hash for O(1) lookup
      #
      # @api private
      def build_options_index
        return unless options

        @options_index = options.to_h { |o| [o.name, o] }
        @options_index_built = true
      end

      # Build the flags index hash for O(1) lookup
      #
      # @api private
      def build_flags_index
        return unless flags

        @flags_index = flags.to_h { |f| [f.name, f] }
        @flags_index_built = true
      end

      # Build the arguments index hash for O(1) lookup
      #
      # @api private
      def build_arguments_index
        return unless arguments

        @arguments_index = arguments.to_h { |a| [a.name, a] }
        @arguments_index_built = true
      end
    end
  end
end
