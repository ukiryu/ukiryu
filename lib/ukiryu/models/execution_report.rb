# frozen_string_literal: true

require 'lutaml/model'
require 'socket'
require 'etc'

module Ukiryu
  module Models
    # Metrics for a single stage of execution
    class StageMetrics < Lutaml::Model::Serializable
      attribute :name, :string, default: ''
      attribute :duration, :float, default: 0.0
      attribute :formatted_duration, :string, default: ''
      attribute :memory_before, :integer, default: 0
      attribute :memory_after, :integer, default: 0
      attribute :memory_delta, :integer, default: 0
      attribute :success, :boolean, default: true
      attribute :error, :string, default: ''

      yaml do
        map_element 'name', to: :name
        map_element 'duration', to: :duration
        map_element 'formatted_duration', to: :formatted_duration
        map_element 'memory_before', to: :memory_before
        map_element 'memory_after', to: :memory_after
        map_element 'memory_delta', to: :memory_delta
        map_element 'success', to: :success
        map_element 'error', to: :error
      end

      # Record the end of a stage
      def finish!(success: true, error: nil)
        @duration = Time.now - @start_time if @start_time
        @formatted_duration = format_duration(@duration)
        @success = success
        @error = error if error

        # Record memory after
        @memory_after = get_memory_usage
        @memory_delta = @memory_after - @memory_before
      end

      # Start recording this stage
      def start!
        @start_time = Time.now
        @memory_before = get_memory_usage
        self
      end

      private

      def get_memory_usage
        # Get RSS memory usage in KB
        `ps -o rss= -p #{Process.pid}`.to_i
      rescue StandardError
        0
      end

      def format_duration(seconds)
        return '0ms' if seconds.nil? || seconds.zero?
        return "#{(seconds * 1000).round(2)}ms" if seconds < 1

        "#{seconds.round(2)}s"
      end
    end

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

      yaml do
        map_element 'hostname', to: :hostname
        map_element 'platform', to: :platform
        map_element 'os_version', to: :os_version
        map_element 'shell', to: :shell
        map_element 'shell_override', to: :shell_override
        map_element 'shell_version', to: :shell_version
        map_element 'ruby_version', to: :ruby_version
        map_element 'ukiryu_version', to: :ukiryu_version
        map_element 'cpu_count', to: :cpu_count
        map_element 'total_memory', to: :total_memory
        map_element 'working_directory', to: :working_directory
      end

      # Collect all environment information
      #
      # @return [RunEnvironment] the environment info
      def self.collect
        require_relative '../runtime'
        require_relative '../config'
        require_relative '../shell'

        runtime = Runtime.instance
        begin
          Shell.detect
        rescue Ukiryu::UnknownShellError
          'unknown'
        end

        # Determine if shell was overridden
        shell_override = !Config.shell.nil?
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

    # Execution report containing metrics and timing information
    #
    # Provides detailed metrics about the execution process including:
    # - Stage timings (tool resolution, command building, execution)
    # - Memory usage
    # - Run environment information
    class ExecutionReport < Lutaml::Model::Serializable
      attribute :tool_resolution, StageMetrics
      attribute :command_building, StageMetrics
      attribute :execution, StageMetrics
      attribute :response_building, StageMetrics
      attribute :total_duration, :float, default: 0.0
      attribute :formatted_total_duration, :string, default: ''
      attribute :run_environment, RunEnvironment
      attribute :timestamp, :string, default: ''

      yaml do
        map_element 'tool_resolution', to: :tool_resolution
        map_element 'command_building', to: :command_building
        map_element 'execution', to: :execution
        map_element 'response_building', to: :response_building
        map_element 'total_duration', to: :total_duration
        map_element 'formatted_total_duration', to: :formatted_total_duration
        map_element 'run_environment', to: :run_environment
        map_element 'timestamp', to: :timestamp
      end

      json do
        map 'tool_resolution', to: :tool_resolution
        map 'command_building', to: :command_building
        map 'execution', to: :execution
        map 'response_building', to: :response_building
        map 'total_duration', to: :total_duration
        map 'formatted_total_duration', to: :formatted_total_duration
        map 'run_environment', to: :run_environment
        map 'timestamp', to: :timestamp
      end

      # Calculate total duration from all stages
      def calculate_total
        stages = [tool_resolution, command_building, execution, response_building]
        total = stages.compact.map(&:duration).sum
        @total_duration = total
        @formatted_total_duration = format_duration(total)
      end

      # Get all stages in order
      #
      # @return [Array<StageMetrics>] all stages
      def all_stages
        [tool_resolution, command_building, execution, response_building].compact
      end

      private

      def format_duration(seconds)
        return '0ms' if seconds.zero?
        return "#{(seconds * 1000).round(2)}ms" if seconds < 1

        "#{seconds.round(2)}s"
      end
    end
  end
end
