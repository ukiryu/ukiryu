# frozen_string_literal: true

module Ukiryu
  # Environment represents a set of environment variables for command execution.
  #
  # This class provides an immutable, functional-style interface for managing
  # environment variables. All write operations return a new Environment instance,
  # preserving the original.
  #
  # == Usage
  #
  # Create from various sources:
  #   env = Environment.system              # Empty environment
  #   env = Environment.from_env            # Inherit current process ENV
  #   env = Environment.new({ 'PATH' => '...' })  # From hash
  #
  # Manipulate immutably:
  #   new_env = env.set('VAR', 'value')
  #   new_env = env.delete('VAR')
  #   new_env = env.merge(other_env)
  #
  # PATH utilities (Unix-style colon separator):
  #   new_env = env.prepend_path('/new/bin')
  #   new_env = env.append_path('/new/bin')
  #   new_env = env.remove_path('/old/bin')
  #
  # Convert to hash for execution:
  #   hash = env.to_h
  #
  class Environment
    SEPARATOR = ':'

    # Create a new Environment instance
    #
    # @param env [Hash{String => String}] initial environment variables
    # @return [Environment] new environment instance
    def initialize(env = {})
      @env = env.dup.freeze
    end

    # Create an empty environment (no inherited variables)
    #
    # @return [Environment] empty environment
    def self.system
      new({})
    end

    # Create an environment that inherits from the current process ENV
    #
    # @return [Environment] environment copied from ENV
    def self.from_env
      # On Windows, ENV.to_h might not include PATH due to case sensitivity
      # issues. Ensure PATH is always included by explicitly checking for it.
      env_hash = ENV.to_h.dup

      # Ensure PATH is included (check case-insensitively on Windows)
      unless env_hash.key?('PATH')
        # Look for Path, path, etc. on Windows
        ENV.each_key do |key|
          if key.upcase == 'PATH'
            env_hash['PATH'] = ENV[key]
            break
          end
        end
      end

      new(env_hash)
    end

    # Get a value from the environment
    #
    # @param key [String, Symbol] the variable name
    # @return [String, nil] the value or nil if not set
    def [](key)
      @env[key.to_s]
    end

    # Check if a key exists in the environment
    #
    # @param key [String, Symbol] the variable name
    # @return [Boolean] true if the key exists
    def key?(key)
      @env.key?(key.to_s)
    end

    # Get all keys in the environment
    #
    # @return [Array<String>] array of variable names
    def keys
      @env.keys
    end

    # Convert to a plain hash (for execution)
    #
    # @return [Hash{String => String}] mutable copy of environment
    def to_h
      @env.dup
    end

    # Set or update a variable
    #
    # @param key [String, Symbol] the variable name
    # @param value [String] the value to set
    # @return [Environment] new environment with the variable set
    def set(key, value)
      self.class.new(@env.merge(key.to_s => value.to_s))
    end

    # Delete a variable
    #
    # @param key [String, Symbol] the variable name
    # @return [Environment] new environment without the variable
    def delete(key)
      new_env = @env.dup
      new_env.delete(key.to_s)
      self.class.new(new_env)
    end

    # Merge another environment or hash
    #
    # @param other [Environment, Hash] the environment or hash to merge
    # @return [Environment] new environment with merged values
    def merge(other)
      other_hash = other.is_a?(Environment) ? other.to_h : other
      self.class.new(@env.merge(other_hash))
    end

    # Prepend one or more directories to PATH
    #
    # Handles Unix-style colon-separated PATH. Directories are added to the
    # beginning of PATH, so they are searched first.
    #
    # @param additions [String, Array<String>] directory or directories to prepend
    # @return [Environment] new environment with modified PATH
    def prepend_path(additions)
      additions_arr = Array(additions)
      additions_str = additions_arr.join(SEPARATOR)
      existing = @env['PATH'] || ''
      new_path = existing.empty? ? additions_str : "#{additions_str}#{SEPARATOR}#{existing}"
      self.class.new(@env.merge('PATH' => new_path))
    end

    # Append one or more directories to PATH
    #
    # Handles Unix-style colon-separated PATH. Directories are added to the
    # end of PATH, so existing directories take precedence.
    #
    # @param additions [String, Array<String>] directory or directories to append
    # @return [Environment] new environment with modified PATH
    def append_path(additions)
      additions_arr = Array(additions)
      additions_str = additions_arr.join(SEPARATOR)
      existing = @env['PATH'] || ''
      new_path = existing.empty? ? additions_str : "#{existing}#{SEPARATOR}#{additions_str}"
      self.class.new(@env.merge('PATH' => new_path))
    end

    # Remove a directory from PATH
    #
    # Removes all occurrences of the specified directory from PATH.
    # Uses prefix matching to handle cases like removing '/opt' which
    # should also remove '/opt/bin', '/opt/local/bin', etc.
    #
    # @param directory [String] directory prefix to remove
    # @return [Environment] new environment with modified PATH
    def remove_path(directory)
      existing = @env['PATH'] || ''
      # Remove trailing slash for consistent comparison
      dir = directory.end_with?('/') ? directory[0..-2] : directory
      path_parts = existing.split(SEPARATOR).reject do |part|
        part == dir || part.start_with?("#{dir}/")
      end
      new_path = path_parts.join(SEPARATOR)
      self.class.new(@env.merge('PATH' => new_path))
    end

    # Check if PATH contains a directory
    #
    # @param directory [String] directory to check
    # @return [Boolean] true if directory is in PATH
    def path_contains?(directory)
      return false unless @env['PATH']

      @env['PATH'].split(SEPARATOR).include?(directory)
    end

    # Get the PATH as an array
    #
    # @return [Array<String>] array of directories in PATH
    def path_array
      (@env['PATH'] || '').split(SEPARATOR)
    end

    # Equality check
    #
    # @param other [Object] object to compare
    # @return [Boolean] true if equal
    def ==(other)
      return false unless other.is_a?(Environment)

      @env == other.instance_variable_get(:@env)
    end

    # String representation for debugging
    #
    # @return [String] summary of environment
    def inspect
      "#<Ukiryu::Environment keys=#{@env.keys.size}>"
    end

    # Hash representation for hashing (e.g., use in Hash as key)
    #
    # @return [Integer] hash value
    def hash
      @env.hash
    end
  end
end
