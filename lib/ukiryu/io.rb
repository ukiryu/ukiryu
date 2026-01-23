# frozen_string_literal: true

module Ukiryu
  # I/O stream primitives for CLI tools
  #
  # This module defines standard I/O primitives that are common across
  # command-line tools, providing a consistent interface for:
  # - Standard input (stdin)
  # - Standard output (stdout)
  # - Standard error (stderr)
  # - Pipes (inter-process communication)
  # - File redirections
  #
  # These are GENERAL PRIMITIVES that apply to ALL CLI tools, not tool-specific.

  # Standard stream marker for stdin
  STDIN = '-'

  # Standard stream marker for stdout
  STDOUT = '-'
  # Also available as "%stdout%" in some tools (Ghostscript)

  # Special value for reading from stdin (double dash)
  STDIN_MARKER = '--'

  # Standard stream constants
  module Stream
    # Standard input stream descriptor
    #
    # Used for commands that can read from stdin instead of a file
    # @example
    #   # Read from stdin
    #   tool.options_for(:process).tap do |opts|
    #     opts.inputs = [Ukiryu::IO::Stream::STDIN]
    #     opts.output = "output.pdf"
    #   end
    STDIN = :stdin

    # Standard output stream descriptor
    #
    # Used for commands that can write to stdout instead of a file
    # @example
    #   tool.options_for(:export).tap do |opts|
    #     opts.inputs = ["input.svg"]
    #     opts.output = Ukiryu::IO::Stream::STDOUT
    #   end
    STDOUT = :stdout

    # Standard error stream descriptor
    #
    # Used for separating stderr from stdout
    STDERR = :stderr
  end

  # Pipe redirection for inter-process communication
  #
  # Pipes allow the output of one command to become the input of another.
  # This is represented by special file path markers.
  #
  # @example
  #   # Pipe output of command1 to command2
  #   result1 = command1.execute(output: Pipe.to("command2"))
  #
  # @example Using special syntax in tools
  #   # Ghostscript: -sOutputFile=%pipe%lpr
  #   # Tar: --to-command=COMMAND
  class Pipe
    # Special marker for pipe output
    MARKER = '%pipe%'

    # Create a pipe to a command
    #
    # @param command [String] the command to pipe to
    # @return [String] the pipe marker for use in CLI options
    #
    # @example
    #   Pipe.to("lpr") # => "%pipe%lpr"
    def self.to(command)
      "#{MARKER}#{command}"
    end

    # Parse a pipe marker
    #
    # @param value [String] the pipe marker string
    # @return [String, nil] the command if it's a pipe marker
    #
    # @example
    #   Pipe.parse("%pipe%lpr") # => "lpr"
    def self.parse(value)
      return nil unless value.is_a?(String)
      return nil unless value.start_with?(MARKER)

      value.sub(MARKER, '')
    end

    # Check if a value is a pipe marker
    #
    # @param value [String] the value to check
    # @return [Boolean] true if it's a pipe marker
    def self.pipe?(value)
      return false unless value.is_a?(String)

      value.start_with?(MARKER)
    end
  end

  # File redirection primitives
  #
  # Provides utilities for file redirection operations
  module Redirection
    # Redirect output to a file
    #
    # @param output [Symbol, String] :stdout or :stderr
    # @param path [String] the file path to redirect to
    # @return [Hash] redirection specification
    #
    # @example
    #   Redirection.to(:stdout, "/tmp/output.txt")
    def self.to(stream, path)
      { stream => path }
    end

    # Redirect stderr to stdout (2>&1 in shell)
    #
    # @return [Hash] redirection specification
    #
    # @example
    #   Redirection.stderr_to_stdout
    def self.stderr_to_stdout
      { stderr: :stdout }
    end
  end

  # Standard input/output file handles
  #
  # This class represents special file handles for stdin/stdout/stderr
  # that are recognized by CLI tools.
  #
  # @example
  #   # Reading from stdin
  #   input = Ukiryu::IO::StandardInput.new
  #   input.read
  #
  #   # Writing to stdout
  #   output = Ukiryu::IO::StandardOutput.new
  #   output.write("data")
  class StandardInput
    # The stdin file descriptor
    FILENO = 0

    # Check if a path represents stdin
    #
    # @param path [String, Symbol] the path to check
    # @return [Boolean] true if the path represents stdin
    #
    # @example
    #   Ukiryu::IO::StandardInput.stdin?("-")  # => true
    #   Ukiryu::IO::StandardInput.stdin?(:stdin)  # => true
    def self.stdin?(path)
      path = path.to_s if path.is_a?(Symbol)
      [$stdin, '-', '/dev/stdin'].include?(path)
    end
  end

  class StandardOutput
    # The stdout file descriptor
    FILENO = 1

    # Check if a path represents stdout
    #
    # @param path [String, Symbol] the path to check
    # @return [Boolean] true if the path represents stdout
    #
    # @example
    #   Ukiryu::IO::StandardOutput.stdout?("-")  # => true
    #   Ukiryu::IO::StandardOutput.stdout?(:stdout)  # => true
    def self.stdout?(path)
      path = path.to_s if path.is_a?(Symbol)
      [$stdout, '-', '/dev/stdout', '%stdout%'].include?(path)
    end
  end

  class StandardError
    # The stderr file descriptor
    FILENO = 2

    # Check if a path represents stderr
    #
    # @param path [String, Symbol] the path to check
    # @return [Boolean] true if the path represents stderr
    def self.stderr?(path)
      path = path.to_s if path.is_a?(Symbol)
      [:stderr, '/dev/stderr'].include?(path)
    end
  end
end
