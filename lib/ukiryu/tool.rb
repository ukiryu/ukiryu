# frozen_string_literal: true

require_relative "registry"
require_relative "executor"
require_relative "shell"

module Ukiryu
  # Tool wrapper class for external command-line tools
  #
  # Provides a Ruby interface to external CLI tools defined in YAML profiles.
  class Tool
    class << self
      # Registered tools cache
      attr_reader :tools

      # Get a tool by name
      #
      # @param name [String] the tool name
      # @param options [Hash] initialization options
      # @option options [String] :registry_path path to tool profiles
      # @option options [Symbol] :platform platform to use
      # @option options [Symbol] :shell shell to use
      # @option options [String] :version specific version to use
      # @return [Tool] the tool instance
      def get(name, options = {})
        # Check cache first
        cache_key = cache_key_for(name, options)
        return @tools[cache_key] if @tools && @tools[cache_key]

        # Load profile from registry
        profile = load_profile(name, options)
        raise ToolNotFoundError, "Tool not found: #{name}" unless profile

        # Create tool instance
        tool = new(profile, options)
        @tools ||= {}
        @tools[cache_key] = tool
        tool
      end

      # Clear the tool cache
      #
      # @api private
      def clear_cache
        @tools = nil
      end

      # Configure default options
      #
      # @param options [Hash] default options
      def configure(options = {})
        @default_options ||= {}
        @default_options.merge!(options)
      end

      private

      # Generate a cache key for a tool
      def cache_key_for(name, options)
        platform = options[:platform] || Platform.detect
        shell = options[:shell] || Shell.detect
        version = options[:version] || "latest"
        "#{name}-#{platform}-#{shell}-#{version}"
      end

      # Load a profile for a tool
      def load_profile(name, options)
        registry_path = options[:registry_path] || Registry.default_registry_path

        if registry_path && Dir.exist?(registry_path)
          Registry.load_tool(name, options)
        else
          # Fall back to built-in profiles if available
          load_builtin_profile(name, options)
        end
      end

      # Load a built-in profile
      def load_builtin_profile(name, options)
        # This will be extended with bundled profiles
        nil
      end
    end

    # Create a new Tool instance
    #
    # @param profile [Hash] the tool profile
    # @param options [Hash] initialization options
    def initialize(profile, options = {})
      @profile = profile
      @options = options
      @platform = options[:platform] || Platform.detect
      @shell = options[:shell] || Shell.detect
      @version = options[:version]

      # Find compatible profile
      @command_profile = find_command_profile
      raise ProfileNotFoundError, "No compatible profile for #{name}" unless @command_profile

      # Find executable
      @executable = find_executable
    end

    # Get the raw profile data
    #
    # @return [Hash] the tool profile
    attr_reader :profile

    # Get the tool name
    #
    # @return [String] the tool name
    def name
      @profile[:name]
    end

    # Get the tool version
    #
    # @return [String, nil] the tool version
    def version
      @version || detect_version
    end

    # Get the executable path
    #
    # @return [String] the executable path
    def executable
      @executable
    end

    # Check if the tool is available
    #
    # @return [Boolean]
    def available?
      !@executable.nil?
    end

    # Get the commands defined in the active profile
    #
    # @return [Hash, nil] the commands hash
    def commands
      @command_profile[:commands]
    end

    # Execute a command defined in the profile
    #
    # @param command_name [Symbol] the command to execute
    # @param params [Hash] command parameters
    # @return [Executor::Result] the execution result
    def execute(command_name, params = {})
      command = @command_profile[:commands][command_name.to_s] ||
                @command_profile[:commands][command_name.to_sym]

      raise ArgumentError, "Unknown command: #{command_name}" unless command

      # Build command arguments
      args = build_args(command, params)

      # Execute with environment
      Executor.execute(
        @executable,
        args,
        env: build_env_vars(command, params),
        timeout: @profile[:timeout] || 90,
        shell: @shell
      )
    end

    # Check if a command is available
    #
    # @param command_name [Symbol] the command name
    # @return [Boolean]
    def command?(command_name)
      cmd = @command_profile[:commands][command_name.to_s] ||
            @command_profile[:commands][command_name.to_sym]
      !cmd.nil?
    end

    private

    # Find the best matching command profile
    def find_command_profile
      return @profile[:profiles].first if @profile[:profiles].one?

      @profile[:profiles].find do |p|
        platforms = p[:platforms] || p[:platform]
        shells = p[:shells] || p[:shell]

        # Convert array elements to symbols for comparison
        # (YAML arrays contain strings, but platform/shell are symbols)
        platform_match = platforms.nil? || platforms.map(&:to_sym).include?(@platform)
        shell_match = shells.nil? || shells.map(&:to_sym).include?(@shell)

        platform_match && shell_match
      end
    end

    # Find the executable path
    def find_executable
      # Try primary name first
      exe = try_find_executable(@profile[:name])
      return exe if exe

      # Try aliases
      aliases = @profile[:aliases] || []
      aliases.each do |alias_name|
        exe = try_find_executable(alias_name)
        return exe if exe
      end

      nil
    end

    # Try to find an executable by name
    def try_find_executable(command)
      # Check custom search paths first
      search_paths = custom_search_paths
      unless search_paths.empty?
        search_paths.each do |path_pattern|
          paths = Dir.glob(path_pattern)
          paths.each do |path|
            return path if File.executable?(path) && !File.directory?(path)
          end
        end
      end

      # Fall back to PATH
      Executor.find_executable(command)
    end

    # Get custom search paths from profile
    def custom_search_paths
      return [] unless @profile[:search_paths]

      case @platform
      when :windows
        @profile[:search_paths][:windows] || []
      when :macos
        @profile[:search_paths][:macos] || []
      else
        [] # Unix: rely on PATH only
      end
    end

    # Detect tool version
    def detect_version
      return nil unless @profile[:version_detection]

      vd = @profile[:version_detection]
      cmd = vd[:command] || "--version"

      result = Executor.execute(@executable, [cmd], shell: @shell)

      if result.success?
        pattern = vd[:pattern] || /(\d+\.\d+)/
        match = result.stdout.match(pattern) || result.stderr.match(pattern)
        match[1] if match
      end
    end

    # Build command arguments from parameters
    def build_args(command, params)
      args = []

      # Add subcommand prefix if present (e.g., for ImageMagick "magick convert")
      if command[:subcommand]
        args << command[:subcommand]
      end

      # Add options first (before arguments)
      (command[:options] || []).each do |opt_def|
        # Convert name to symbol for params lookup
        param_key = opt_def[:name].is_a?(String) ? opt_def[:name].to_sym : opt_def[:name]
        next unless params.key?(param_key)
        next if params[param_key].nil?

        formatted_opt = format_option(opt_def, params[param_key])
        Array(formatted_opt).each { |opt| args << opt unless opt.nil? || opt.empty? }
      end

      # Add flags
      (command[:flags] || []).each do |flag_def|
        # Convert name to symbol for params lookup
        param_key = flag_def[:name].is_a?(String) ? flag_def[:name].to_sym : flag_def[:name]
        value = params[param_key]
        value = flag_def[:default] if value.nil?

        formatted_flag = format_flag(flag_def, value)
        Array(formatted_flag).each { |flag| args << flag unless flag.nil? || flag.empty? }
      end

      # Separate "last" positioned argument from other arguments
      arguments = command[:arguments] || []
      last_arg = arguments.find { |a| a[:position] == "last" || a[:position] == :last }
      regular_args = arguments.reject { |a| a[:position] == "last" || a[:position] == :last }

      # Add regular positional arguments (in order, excluding "last")
      regular_args.sort_by do |a|
        pos = a[:position]
        pos.is_a?(Integer) ? pos : (pos || 99)
      end.each do |arg_def|
        # Convert name to symbol for params lookup (YAML uses strings, Ruby uses symbols)
        param_key = arg_def[:name].is_a?(String) ? arg_def[:name].to_sym : arg_def[:name]
        next unless params.key?(param_key)

        value = params[param_key]
        next if value.nil?

        if arg_def[:variadic]
          # Variadic argument - expand array
          array = Type.validate(value, :array, arg_def)
          array.each { |v| args << format_arg(v, arg_def) }
        else
          args << format_arg(value, arg_def)
        end
      end

      # Add post_options (options that come before the "last" argument)
      (command[:post_options] || []).each do |opt_def|
        # Convert name to symbol for params lookup
        param_key = opt_def[:name].is_a?(String) ? opt_def[:name].to_sym : opt_def[:name]
        next unless params.key?(param_key)
        next if params[param_key].nil?

        formatted_opt = format_option(opt_def, params[param_key])
        Array(formatted_opt).each { |opt| args << opt unless opt.nil? || opt.empty? }
      end

      # Add the "last" positioned argument (typically output file)
      if last_arg
        param_key = last_arg[:name].is_a?(String) ? last_arg[:name].to_sym : last_arg[:name]
        if params.key?(param_key) && !params[param_key].nil?
          if last_arg[:variadic]
            array = Type.validate(params[param_key], :array, last_arg)
            array.each { |v| args << format_arg(v, last_arg) }
          else
            args << format_arg(params[param_key], last_arg)
          end
        end
      end

      args
    end

    # Format a positional argument
    def format_arg(value, arg_def)
      # Validate type
      Type.validate(value, arg_def[:type] || :string, arg_def)

      # Apply platform-specific path formatting
      if arg_def[:type] == :file
        shell_class = Shell.class_for(@shell)
        shell_class.new.format_path(value.to_s)
      else
        value.to_s
      end
    end

    # Format an option
    def format_option(opt_def, value)
      # Validate type
      Type.validate(value, opt_def[:type] || :string, opt_def)

      # Handle boolean types - just return the CLI flag (no value)
      type_val = opt_def[:type]
      if type_val == :boolean || type_val == TrueClass || type_val == "boolean"
        return nil if value.nil? || value == false
        return opt_def[:cli] || ""
      end

      cli = opt_def[:cli] || ""
      format = opt_def[:format] || "double_dash_equals"
      format_sym = format.is_a?(String) ? format.to_sym : format
      separator = opt_def[:separator] || "="

      # Convert value to string (handle symbols)
      value_str = value.is_a?(Symbol) ? value.to_s : value.to_s

      # Handle array values with separator
      if value.is_a?(Array) && opt_def[:separator]
        joined = value.join(opt_def[:separator])
        case format_sym
        when :double_dash_equals
          "#{cli}#{joined}"
        when :double_dash_space, :single_dash_space
          [cli, joined]  # Return array for space-separated
        when :single_dash_equals
          "#{cli}#{joined}"
        else
          "#{cli}#{joined}"
        end
      else
        case format_sym
        when :double_dash_equals
          "#{cli}#{value_str}"
        when :double_dash_space, :single_dash_space
          [cli, value_str]  # Return array for space-separated
        when :single_dash_equals
          "#{cli}#{value_str}"
        when :slash_colon
          "#{cli}:#{value_str}"
        when :slash_space
          "#{cli} #{value_str}"
        else
          "#{cli}#{value_str}"
        end
      end
    end

    # Format a flag
    def format_flag(flag_def, value)
      return nil if value.nil? || value == false

      flag_def[:cli] || ""
    end

    # Build environment variables for command
    def build_env_vars(command, params)
      env_vars = {}

      (command[:env_vars] || []).each do |ev|
        # Check platform restriction
        platforms = ev[:platforms] || ev[:platform]
        next if platforms && !platforms.include?(@platform)

        # Get value - use ev[:value] if provided, or extract from params
        value = if ev.key?(:value)
                  ev[:value]
                elsif ev[:from]
                  params[ev[:from].to_sym]
                end

        # Set the environment variable if value is defined (including empty string)
        env_vars[ev[:name]] = value.to_s unless value.nil?
      end

      env_vars
    end
  end
end
