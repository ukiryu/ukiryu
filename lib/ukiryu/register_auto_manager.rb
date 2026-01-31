# frozen_string_literal: true

require 'git'
require 'fileutils'
require 'pathname'

module Ukiryu
  # Manages automatic register cloning and updates
  #
  # This class handles:
  # - Auto-cloning the register repository to ~/.ukiryu/register
  # - Detecting development mode (local submodule)
  # - Validating register integrity
  # - Providing register path to the Register class
  #
  # @api private
  class RegisterAutoManager
    # GitHub repository URL for the register
    REGISTER_URL = 'https://github.com/ukiryu/register'

    # Default local directory for the register
    DEFAULT_DIR = '~/.ukiryu/register'

    class << self
      # Get the register path, ensuring it exists
      #
      # Checks in order:
      # 1. Environment variable UKIRYU_REGISTER
      # 2. Development register (../../register relative to gem lib)
      # 3. User's local clone (~/.ukiryu/register)
      #
      # @return [String, nil] the register path, or nil if unavailable
      def register_path
        # Debug logging
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn '[UKIRYU DEBUG RegisterAutoManager] Checking register_path...'
          warn "[UKIRYU DEBUG RegisterAutoManager] ENV['UKIRYU_REGISTER'] = #{ENV['UKIRYU_REGISTER'].inspect}"
        end

        # 1. Environment variable has highest priority
        env_path = ENV['UKIRYU_REGISTER']
        if env_path && Dir.exist?(env_path)
          warn "[UKIRU DEBUG RegisterAutoManager] Using ENV register: #{env_path}" if ENV['UKIRYU_DEBUG_EXECUTABLE']
          return env_path
        end

        warn "[UKIRYU DEBUG RegisterAutoManager] ENV path doesn't exist or not set" if ENV['UKIRYU_DEBUG_EXECUTABLE']

        # 2. Check development register (../../../register relative to this file)
        # Use Pathname for reliable path calculation
        this_file = Pathname.new(__FILE__).realpath
        dev_path = this_file.parent.parent.parent.parent + 'register'
        if dev_path.exist?
          warn "[UKIRYU DEBUG RegisterAutoManager] Using DEV register: #{dev_path}" if ENV['UKIRYU_DEBUG_EXECUTABLE']
          return dev_path.to_s
        end

        warn "[UKIRYU DEBUG RegisterAutoManager] DEV register doesn't exist" if ENV['UKIRYU_DEBUG_EXECUTABLE']

        # 3. Use user's local clone, create if needed
        ensure_user_clone
      end

      # Check if the register exists and is valid
      #
      # @return [Boolean] true if register exists and is valid
      def register_exists?
        path = resolve_register_path
        return false unless path

        Dir.exist?(path) && validate_register_integrity(path)
      end

      # Update or re-clone the register
      #
      # @param force [Boolean] if true, re-clone even if register exists
      # @return [Boolean] true if successful
      # @raise [RegisterError] if update fails
      def update_register(force: false)
        if force
          force_reclone
        else
          update_existing_clone
        end
        true
      rescue Git::GitExecuteError => e
        raise RegisterError, "Failed to update register: #{e.message}"
      rescue StandardError => e
        raise RegisterError, "Register update failed: #{e.message}"
      end

      # Get register information
      #
      # @return [Hash] register information
      def register_info
        path = resolve_register_path
        return { status: :not_found } unless path

        return { status: :not_cloned, path: expand_path(DEFAULT_DIR) } unless Dir.exist?(path)

        return { status: :invalid, path: path } unless validate_register_integrity(path)

        info = {
          status: :ok,
          path: path,
          source: detect_source(path)
        }

        # Add git info if available
        git_dir = File.join(path, '.git')
        if Dir.exist?(git_dir)
          begin
            # Suppress stderr from git commands using GIT_REDIRECT_STDERR
            # This prevents "fatal: not a git repository" errors from polluting output
            # Redirect stderr to /dev/null at the git subprocess level
            null_dev = RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL' : '/dev/null'
            old_git_redirect = ENV['GIT_REDIRECT_STDERR']
            ENV['GIT_REDIRECT_STDERR'] = null_dev

            g = Git.open(path)
            info[:branch] = g.current_branch
            log = g.log(1).to_a
            info[:commit] = log.first.sha[0..7]
            info[:last_update] = Time.at(log.first.date.to_i)

            # Restore original GIT_REDIRECT_STDERR
            if old_git_redirect
              ENV['GIT_REDIRECT_STDERR'] = old_git_redirect
            else
              ENV.delete('GIT_REDIRECT_STDERR')
            end
          rescue Git::GitExecuteError, IOError, Errno::ENOENT
            # Git info not available, but register is valid
            # Ensure GIT_REDIRECT_STDERR is restored
            if old_git_redirect
              ENV['GIT_REDIRECT_STDERR'] = old_git_redirect
            else
              ENV.delete('GIT_REDIRECT_STDERR')
            end
          end
        end

        # Count available tools
        tools_dir = File.join(path, 'tools')
        if Dir.exist?(tools_dir)
          info[:tools_count] = Dir.glob(File.join(tools_dir, '*')).select do |d|
            File.directory?(d)
          end.count
        end

        info
      end

      private

      # Ensure the user's local clone exists
      #
      # @return [String, nil] the register path, or nil if unavailable
      def ensure_user_clone
        expanded_path = expand_path(DEFAULT_DIR)

        # If already exists and valid, return it
        if Dir.exist?(expanded_path)
          return expanded_path if validate_register_integrity(expanded_path)

          # Exists but invalid, re-clone
          force_reclone

          return expanded_path
        end

        # Doesn't exist, clone it
        clone_register(expanded_path)
        expanded_path
      rescue RegisterError
        # Re-raise with context
        raise
      rescue StandardError => e
        raise RegisterError, "Failed to setup register at #{expanded_path}: #{e.message}"
      end

      # Clone the register repository
      #
      # @param target_path [String] where to clone
      # @raise [RegisterError] if clone fails
      def clone_register(target_path)
        parent_dir = File.dirname(target_path)

        # Create parent directory if needed
        FileUtils.mkdir_p(parent_dir) unless Dir.exist?(parent_dir)

        # Check if git is available
        unless git_available?
          raise RegisterError, <<~ERROR
            Git is required but not found in PATH.

            To fix this:
              1. Install git from https://git-scm.com
              2. Or set UKIRYU_REGISTER to use a local register path

            Example:
              export UKIRYU_REGISTER=/path/to/register
          ERROR
        end

        # Perform the clone
        print "Cloning register from #{REGISTER_URL}..." if $stdout.tty?
        Git.clone(REGISTER_URL, target_path, quiet: true)
        puts 'done' if $stdout.tty?

        # Validate the clone
        unless validate_register_integrity(target_path)
          FileUtils.rm_rf(target_path)
          raise RegisterError, 'Register clone validation failed. Please try again or set UKIRYU_REGISTER.'
        end
      rescue Git::GitExecuteError => e
        raise RegisterError, <<~ERROR
          Failed to clone register from #{REGISTER_URL}: #{e.message}

          To fix this:
            1. Check your internet connection
            2. Manually clone: git clone #{REGISTER_URL} #{target_path}
            3. Or set UKIRYU_REGISTER to use a local register path

          Example:
            export UKIRYU_REGISTER=/path/to/register
        ERROR
      end

      # Update existing register clone
      #
      # @raise [RegisterError] if update fails
      def update_existing_clone
        path = expand_path(DEFAULT_DIR)

        return clone_register(path) unless Dir.exist?(path)

        begin
          print 'Updating register...' if $stdout.tty?
          # Suppress stderr from git commands using GIT_REDIRECT_STDERR
          null_dev = RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL' : '/dev/null'
          old_git_redirect = ENV['GIT_REDIRECT_STDERR']
          ENV['GIT_REDIRECT_STDERR'] = null_dev

          g = Git.open(path)
          g.pull
          puts 'done' if $stdout.tty?

          # Restore original GIT_REDIRECT_STDERR
          if old_git_redirect
            ENV['GIT_REDIRECT_STDERR'] = old_git_redirect
          else
            ENV.delete('GIT_REDIRECT_STDERR')
          end
        rescue Git::GitExecuteError => e
          # Ensure GIT_REDIRECT_STDERR is restored
          if defined?(old_git_redirect)
            if old_git_redirect
              ENV['GIT_REDIRECT_STDERR'] = old_git_redirect
            else
              ENV.delete('GIT_REDIRECT_STDERR')
            end
          end
          raise RegisterError, "Failed to update register: #{e.message}"
        end
      end

      # Force re-clone the register
      #
      # @raise [RegisterError] if re-clone fails
      def force_reclone
        path = expand_path(DEFAULT_DIR)
        FileUtils.rm_rf(path) if Dir.exist?(path)
        clone_register(path)
      end

      # Validate register integrity
      #
      # @param path [String] path to check
      # @return [Boolean] true if valid
      def validate_register_integrity(path)
        return false unless path

        # Check for tools/ directory
        tools_dir = File.join(path, 'tools')
        return false unless Dir.exist?(tools_dir)

        # Check for at least one tool definition
        # This confirms it's a valid register structure
        Dir.glob(File.join(tools_dir, '*', '*.yaml')).any?
      end

      # Resolve the register path without auto-creating
      #
      # @return [String, nil] current register path or nil
      def resolve_register_path
        # Check environment variable
        env_path = ENV['UKIRYU_REGISTER']
        return env_path if env_path && Dir.exist?(env_path)

        # Check development register (../../../register relative to this file)
        # Use Pathname for reliable path calculation
        this_file = Pathname.new(__FILE__).realpath
        dev_path = this_file.parent.parent.parent.parent + 'register'
        return dev_path.to_s if dev_path.exist?

        # Check user clone
        expanded = expand_path(DEFAULT_DIR)
        Dir.exist?(expanded) ? expanded : nil
      end

      # Detect the source of the register
      #
      # @param path [String] register path
      # @return [Symbol] :env or :user
      def detect_source(path)
        env_path = ENV['UKIRYU_REGISTER']
        return :env if env_path && path == File.expand_path(env_path)

        :user
      end

      # Check if git is available
      #
      # @return [Boolean] true if git binary is available
      def git_available?
        system('git --version > /dev/null 2>&1')
      end

      # Expand a path with ~ support
      #
      # @param path [String] path to expand
      # @return [String] expanded path
      def expand_path(path)
        File.expand_path(path)
      end
    end

    # Register-specific error
    class RegisterError < StandardError; end
  end
end
