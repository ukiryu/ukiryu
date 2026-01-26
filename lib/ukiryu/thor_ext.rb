# frozen_string_literal: true

module Ukiryu
  # Configures Thor to behave more like a typical modern CLI.
  #
  # Features:
  # - Passing -h or --help to a command will show help for that command
  # - Unrecognized options will be treated as errors (not silently ignored)
  # - Error messages are printed to stderr in red, without stack trace
  # - Full stack traces can be enabled with VERBOSE environment variable
  # - Errors cause Thor to exit with non-zero status
  # - Missing required arguments show help instead of errors
  #
  # @example Extend your CLI with this module
  #   class Cli < Thor
  #     extend FriendlyCLI
  #   end
  #
  # Start your CLI with:
  #   Cli.start
  #
  # In tests, prevent Kernel.exit from being called:
  #   Cli.start(args, exit_on_failure: false)
  module FriendlyCLI
    # Regex patterns for error message parsing
    MISSING_ARGS_PATTERN = /"(\w+) (\w+)"/.freeze
    HELP_OPTIONS = %w[-h --help].freeze

    # Environment variables for trace mode
    TRACE_ENV_VARS = %w[UKIRYU_TRACE VERBOSE].freeze

    def self.extended(base)
      super
      base.check_unknown_options!
    end

    # Override Thor's start method to provide better CLI behavior
    #
    # @param given_args [Array<String>] the command-line arguments
    # @param config [Hash] configuration options
    # @option config [Thor::Shell] :shell the Thor shell instance
    # @option config [Boolean] :exit_on_failure whether to exit on errors (default: true)
    def start(given_args = ARGV, config = {})
      config[:shell] ||= Thor::Base.shell.new

      handle_help_switches(given_args) do |args|
        dispatch(nil, args, nil, config)
      end
    rescue StandardError, Exception => e
      handle_exception_on_start(e, config)
    end

    # Override Thor's handle_argument_error to show help for missing arguments
    #
    # @param command [Thor::Command] the Thor command object
    # @param error [Exception] the error that was raised
    # @param _args [Array] the arguments that were passed (unused)
    # @param _arity [Integer] the arity of the command (unused)
    def handle_argument_error(command, error, _args, _arity)
      return show_help_for_command(error) if missing_arguments_error?(error)
      return handle_argument_count_error(command, error) if wrong_argument_count_error?(error)

      # Otherwise, handle as normal error
      handle_exception_on_start(error, {})
    end

    private

    # Check if error indicates missing arguments
    #
    # @param error [Exception] the error to check
    # @return [Boolean] true if this is a missing arguments error
    def missing_arguments_error?(error)
      error.message.include?('was called with no arguments') &&
        error.message.match?(MISSING_ARGS_PATTERN)
    end

    # Check if error indicates wrong argument count
    #
    # @param error [Exception] the error to check
    # @return [Boolean] true if this is a wrong argument count error
    def wrong_argument_count_error?(error)
      error.is_a?(ArgumentError) && error.message.include?('wrong number of arguments')
    end

    # Show help for a command when arguments are missing
    #
    # @param error [Exception] the error containing the command name
    def show_help_for_command(error)
      return unless (match = error.message.match(MISSING_ARGS_PATTERN))

      command_name = match[2]
      start(['help', command_name])
    end

    # Handle wrong number of arguments error
    #
    # @param command [Thor::Command] the Thor command object
    # @param error [Exception] the ArgumentError
    def handle_argument_count_error(command, error)
      cmd_name = command.name
      message = build_argument_error_message(cmd_name, error.message)

      print_error_message(message)
      exit(false)
    end

    # Build appropriate error message for argument errors
    #
    # @param cmd_name [String] the command name
    # @param error_message [String] the original error message
    # @return [String] a user-friendly error message
    def build_argument_error_message(cmd_name, error_message)
      if error_message.include?('given 0')
        "Missing required argument for '#{cmd_name}'. Check the command syntax with: ukiryu help #{cmd_name}"
      else
        "Invalid number of arguments for '#{cmd_name}'. Check the command syntax with: ukiryu help #{cmd_name}"
      end
    end

    # Handle -h and --help switches by converting them to Thor's help format
    #
    # @param given_args [Array<String>] the command-line arguments
    # @yield [Array<String>] the processed arguments
    def handle_help_switches(given_args)
      yield(given_args.dup)
    rescue Thor::UnknownArgumentError => e
      retry_with_args = build_help_args(given_args, e)

      return yield(retry_with_args) if retry_with_args.any?

      # Not a help-related error, re-raise to be handled by outer rescue
      raise
    end

    # Build help arguments from the given args and error
    #
    # @param given_args [Array<String>] the original command-line arguments
    # @param error [Thor::UnknownArgumentError] the error from Thor
    # @return [Array<String>] help arguments or empty array
    def build_help_args(given_args, error)
      return ['help'] if given_args.first == 'help' && given_args.length > 1
      return ['help', (given_args - error.unknown).first] if error.unknown.intersect?(HELP_OPTIONS)

      []
    end

    # Handle exceptions during CLI execution
    #
    # @param error [Exception] the exception that was raised
    # @param config [Hash] configuration options
    def handle_exception_on_start(error, config)
      # EPIPE errors are safe to ignore (happens when piping to head and similar)
      return if error.is_a?(Errno::EPIPE)

      # SystemExit is used for intentional exits (from handle_argument_error or error!)
      # Just exit with the same status without printing anything
      return Kernel.exit(error.status || 1) if error.is_a?(SystemExit)

      # Re-raise (show full stack trace) if user has opted into trace mode
      return raise if trace_mode_enabled?(config)

      # Build error message with class prefix for non-Thor errors
      message = format_error_message(error)

      # Print error to stderr in red
      print_error_message(message, config[:shell])

      # Exit with non-zero status
      exit(false)
    end

    # Check if trace mode is enabled via environment or config
    #
    # @param config [Hash] configuration options
    # @return [Boolean] true if trace mode is enabled
    def trace_mode_enabled?(config)
      TRACE_ENV_VARS.any? { |var| ENV[var] } || config[:trace]
    end

    # Format error message with appropriate class prefix
    #
    # @param error [Exception] the error to format
    # @return [String] the formatted error message
    def format_error_message(error)
      message = error.message.to_s.dup
      return message if error.is_a?(Thor::Error) && !message.empty?

      # Add class prefix for non-Thor errors or empty messages
      message.prepend("[#{error.class}] ") if message.empty? || !error.is_a?(Thor::Error)
      message
    end

    # Print error message to stderr in red (if supported)
    #
    # @param message [String] the error message
    # @param shell [Thor::Shell, nil] the Thor shell instance (optional)
    def print_error_message(message, shell = nil)
      shell ||= Thor::Base.shell.new

      if shell.respond_to?(:say_error)
        shell.say_error(message, :red)
      else
        warn "\e[31m#{message}\e[0m"
      end
    end
  end
end
