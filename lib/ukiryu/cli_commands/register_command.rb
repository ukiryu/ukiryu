# frozen_string_literal: true

module Ukiryu
  module CliCommands
    # Command to manage the register
    class RegisterCommand < BaseCommand
      # Run the register command
      #
      # @param subcommand [String, nil] the subcommand (info, update, etc.)
      # @param options [Hash] command options
      # @option options [Boolean] :force force re-clone
      # @option options [Boolean] :verbose show verbose output
      def run(subcommand = nil, options = {})
        case subcommand
        when 'info', nil
          show_info(options)
        when 'update'
          update_register(options)
        when 'path'
          show_path
        else
          error!("Unknown subcommand: #{subcommand}. Valid subcommands: info, update, path")
        end
      rescue Ukiryu::Register::Error => e
        error!("Register error: #{e.message}")
      end

      private

      # Show register information
      #
      # @param options [Hash] command options
      def show_info(_options = {})
        info = Ukiryu::Register.default.info

        say 'Register Information', :cyan
        say ''

        case determine_status(info)
        when :not_found
          say '  Status: Not configured', :red
          say ''
          say '  No register found. Run: ukiryu register update', :yellow
        when :invalid
          say '  Status: Invalid', :red
          say "  Path: #{info[:path]}", :dim
          say ''
          say '  Register is corrupted. Run: ukiryu register update --force', :yellow
        when :ok
          say '  Status: OK', :green
          say "  Path: #{info[:path]}", :dim
          say "  Source: #{format_source(info[:source])}", :dim

          say "  Tools available: #{info[:tools_count]}", :dim if info[:tools_count]

          if info[:git_info]
            say "  Branch: #{info[:git_info][:branch]}", :dim if info[:git_info][:branch]
            say "  Commit: #{info[:git_info][:commit]}", :dim if info[:git_info][:commit]
            if info[:git_info][:last_update]
              say "  Last updated: #{info[:git_info][:last_update].strftime('%Y-%m-%d %H:%M:%S')}",
                  :dim
            end
          end
        end

        say ''
        say 'Environment variable:', :cyan
        env_path = ENV['UKIRYU_REGISTER']
        if env_path
          say "  UKIRYU_REGISTER=#{env_path}", :dim
        else
          say '  UKIRYU_REGISTER (not set)', :dim
        end

        show_manual_setup_help unless info[:valid]
      end

      # Determine register status from info hash
      def determine_status(info)
        return :not_found unless info[:exists]
        return :invalid unless info[:valid]

        :ok
      end

      # Update the register
      #
      # @param options [Hash] command options
      def update_register(options = {})
        force = options[:force] || false

        if force
          say 'Force re-cloning register...', :yellow
          FileUtils.rm_rf(Ukiryu::Register.default.path) if Dir.exist?(Ukiryu::Register.default.path)
          Ukiryu::Register.reset_default
        else
          say 'Updating register...', :cyan
        end

        register = Ukiryu::Register.default
        register.update!

        say 'Register updated successfully!', :green
        show_info(options)
      end

      # Show the register path
      def show_path
        path = Ukiryu::Register.default.path

        if path && Dir.exist?(path)
          say path
        else
          error!('Register not available. Run: ukiryu register update')
        end
      end

      # Format the source for display
      #
      # @param source [Symbol] the source symbol
      # @return [String] formatted source
      def format_source(source)
        case source
        when :env
          'Environment variable (UKIRYU_REGISTER)'
        when :dev
          'Development mode (local submodule)'
        when :user
          'User local clone (~/.ukiryu/register)'
        else
          source.to_s
        end
      end

      # Show manual setup help
      def show_manual_setup_help
        say ''
        say 'Manual setup:', :cyan
        say ''
        say '  1. Clone the register:'
        say '     git clone https://github.com/ukiryu/register ~/.ukiryu/register'
        say ''
        say '  2. Or set environment variable:'
        say '     export UKIRYU_REGISTER=/path/to/register'
        say ''
        say '  3. Then run this command again.'
      end
    end
  end
end
