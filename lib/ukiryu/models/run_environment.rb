# frozen_string_literal: true

require 'socket'
require 'etc'

module Ukiryu
  module Models

    # Run environment information
    class RunEnvironment < Lutaml::Model::Serializable
      attribute :hostname, :string, default: ''
      attribute :platform, :string, default: ''
      attribute :os_version, :string, default: ''
      attribute :shell, :string, default: ''
      attribute :shell_override, :boolean, default: false
      attribute :shell_version, :string, default: ''
      attribute :ruby_version, :string, default: ''
      attribute :ukiryu_version, :string, default: ''
      attribute :cpu_count, :integer, default: 0
      attribute :total_memory, :integer, default: 0
      attribute :working_directory, :string, default: ''

      key_value do
        map 'hostname', to: :hostname
        map 'platform', to: :platform
        map 'os_version', to: :os_version
        map 'shell', to: :shell
        map 'shell_override', to: :shell_override
        map 'shell_version', to: :shell_version
        map 'ruby_version', to: :ruby_version
        map 'ukiryu_version', to: :ukiryu_version
        map 'cpu_count', to: :cpu_count
        map 'total_memory', to: :total_memory
        map 'working_directory', to: :working_directory
      end

      # Collect all environment information
      #
      # @return [RunEnvironment] the environment info
      def self.collect
        runtime = ::Ukiryu::Runtime.instance
        begin
          ::Ukiryu::Shell.detect
        rescue ::Ukiryu::Errors::UnknownShellError
          'unknown'
        end

        # Determine if shell was overridden
        shell_override = !::Ukiryu::Config.shell.nil?
        actual_shell = runtime.shell.to_s

        new(
          hostname: Socket.gethostname,
          platform: RUBY_PLATFORM,
          os_version: os_version_string,
          shell: actual_shell,
          shell_override: shell_override,
          shell_version: detect_shell_version_for(actual_shell),
          ruby_version: RUBY_VERSION,
          ukiryu_version: Ukiryu::VERSION,
          cpu_count: Etc.nprocessors,
          total_memory: detect_total_memory,
          working_directory: Dir.pwd
        )
      end

      # Detect shell version for a specific shell
      #
      # @param shell_name [String] the shell name
      # @return [String] the shell version string
      def self.detect_shell_version_for(shell_name)
        return '' if shell_name == 'unknown' || shell_name.empty?

        shell_path = ENV['SHELL']
        return '' unless shell_path

        `#{shell_path} --version 2>&1`.strip
      rescue StandardError
        ''
      end

      # Get OS version string
      #
      # @return [String] the OS version
      def self.os_version_string
        # Try to get OS version from RbConfig
        RbConfig::CONFIG['host_os'] || RbConfig::CONFIG['target_os'] || RUBY_PLATFORM
      end

      # Detect total system memory
      #
      # @return [Integer] total memory in GB
      def self.detect_total_memory
        # Get total system memory in GB
        if RUBY_PLATFORM =~ /darwin/i
          # macOS
          `sysctl hw.memsize`.to_i / (1024**3)
        elsif RUBY_PLATFORM =~ /linux/i
          # Linux
          `grep MemTotal /proc/meminfo`.split[1].to_i / 1024
        else
          0
        end
      rescue StandardError
        0
      end

      private_class_method :detect_shell_version_for, :detect_total_memory, :os_version_string
    end

  end
end
