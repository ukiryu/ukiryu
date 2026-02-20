# frozen_string_literal: true

require 'yaml'
require 'git'
require 'fileutils'
require 'pathname'
require_relative 'utils'
require_relative 'models/interface'
require_relative 'models/implementation_index'
require_relative 'models/implementation_version'

module Ukiryu
  # Represents a collection of tool definitions
  #
  # A Register is a directory containing tool profiles in YAML format.
  # It handles:
  # - Discovery (env variable, dev path, user clone)
  # - Auto-cloning from GitHub
  # - Loading tool definitions
  # - Validation
  #
  # @example Getting the default register
  #   register = Ukiryu::Register.default
  #   register.tool_names  # => ['ghostscript', 'imagemagick', ...]
  #
  # @example Using a specific path
  #   register = Ukiryu::Register.at('/path/to/register')
  #
  # @api private - This is an internal class. Developers use Tool.get()
  #
  class Register
    # GitHub repository URL for the register
    REMOTE_URL = 'https://github.com/ukiryu/register'

    # Default local directory for user clone
    DEFAULT_USER_PATH = '~/.ukiryu/register'

    # @return [String] the filesystem path to the register
    attr_reader :path

    # @return [Symbol] how the register was discovered (:env, :dev, :user, :manual)
    attr_reader :source

    # Error raised when register operations fail
    class Error < StandardError; end

    # Error raised when register cannot be found or cloned
    class NotFoundError < Error; end

    # Error raised when cloning fails
    class CloneError < Error; end

    class << self
      # Get the default register instance
      #
      # Auto-discovers the register using this priority:
      # 1. UKIRYU_REGISTER environment variable
      # 2. Development register (sibling to gem source)
      # 3. User clone at ~/.ukiryu/register (auto-clones if needed)
      #
      # @return [Register] the default register instance
      def default
        @default ||= discover
      end

      # Create a register at a specific path
      #
      # @param path [String] the filesystem path
      # @return [Register] a new register instance
      def at(path)
        new(File.expand_path(path), source: :manual)
      end

      # Reset the cached default register (mainly for testing)
      def reset_default
        @default = nil
      end

      # Check if a default register exists (without auto-cloning)
      #
      # @return [Boolean] true if a register can be found
      def exists?
        path = resolve_path_without_clone
        path && Dir.exist?(path) && valid_structure?(path)
      end

      # ===== BACKWARD COMPATIBILITY =====
      # These class methods delegate to the default instance for backward compatibility

      # @deprecated Use Register.default.path instead
      def default_register_path
        default.path
      end

      # @deprecated Use ENV['UKIRYU_REGISTER'] = path; Register.reset_default instead
      def default_register_path=(path)
        ENV['UKIRYU_REGISTER'] = path
        reset_default
      end

      # @deprecated Use Register.reset_default instead
      def reset_version_cache
        reset_default
      end

      # @deprecated Use Register.default.tool_names instead
      def tools
        default.tool_names
      end

      # @deprecated Use Register.default.list_versions instead
      def list_versions(name, register_path: nil)
        register = register_path ? at(register_path) : default
        register.list_versions(name)
      end

      # @deprecated Use Register.default.load_tool_yaml instead
      def load_tool_yaml(name, options = {})
        register = options[:register_path] ? at(options[:register_path]) : default
        register.load_tool_yaml(name, version: options[:version])
      end

      # @deprecated Use Register.default.load_implementation_index instead
      def load_implementation_index(tool_name, options = {})
        register = options[:register_path] ? at(options[:register_path]) : default
        register.load_implementation_index(tool_name)
      end

      # @deprecated Use Register.default.load_implementation_version instead
      def load_implementation_version(tool_name, implementation_name, file_path, options = {})
        register = options[:register_path] ? at(options[:register_path]) : default
        register.load_implementation_version(tool_name, implementation_name, file_path)
      end

      # @deprecated Use Register.default.load_interface instead
      def load_interface(path, options = {})
        register = options[:register_path] ? at(options[:register_path]) : default
        register.load_interface(path)
      end

      # @deprecated Use Register.default methods instead
      def load_tool_metadata(name, options = {})
        # First try exact name match
        yaml_content = load_tool_yaml(name, options)
        if yaml_content
          hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
          if hash
            return ToolMetadata.from_hash(hash, tool_name: name.to_s,
                                                register_path: options[:register_path] || default.path)
          end
        end

        # If not found, try interface-based discovery using ToolIndex
        index = Ukiryu::ToolIndex.instance

        # Try exact interface name first
        result = index.find_by_interface(name.to_sym)
        return result if result

        # Try interface name with common version suffix
        name_str = name.to_s
        [:"#{name_str}/1.0", :"#{name_str}/1", :"v#{name_str}/1.0"].each do |versioned_interface|
          result = index.find_by_interface(versioned_interface)
          return result if result
        end

        nil
      end

      # @deprecated Use Register.default.validate methods instead
      def validate_tool(name, options = {})
        yaml_content = load_tool_yaml(name, options)
        return Models::ValidationResult.not_found(name.to_s) unless yaml_content

        profile = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
        return Models::ValidationResult.invalid(name.to_s, ['Failed to parse YAML']) unless profile

        errors = Ukiryu::SchemaValidator.validate_profile(profile, options)
        if errors.empty?
          Models::ValidationResult.valid(name.to_s)
        else
          Models::ValidationResult.invalid(name.to_s, errors)
        end
      end

      # @deprecated Use Register.default.validate methods instead
      def validate_all_tools(options = {})
        tools.map do |tool_name|
          validate_tool(tool_name, options)
        end
      end

      private

      # Discover and create the default register
      #
      # @return [Register] the discovered register
      def discover
        path, source = discover_path
        raise NotFoundError, 'No register found and auto-clone failed' unless path

        register = new(path, source: source)
        register.ensure_exists!
        register
      end

      # Discover the register path without auto-cloning
      #
      # @return [Array<String, Symbol>, nil] path and source, or nil
      def discover_path
        # 1. Check UKIRYU_REGISTER environment variable
        env_path = ENV['UKIRYU_REGISTER']
        return [env_path, :env] if env_path && Dir.exist?(env_path)

        # 2. Check development register (sibling to gem source)
        dev_path = calculate_dev_path
        return [dev_path.to_s, :dev] if dev_path&.exist?

        # 3. Use user clone (may need to be created)
        user_path = File.expand_path(DEFAULT_USER_PATH)
        return [user_path, :user] if Dir.exist?(user_path) && valid_structure?(user_path)

        # 4. Return user path for auto-clone
        [user_path, :user]
      end

      # Resolve path without triggering auto-clone
      #
      # @return [String, nil] the path or nil
      def resolve_path_without_clone
        env_path = ENV['UKIRYU_REGISTER']
        return env_path if env_path && Dir.exist?(env_path)

        dev_path = calculate_dev_path
        return dev_path.to_s if dev_path&.exist?

        user_path = File.expand_path(DEFAULT_USER_PATH)
        return user_path if Dir.exist?(user_path) && valid_structure?(user_path)

        nil
      end

      # Calculate the development register path
      #
      # @return [Pathname, nil] the dev path or nil
      def calculate_dev_path
        this_file = Pathname.new(__FILE__).realpath
        # lib/ukiryu/register.rb -> ../../../register
        this_file.parent.parent.parent.join('register')
      rescue StandardError
        nil
      end

      # Check if a path has valid register structure
      #
      # @param path [String] the path to check
      # @return [Boolean] true if valid
      def valid_structure?(path)
        return false unless path && Dir.exist?(path)

        tools_dir = File.join(path, 'tools')
        return false unless Dir.exist?(tools_dir)

        # Must have at least one tool definition
        Dir.glob(File.join(tools_dir, '*', '*.yaml')).any?
      end
    end

    # Initialize a new Register
    #
    # @param path [String] the filesystem path
    # @param source [Symbol] how the register was discovered
    def initialize(path, source: :unknown)
      @path = path
      @source = source
      @version_cache = {}
    end

    # Check if the register exists on disk
    #
    # @return [Boolean] true if the register directory exists
    def exists?
      Dir.exist?(path)
    end

    # Check if the register has valid structure
    #
    # @return [Boolean] true if valid
    def valid?
      self.class.send(:valid_structure?, path)
    end

    # Ensure the register exists, cloning if necessary
    #
    # @raise [CloneError] if cloning fails
    def ensure_exists!
      return if exists? && valid?

      clone!
    end

    # Clone the register from GitHub
    #
    # @raise [CloneError] if cloning fails
    def clone!
      raise CloneError, "Register already exists at #{path}" if exists? && valid?

      parent_dir = File.dirname(path)
      FileUtils.mkdir_p(parent_dir) unless Dir.exist?(parent_dir)

      print "Cloning register from #{REMOTE_URL}..." if $stdout.tty?

      begin
        Git.clone(REMOTE_URL, path, quiet: true)
      rescue Git::Error => e
        FileUtils.rm_rf(path) if Dir.exist?(path)
        raise CloneError, clone_error_message(e)
      end

      puts 'done' if $stdout.tty?

      raise CloneError, 'Register clone validation failed' unless valid?
    end

    # Update the register (git pull)
    #
    # @raise [Error] if update fails
    def update!
      return clone! unless exists?

      begin
        null_dev = RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL' : '/dev/null'
        old_redirect = ENV['GIT_REDIRECT_STDERR']
        ENV['GIT_REDIRECT_STDERR'] = null_dev

        print 'Updating register...' if $stdout.tty?
        git = Git.open(path)
        git.pull
        puts 'done' if $stdout.tty?
      ensure
        if old_redirect
          ENV['GIT_REDIRECT_STDERR'] = old_redirect
        else
          ENV.delete('GIT_REDIRECT_STDERR')
        end
      end
    rescue Git::Error => e
      raise Error, "Failed to update register: #{e.message}"
    end

    # Get list of all tool names in this register
    #
    # @return [Array<String>] sorted list of tool names
    def tool_names
      tools_dir = File.join(path, 'tools')
      return [] unless Dir.exist?(tools_dir)

      Dir.glob(File.join(tools_dir, '*', 'index.yaml')).map do |index_file|
        File.basename(File.dirname(index_file))
      end.sort
    end

    # Check if a tool exists in this register
    #
    # @param name [String, Symbol] the tool name
    # @return [Boolean] true if the tool exists
    def tool?(name)
      index_file = File.join(path, 'tools', name.to_s, 'index.yaml')
      File.exist?(index_file)
    end

    # Load the implementation index for a tool
    #
    # @param tool_name [String, Symbol] the tool name
    # @return [Models::ImplementationIndex, nil] the index or nil
    def load_implementation_index(tool_name)
      file = File.join(path, 'tools', tool_name.to_s, 'index.yaml')
      return nil unless File.exist?(file)

      yaml_content = File.read(file)
      hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
      return nil unless hash

      Models::ImplementationIndex.from_hash(symbolize_keys(hash))
    end

    # Load a specific implementation version
    #
    # @param tool_name [String, Symbol] the tool name
    # @param impl_name [String, Symbol] the implementation name
    # @param file_path [String] the file path relative to implementation directory
    # @return [Models::ImplementationVersion, nil] the version or nil
    def load_implementation_version(tool_name, impl_name, file_path)
      file = File.join(path, 'tools', tool_name.to_s, impl_name.to_s, file_path)
      return nil unless File.exist?(file)

      yaml_content = File.read(file)
      hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
      return nil unless hash

      Models::ImplementationVersion.from_hash(symbolize_keys(hash))
    end

    # Load raw YAML content for a tool
    #
    # @param name [String, Symbol] the tool name
    # @param version [String, nil] specific version (optional)
    # @return [String, nil] the YAML content or nil
    def load_tool_yaml(name, version: nil)
      name_str = name.to_s

      # Try version-specific file first
      if version
        file = File.join(path, 'tools', name_str, "#{version}.yaml")
        return File.read(file) if File.exist?(file)
      end

      # Get versions from index
      versions = list_versions(name_str)
      return nil if versions.empty?

      # Return specific version or latest
      if version
        version_file = versions.keys.find { |f| File.basename(f, '.yaml') == version }
        return version_file ? File.read(version_file) : nil
      end

      File.read(versions.keys.last)
    end

    # Load an interface definition
    #
    # @param interface_path [String] the interface path (e.g., "gzip/1.0")
    # @return [Models::Interface, nil] the interface or nil
    def load_interface(interface_path)
      file = File.join(path, 'interfaces', "#{interface_path}.yaml")
      return nil unless File.exist?(file)

      yaml_content = File.read(file)
      hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
      return nil unless hash

      Models::Interface.from_hash(symbolize_keys(hash))
    end

    # List available versions for a tool
    #
    # @param tool_name [String, Symbol] the tool name
    # @return [Hash] mapping of full file path to version string
    def list_versions(tool_name)
      index = load_implementation_index(tool_name)
      return {} unless index

      versions = {}
      index.implementations.each do |impl|
        impl_name = impl[:name] || impl['name']
        impl_versions = impl[:versions] || impl['versions']
        next unless impl_versions

        impl_versions.each do |version_spec|
          equals = version_spec[:equals] || version_spec['equals']
          file = version_spec[:file] || version_spec['file']
          next unless equals && file

          full_path = File.join(path, 'tools', tool_name.to_s, impl_name.to_s, file)
          versions[full_path] = equals
        end
      end

      versions
    end

    # Get information about this register
    #
    # @return [Hash] register information
    def info
      {
        path: path,
        source: source,
        exists: exists?,
        valid: valid?,
        tools_count: tool_names.count,
        git_info: git_info
      }
    end

    private

    # Get git information for this register
    #
    # @return [Hash, nil] git info or nil
    def git_info
      git_dir = File.join(path, '.git')
      return nil unless Dir.exist?(git_dir)

      null_dev = RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL' : '/dev/null'
      old_redirect = ENV['GIT_REDIRECT_STDERR']
      ENV['GIT_REDIRECT_STDERR'] = null_dev

      git = Git.open(path)
      log = git.log(1).to_a

      {
        branch: git.current_branch,
        commit: log.first&.sha&.[](0..7),
        last_update: log.first&.date && Time.at(log.first.date.to_i)
      }
    rescue Git::Error, IOError, Errno::ENOENT
      nil
    ensure
      if old_redirect
        ENV['GIT_REDIRECT_STDERR'] = old_redirect
      else
        ENV.delete('GIT_REDIRECT_STDERR')
      end
    end

    # Generate a helpful error message for clone failures
    #
    # @param error [Git::Error] the error
    # @return [String] the error message
    def clone_error_message(error)
      msg = error.message.to_s

      if msg.include?('cannot find') || msg.include?('not found') || msg.include?('path specified')
        <<~ERROR
          Failed to clone register: #{msg}

          This error usually means git is not in PATH or the target directory is not accessible.

          To fix this:
            1. Verify git is installed and in PATH: git --version
            2. On Windows, ensure Git for Windows is installed from https://git-scm.com
            3. Or set UKIRYU_REGISTER to use a local register path

          Example (Windows):
            set UKIRYU_REGISTER=C:\\path\\to\\register

          Example (Unix):
            export UKIRYU_REGISTER=/path/to/register
        ERROR
      else
        <<~ERROR
          Failed to clone register from #{REMOTE_URL}: #{msg}

          To fix this:
            1. Check your internet connection
            2. Verify git is installed: git --version
            3. Manually clone: git clone #{REMOTE_URL} #{path}
            4. Or set UKIRYU_REGISTER to use a local register path

          Example:
            export UKIRYU_REGISTER=/path/to/register
        ERROR
      end
    end

    # Recursively symbolize hash keys
    #
    # @param hash [Hash] the hash to symbolize
    # @return [Hash] hash with symbolized keys
    def symbolize_keys(hash)
      Utils.symbolize_keys(hash)
    end
  end
end
