# frozen_string_literal: true

require_relative 'lint_issue'

module Ukiryu
  module Definition
    # Lint tool definitions for best practices
    #
    # This class checks tool definitions for best practices,
    # deprecated patterns, naming conventions, and security issues.
    class DefinitionLinter
      # Linting result
      class LintResult
        attr_reader :issues

        def initialize(issues = [])
          @issues = issues
        end

        # Get issues by severity
        #
        # @param severity [Symbol] severity level
        # @return [Array<LintIssue>] issues with the specified severity
        def by_severity(severity)
          @issues.select { |i| i.severity == severity }
        end

        # Get errors
        #
        # @return [Array<LintIssue>] error issues
        def errors
          by_severity(LintIssue::SEVERITY_ERROR)
        end

        # Get warnings
        #
        # @return [Array<LintIssue>] warning issues
        def warnings
          by_severity(LintIssue::SEVERITY_WARNING)
        end

        # Get info issues
        #
        # @return [Array<LintIssue>] info issues
        def infos
          by_severity(LintIssue::SEVERITY_INFO)
        end

        # Get style issues
        #
        # @return [Array<LintIssue>] style issues
        def styles
          by_severity(LintIssue::SEVERITY_STYLE)
        end

        # Check if there are any issues
        #
        # @return [Boolean] true if there are issues
        def has_issues?
          !@issues.empty?
        end

        # Check if there are any errors
        #
        # @return [Boolean] true if there are errors
        def has_errors?
          !errors.empty?
        end

        # Get total issue count
        #
        # @return [Integer] total number of issues
        def count
          @issues.length
        end

        # Get count by severity
        #
        # @param severity [Symbol] severity level
        # @return [Integer] count of issues with specified severity
        def count_by_severity(severity)
          by_severity(severity).length
        end

        # Convert to hash
        #
        # @return [Hash] hash representation
        def to_h
          {
            issues: @issues.map(&:to_h),
            total_count: count,
            error_count: errors.length,
            warning_count: warnings.length,
            info_count: infos.length,
            style_count: styles.length
          }
        end

        # Format as string
        #
        # @return [String] formatted result
        def to_s
          return 'No issues found' unless has_issues?

          output = []
          output << "Found #{count} issue(s):"

          {
            LintIssue::SEVERITY_ERROR => errors,
            LintIssue::SEVERITY_WARNING => warnings,
            LintIssue::SEVERITY_INFO => infos,
            LintIssue::SEVERITY_STYLE => styles
          }.each do |severity, issues|
            next if issues.empty?

            output << ''
            output << "#{severity.to_s.upcase}:"
            issues.each { |issue| output << "  #{issue}" }
          end

          output.join("\n")
        end
      end

      # Linting rules configuration
      class Rules
        # Naming convention rules
        NAMING_RULES = {
          tool_name_format: {
            rule_id: 'naming_tool_name_format',
            pattern: /^[a-z][a-z0-9_-]*$/,
            message: 'Tool name should start with a lowercase letter and contain only lowercase letters, numbers, hyphens, and underscores',
            suggestion: 'Use lowercase with hyphens for multi-word names (e.g., "my-tool")'
          },
          command_name_format: {
            rule_id: 'naming_command_name_format',
            pattern: /^[a-z][a-z0-9_]*$/,
            message: 'Command names should be lowercase with underscores',
            suggestion: 'Use snake_case for command names (e.g., "build_command")'
          }
        }.freeze

        # Completeness rules
        COMPLETENESS_RULES = {
          missing_description: {
            rule_id: 'complete_missing_description',
            message: 'Tool is missing a description',
            suggestion: 'Add a "description" field to help users understand what this tool does'
          },
          missing_homepage: {
            rule_id: 'complete_missing_homepage',
            message: 'Tool is missing a homepage URL',
            suggestion: 'Add a "homepage" field linking to the tool\'s website'
          },
          missing_version_detection: {
            rule_id: 'complete_missing_version_detection',
            message: 'Tool is missing version detection',
            suggestion: 'Add "version_detection" to auto-detect installed versions'
          }
        }.freeze

        # Security rules
        SECURITY_RULES = {
          suspicious_subcommand: {
            rule_id: 'security_suspicious_subcommand',
            pattern: /(^|\s|;)\s*(rm\s+-rf|del|format|mkfs)/,
            message: 'Subcommand contains potentially dangerous shell commands',
            suggestion: 'Avoid using destructive commands in subcommands'
          },
          unvalidated_user_input: {
            rule_id: 'security_unvalidated_input',
            message: 'Arguments should specify type validation',
            suggestion: 'Add "type" field to all arguments for validation'
          }
        }.freeze

        # Deprecated patterns
        DEPRECATED_RULES = {
          old_schema_version: {
            rule_id: 'deprecated_old_schema',
            threshold: '1.0',
            message: 'Using old schema version',
            suggestion: 'Update to the latest schema version (1.2)'
          }
        }.freeze
      end

      class << self
        # Lint a definition
        #
        # @param definition [Hash] the definition to lint
        # @param rules [Hash, nil] optional rule overrides
        # @return [LintResult] linting result
        def lint(definition, rules: nil)
          issues = []

          # Check if definition is a hash
          return LintResult.new([LintIssue.error('Definition must be a hash/object')]) unless definition.is_a?(Hash)

          # Run all lint checks
          issues.concat(check_naming_conventions(definition))
          issues.concat(check_completeness(definition))
          issues.concat(check_security(definition))
          issues.concat(check_deprecated_patterns(definition))
          issues.concat(check_best_practices(definition))

          # Filter by rules if provided
          if rules
            enabled_rules = rules[:enabled] || []
            disabled_rules = rules[:disabled] || []

            issues = issues.select do |issue|
              if disabled_rules.any?
                !disabled_rules.include?(issue.rule_id)
              elsif enabled_rules.any?
                enabled_rules.include?(issue.rule_id)
              else
                true
              end
            end
          end

          LintResult.new(issues)
        end

        # Lint a definition file
        #
        # @param file_path [String] path to definition file
        # @param rules [Hash, nil] optional rule overrides
        # @return [LintResult] linting result
        def lint_file(file_path, rules: nil)
          # Load raw YAML hash for linting
          require 'yaml'
          definition = YAML.safe_load(File.read(file_path), permitted_classes: [Symbol, Date, Time],
                                                            symbolize_names: true)
          lint(definition, rules: rules)
        rescue Ukiryu::DefinitionNotFoundError
          LintResult.new([LintIssue.error("File not found: #{file_path}")])
        rescue Ukiryu::DefinitionLoadError, Ukiryu::DefinitionValidationError => e
          LintResult.new([LintIssue.error(e.message)])
        rescue Errno::ENOENT
          LintResult.new([LintIssue.error("File not found: #{file_path}")])
        rescue Psych::SyntaxError => e
          LintResult.new([LintIssue.error("Invalid YAML: #{e.message}")])
        end

        # Lint a YAML string
        #
        # @param yaml_string [String] YAML content
        # @param rules [Hash, nil] optional rule overrides
        # @return [LintResult] linting result
        def lint_string(yaml_string, rules: nil)
          require 'yaml'
          definition = YAML.safe_load(yaml_string, permitted_classes: [Symbol, Date, Time])
          lint(definition, rules: rules)
        rescue Psych::SyntaxError => e
          LintResult.new([LintIssue.error("Invalid YAML: #{e.message}")])
        end

        private

        # Check naming conventions
        #
        # @param definition [Hash] the definition
        # @return [Array<LintIssue>] naming issues
        def check_naming_conventions(definition)
          issues = []

          # Check tool name format
          if definition[:name]
            rule = Rules::NAMING_RULES[:tool_name_format]
            unless definition[:name].match?(rule[:pattern])
              issues << LintIssue.warning(
                rule[:message],
                location: 'name',
                suggestion: rule[:suggestion],
                rule_id: rule[:rule_id]
              )
            end
          end

          # Check command names
          definition[:profiles]&.each_with_index do |profile, p_idx|
            next unless profile[:commands]

            profile[:commands].each_key do |cmd_name|
              rule = Rules::NAMING_RULES[:command_name_format]
              next if cmd_name.to_s.match?(rule[:pattern])

              issues << LintIssue.warning(
                rule[:message],
                location: "profiles[#{p_idx}].commands.#{cmd_name}",
                suggestion: rule[:suggestion],
                rule_id: rule[:rule_id]
              )
            end
          end

          issues
        end

        # Check completeness
        #
        # @param definition [Hash] the definition
        # @return [Array<LintIssue>] completeness issues
        def check_completeness(definition)
          issues = []

          # Check for description
          unless definition[:description]
            rule = Rules::COMPLETENESS_RULES[:missing_description]
            issues << LintIssue.info(
              rule[:message],
              location: 'definition',
              suggestion: rule[:suggestion],
              rule_id: rule[:rule_id]
            )
          end

          # Check for homepage
          unless definition[:homepage]
            rule = Rules::COMPLETENESS_RULES[:missing_homepage]
            issues << LintIssue.info(
              rule[:message],
              location: 'definition',
              suggestion: rule[:suggestion],
              rule_id: rule[:rule_id]
            )
          end

          # Check for version detection
          unless definition[:version_detection]
            rule = Rules::COMPLETENESS_RULES[:missing_version_detection]
            issues << LintIssue.warning(
              rule[:message],
              location: 'definition',
              suggestion: rule[:suggestion],
              rule_id: rule[:rule_id]
            )
          end

          issues
        end

        # Check security issues
        #
        # @param definition [Hash] the definition
        # @return [Array<LintIssue>] security issues
        def check_security(definition)
          issues = []

          # Check for suspicious subcommands
          definition[:profiles]&.each_with_index do |profile, p_idx|
            next unless profile[:commands]

            profile[:commands].each do |cmd_name, cmd_def|
              next unless cmd_def[:subcommand]

              subcommand = cmd_def[:subcommand].to_s
              rule = Rules::SECURITY_RULES[:suspicious_subcommand]
              next unless subcommand.match?(rule[:pattern])

              issues << LintIssue.error(
                rule[:message],
                location: "profiles[#{p_idx}].commands.#{cmd_name}.subcommand",
                suggestion: rule[:suggestion],
                rule_id: rule[:rule_id]
              )
            end

            # Check for unvalidated arguments
            next unless profile[:commands]

            profile[:commands].each do |cmd_name, cmd_def|
              next unless cmd_def[:arguments]

              cmd_def[:arguments].each_with_index do |arg, a_idx|
                next if arg[:type]

                rule = Rules::SECURITY_RULES[:unvalidated_user_input]
                issues << LintIssue.warning(
                  rule[:message],
                  location: "profiles[#{p_idx}].commands.#{cmd_name}.arguments[#{a_idx}]",
                  suggestion: rule[:suggestion],
                  rule_id: rule[:rule_id]
                )
              end
            end
          end

          issues
        end

        # Check for deprecated patterns
        #
        # @param definition [Hash] the definition
        # @return [Array<LintIssue>] deprecation issues
        def check_deprecated_patterns(definition)
          issues = []

          # Check schema version
          if definition[:schema] || definition['$schema']
            schema = definition[:schema] || definition['$schema']
            version = schema.to_s.split('/').last.gsub('v', '')

            require 'ukiryu/definition/version_resolver'
            rule = Rules::DEPRECATED_RULES[:old_schema_version]

            begin
              if VersionResolver.compare_versions(version, rule[:threshold]).negative?
                issues << LintIssue.warning(
                  rule[:message],
                  location: 'schema',
                  suggestion: rule[:suggestion],
                  rule_id: rule[:rule_id]
                )
              end
            rescue StandardError
              # Skip if version comparison fails
            end
          end

          issues
        end

        # Check best practices
        #
        # @param definition [Hash] the definition
        # @return [Array<LintIssue>] best practice issues
        def check_best_practices(definition)
          issues = []

          # Check for redundant default profile name
          definition[:profiles]&.each_with_index do |profile, p_idx|
            next unless profile[:name] == 'default' && definition[:profiles].length == 1

            issues << LintIssue.style(
              'Single profile named "default" is redundant',
              location: "profiles[#{p_idx}]",
              suggestion: 'For single-profile definitions, omit the profiles array and define commands directly',
              rule_id: 'style_redundant_default_profile'
            )

            # Check for missing platforms
            next if profile[:platforms]

            issues << LintIssue.warning(
              'Profile missing platforms specification',
              location: "profiles[#{p_idx}]",
              suggestion: 'Specify supported platforms (macos, linux, windows)',
              rule_id: 'complete_missing_platforms'
            )
          end

          issues
        end
      end
    end
  end
end
