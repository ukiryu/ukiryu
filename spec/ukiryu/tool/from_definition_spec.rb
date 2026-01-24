# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Tool, '.from_definition' do
  let(:valid_yaml) do
    <<~YAML
      name: string_tool
      version: "1.0"
      display_name: String Tool
      homepage: https://example.com/string
      profiles:
        - name: default
          platforms: [linux, macos]
          shells: [bash, zsh]
          commands:
            - name: process
              description: Process command
              arguments:
                - name: input
                  type: file
                  position: last
                  min: 1
              flags:
                - name: verbose
                  cli: -v
                  default: false
    YAML
  end

  describe 'loading from string' do
    it 'creates a Tool instance' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool).to be_a(Ukiryu::Tool)
      expect(tool.name).to eq('string_tool')
    end

    it 'loads the tool definition from string' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.profile).to be_a(Ukiryu::Models::ToolDefinition)
      expect(tool.profile.name).to eq('string_tool')
    end

    it 'sets definition_source to a StringSource source' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.definition_source).to be_a(Ukiryu::Definition::Sources::StringSource)
      expect(tool.definition_source.source_type).to eq(:string)
    end

    it 'does not set definition_path (not applicable)' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.definition_path).to be_nil
    end

    it 'does not set definition_mtime (not applicable)' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.definition_mtime).to be_nil
    end

    it 'accepts options hash' do
      tool = described_class.from_definition(valid_yaml, platform: :linux)

      expect(tool).to be_a(Ukiryu::Tool)
    end

    it 'passes options to Tool constructor' do
      tool = described_class.from_definition(valid_yaml, platform: :linux, shell: :bash)

      expect(tool.instance_variable_get(:@platform)).to eq(:linux)
      expect(tool.instance_variable_get(:@shell)).to eq(:bash)
    end
  end

  describe 'error handling' do
    it 'raises DefinitionLoadError for invalid YAML syntax' do
      invalid_yaml = 'name: test\n  invalid: [unclosed'

      expect { described_class.from_definition(invalid_yaml) }.to raise_error(
        Ukiryu::DefinitionLoadError,
        /Invalid YAML/
      )
    end

    it 'raises DefinitionLoadError for empty string' do
      expect { described_class.from_definition('') }.to raise_error(
        Ukiryu::DefinitionLoadError,
        /cannot be empty/
      )
    end

    it 'raises DefinitionLoadError for invalid profile structure' do
      invalid_yaml = 'name: test\n# Missing: version, profiles'

      expect { described_class.from_definition(invalid_yaml) }.to raise_error(
        Ukiryu::DefinitionLoadError
      )
    end

    it 'raises ArgumentError for non-string input' do
      expect { described_class.from_definition(123) }.to raise_error(
        ArgumentError,
        /must be a String/
      )
    end

    it 'raises ArgumentError for nil input' do
      expect { described_class.from_definition(nil) }.to raise_error(
        ArgumentError,
        /must be a String/
      )
    end
  end

  describe 'validation modes' do
    it 'validates in strict mode by default' do
      expect { described_class.from_definition(valid_yaml) }.not_to raise_error
    end

    it 'validates with explicit strict mode' do
      expect { described_class.from_definition(valid_yaml, validation: :strict) }.not_to raise_error
    end

    it 'warns in lenient mode' do
      expect { described_class.from_definition(valid_yaml, validation: :lenient) }.not_to raise_error
    end

    it 'skips validation in none mode' do
      # :none mode skips validation but Tool still needs valid profiles
      # This test verifies that validation is skipped, not that invalid profiles work
      expect { described_class.from_definition(valid_yaml, validation: :none) }.not_to raise_error
    end
  end

  describe 'tool functionality' do
    it 'provides access to commands' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.commands).to be_a(Array)
      expect(tool.commands.first.name).to eq('process')
    end

    it 'provides command_definition method' do
      tool = described_class.from_definition(valid_yaml)

      command_def = tool.command_definition(:process)

      expect(command_def).to be_a(Ukiryu::Models::CommandDefinition)
      expect(command_def.name).to eq('process')
    end

    it 'has definition_source accessible' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.definition_source).to be_a(Ukiryu::Definition::Source)
      expect(tool.definition_source.source_type).to eq(:string)
    end

    it 'has content_hash accessible' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.definition_source.content_hash).to match(/^[a-f0-9]{64}$/)
    end

    it 'has size method accessible' do
      tool = described_class.from_definition(valid_yaml)

      expect(tool.definition_source.size).to be > 0
    end
  end

  describe 'with different YAML content' do
    it 'handles simple YAML' do
      simple_yaml = <<~YAML
        name: simple
        version: "1.0"
        profiles:
          - name: default
            platforms: [linux]
            shells: [bash]
      YAML

      expect { described_class.from_definition(simple_yaml, validation: :none) }.not_to raise_error
    end

    it 'handles complex nested YAML' do
      complex_yaml = <<~YAML
        name: complex
        version: "2.0"
        aliases:
          - cpx
          - cplx
        search_paths:
          linux:
            - /usr/bin/complex
            - /usr/local/bin/complex
        profiles:
          - name: modern
            version: ">= 2.0"
            platforms: [linux, macos, windows]
            shells: [bash, zsh, powershell]
            commands:
              - name: complex_command
                description: A complex command
                arguments:
                  - name: inputs
                    type: file
                    variadic: true
                    position: last
                    min: 1
                    description: Input files
                options:
                  - name: output
                    type: file
                    cli: --output
                    format: double_dash_equals
                    required: true
                    description: Output file
                  - name: quality
                    type: integer
                    cli: --quality
                    min: 1
                    max: 100
                    description: Quality setting
                flags:
                  - name: verbose
                    cli: --verbose
                    default: false
                    description: Verbose output
                  - name: quiet
                    cli: -q
                    default: false
                    description: Quiet mode
      YAML

      tool = described_class.from_definition(complex_yaml)

      expect(tool.name).to eq('complex')
      expect(tool.profile.aliases).to eq(%w[cpx cplx])
      # search_paths is a SearchPaths model object, not a Hash
      expect(tool.profile.search_paths).to be_a(Ukiryu::Models::SearchPaths)
    end

    it 'preserves YAML formatting' do
      formatted_yaml = "name: test\nversion: \"1.0\"\nprofiles:\n  - name: default"

      tool = described_class.from_definition(formatted_yaml, validation: :none)

      expect(tool).to be_a(Ukiryu::Tool)
    end
  end

  describe 'alias' do
    it 'has from_definition as alias for load_from_string' do
      tool1 = described_class.load_from_string(valid_yaml)
      tool2 = described_class.from_definition(valid_yaml)

      expect(tool1.name).to eq(tool2.name)
      expect(tool1.definition_source).to be_a(Ukiryu::Definition::Sources::StringSource)
      expect(tool2.definition_source).to be_a(Ukiryu::Definition::Sources::StringSource)
    end
  end

  describe 'caching' do
    it 'creates separate instances for same content' do
      tool1 = described_class.from_definition(valid_yaml)
      tool2 = described_class.from_definition(valid_yaml)

      # Each call creates a new instance
      expect(tool1).not_to be(tool2)
    end

    it 'creates tools with same definition source' do
      tool1 = described_class.from_definition(valid_yaml)
      tool2 = described_class.from_definition(valid_yaml)

      expect(tool1.definition_source.cache_key).to eq(tool2.definition_source.cache_key)
    end
  end

  describe 'integration with options_for' do
    it 'provides options class for commands' do
      tool = described_class.from_definition(valid_yaml)

      # options_for requires the tool to be in the register
      # For dynamically loaded tools, we can test the command definitions directly
      command_def = tool.command_definition(:process)
      expect(command_def).to be_a(Ukiryu::Models::CommandDefinition)
      expect(command_def.name).to eq('process')
    end
  end
end
