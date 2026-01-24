# frozen_string_literal: true

require_relative '../register_auto_manager'
require_relative '../register'

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
      rescue RegisterAutoManager::RegisterError => e
        error!("Register error: #{e.message}")
      end

      private

      # Show register information
      #
      # @param options [Hash] command options
      def show_info(_options = {})
        info = RegisterAutoManager.register_info

        say 'Register Information', :cyan
        say ''

        case info[:status]
        when :not_found
          say '  Status: Not configured', :red
          say ''
          say '  No register found. Run: ukiryu register update', :yellow
        when :not_cloned
          say '  Status: Not cloned', :yellow
          say "  Expected path: #{info[:path]}", :dim
          say ''
          say '  Run: ukiryu register update', :yellow
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

          say "  Branch: #{info[:branch]}", :dim if info[:branch]

          say "  Commit: #{info[:commit]}", :dim if info[:commit]

          say "  Last updated: #{info[:last_update].strftime('%Y-%m-%d %H:%M:%S')}", :dim if info[:last_update]
        end

        say ''
        say 'Environment variable:', :cyan
        env_path = ENV['UKIRYU_REGISTER']
        if env_path
          say "  UKIRYU_REGISTER=#{env_path}", :dim
        else
          say '  UKIRYU_REGISTER (not set)', :dim
        end

        show_manual_setup_help if info[:status] != :ok
      end

      # Update the register
      #
      # @param options [Hash] command options
      def update_register(options = {})
        force = options[:force] || false

        if force
          say 'Force re-cloning register...', :yellow
        else
          say 'Updating register...', :cyan
        end

        RegisterAutoManager.update_register(force: force)

        say 'Register updated successfully!', :green
        show_info(options)
      end

      # Show the register path
      def show_path
        path = RegisterAutoManager.register_path

        if path
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
        say "     git clone #{RegisterAutoManager::REGISTER_URL} ~/.ukiryu/register"
        say ''
        say '  2. Or set environment variable:'
        say '     export UKIRYU_REGISTER=/path/to/register'
        say ''
        say '  3. Then run this command again.'
      end
    end
  end
end
