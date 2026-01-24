# frozen_string_literal: true

require 'thor'
require_relative '../definition/definition_linter'

module Ukiryu
  module CliCommands
    # Lint tool definitions for best practices
    #
    # The lint command checks tool definitions for best practices,
    # deprecated patterns, and potential issues.
    class LintCommand < Thor
      class_option :verbose, type: :boolean, default: false
      class_option :format, type: :string, default: 'text', enum: %w[text json]
      class_option :severity, type: :string, enum: %w[error warning info style], desc: 'Minimum severity level'

      desc 'file PATH', 'Lint a definition file'
      def file(path)
        lint_file(path)
      end

      desc 'all', 'Lint all definitions in register'
      option :register, type: :string, desc: 'Register path'
      def all
        lint_all
      end

      desc 'rules', 'List all linting rules'
      def rules
        list_rules
      end

      private

      # Lint a single file
      #
      # @param path [String] file path
      def lint_file(path)
        result = Ukiryu::Definition::DefinitionLinter.lint_file(path)

        output_result(result, path)

        # Exit with error if there are errors
        exit 1 if result.has_errors?
      end

      # Lint all definitions in register
      def lint_all
        register_path = options[:register] || Ukiryu::Register.default_register_path
        return say_error("Register not found: #{register_path}") unless Dir.exist?(register_path)

        tools_dir = File.join(register_path, 'tools')
        return say_error("Tools directory not found: #{tools_dir}") unless Dir.exist?(tools_dir)

        results = {}
        total_issues = 0

        Dir.glob(File.join(tools_dir, '*', '*', '*.yaml')).each do |file|
          result = Ukiryu::Definition::DefinitionLinter.lint_file(file)
          results[file] = result
          total_issues += result.count
        end

        # Summary
        total_files = results.length
        total_errors = results.values.sum(&:error_count)
        total_warnings = results.values.sum { |r| r.count_by_severity(Ukiryu::Definition::LintIssue::SEVERITY_WARNING) }

        say "\nLint Summary:", :cyan
        say "  Files: #{total_files}", :white
        say "  Issues: #{total_issues}", total_issues.zero? ? :green : :white
        say "  Errors: #{total_errors}", total_errors.zero? ? :green : :red
        say "  Warnings: #{total_warnings}", :white

        # Show files with issues
        if total_issues.positive?
          say '', :clear
          say 'Files with Issues:', :yellow

          results.each do |file, result|
            next unless result.has_issues?

            status = result.has_errors? ? '✗' : '⚠'
            say "  #{status} #{file} (#{result.count} issues)", :white
          end
        end

        exit 1 if total_errors.positive?
      end

      # List all linting rules
      def list_rules
        say 'Linting Rules:', :cyan
        say '', :clear

        say 'Naming Convention Rules:', :white
        say '  naming_tool_name_format - Tool name format', :dim
        say '  naming_command_name_format - Command name format', :dim
        say '', :clear

        say 'Completeness Rules:', :white
        say '  complete_missing_description - Missing description', :dim
        say '  complete_missing_homepage - Missing homepage', :dim
        say '  complete_missing_version_detection - Missing version detection', :dim
        say '', :clear

        say 'Security Rules:', :white
        say '  security_suspicious_subcommand - Dangerous shell commands', :dim
        say '  security_unvalidated_input - Arguments without type validation', :dim
        say '', :clear

        say 'Best Practice Rules:', :white
        say '  style_redundant_default_profile - Redundant default profile', :dim
        say '  complete_missing_platforms - Missing platforms specification', :dim
      end

      # Output linting result
      #
      # @param result [LintResult] linting result
      # @param source [String] source identifier
      def output_result(result, source)
        case options[:format]
        when 'json'
          say result.to_h.to_json, :white
        else
          output_text(result, source)
        end
      end

      # Output as text
      #
      # @param result [LintResult] linting result
      # @param source [String] source identifier
      def output_text(result, source)
        say "Linting: #{source}", :cyan

        if result.has_issues?
          say "\nFound #{result.count} issue(s):", :yellow

          {
            Ukiryu::Definition::LintIssue::SEVERITY_ERROR => 'Errors',
            Ukiryu::Definition::LintIssue::SEVERITY_WARNING => 'Warnings',
            Ukiryu::Definition::LintIssue::SEVERITY_INFO => 'Info',
            Ukiryu::Definition::LintIssue::SEVERITY_STYLE => 'Style'
          }.each do |severity, label|
            issues = result.by_severity(severity)
            next if issues.empty?

            say '', :clear
            say "#{label}:", severity == :error ? :red : :white
            issues.each { |issue| say "  #{issue}", :white }
          end
        else
          say "\n✓ No issues found", :green
        end
      end

      # Show error message
      #
      # @param message [String] error message
      def say_error(message)
        say message, :red
        exit 1
      end
    end
  end
end
