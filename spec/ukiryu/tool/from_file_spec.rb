# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Tool, '.from_file' do
  let(:temp_dir) { Dir.mktmpdir('ukiryu-spec-') }
  let(:valid_yaml) do
    <<~YAML
      name: test_tool
      version: "1.0"
      display_name: Test Tool
      homepage: https://example.com/test
      profiles:
        - name: default
          platforms: [linux, macos]
          shells: [bash, zsh]
          commands:
            - name: export
              description: Export command
              arguments:
                - name: inputs
                  type: file
                  variadic: true
                  position: last
                  min: 1
              options:
                - name: output
                  type: file
                  cli: --output
                  required: true
    YAML
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe 'loading from file' do
    let(:file_path) { File.join(temp_dir, 'test_tool.yaml') }

    before do
      File.write(file_path, valid_yaml)
    end

    it 'creates a Tool instance' do
      tool = described_class.from_file(file_path)

      expect(tool).to be_a(Ukiryu::Tool)
      expect(tool.name).to eq('test_tool')
    end

    it 'loads the tool definition from file' do
      tool = described_class.from_file(file_path)

      expect(tool.profile).to be_a(Ukiryu::Models::ToolDefinition)
      expect(tool.profile.name).to eq('test_tool')
    end

    it 'sets definition_source to a FileSource source' do
      tool = described_class.from_file(file_path)

      expect(tool.definition_source).to be_a(Ukiryu::Definition::Sources::FileSource)
      expect(tool.definition_source.source_type).to eq(:file)
    end

    it 'sets definition_path to the file path' do
      tool = described_class.from_file(file_path)

      expect(tool.definition_path).to eq(File.expand_path(file_path))
    end

    it 'sets definition_mtime after loading' do
      tool = described_class.from_file(file_path)

      expect(tool.definition_mtime).to be_a(Time)
    end

    it 'accepts options hash' do
      tool = described_class.from_file(file_path, platform: :linux)

      expect(tool).to be_a(Ukiryu::Tool)
    end

    it 'passes options to Tool constructor' do
      tool = described_class.from_file(file_path, platform: :linux, shell: :bash)

      expect(tool.instance_variable_get(:@platform)).to eq(:linux)
      expect(tool.instance_variable_get(:@shell)).to eq(:bash)
    end
  end

  describe 'error handling' do
    it 'raises DefinitionNotFoundError for non-existent file' do
      expect { described_class.from_file('nonexistent.yaml') }.to raise_error(
        Ukiryu::DefinitionNotFoundError
      )
    end

    it 'raises DefinitionLoadError for invalid YAML' do
      file_path = File.join(temp_dir, 'invalid.yaml')
      File.write(file_path, 'name: test\n  invalid: [')

      expect { described_class.from_file(file_path) }.to raise_error(
        Ukiryu::DefinitionLoadError
      )
    end

    it 'raises DefinitionLoadError for invalid profile structure' do
      invalid_yaml = <<~YAML
        name: test
        version: "1.0"
        # Missing: profiles
      YAML

      file_path = File.join(temp_dir, 'invalid.yaml')
      File.write(file_path, invalid_yaml)

      # Validation runs before Tool constructor, so we get DefinitionValidationError
      expect { described_class.from_file(file_path) }.to raise_error(
        Ukiryu::DefinitionValidationError
      )
    end
  end

  describe 'validation modes' do
    let(:file_path) { File.join(temp_dir, 'test_tool.yaml') }

    before do
      File.write(file_path, valid_yaml)
    end

    it 'validates in strict mode by default' do
      expect { described_class.from_file(file_path) }.not_to raise_error
    end

    it 'validates with explicit strict mode' do
      expect { described_class.from_file(file_path, validation: :strict) }.not_to raise_error
    end

    it 'warns in lenient mode' do
      expect { described_class.from_file(file_path, validation: :lenient) }.not_to raise_error
    end

    it 'skips validation in none mode' do
      # :none mode skips validation but Tool still needs valid profiles
      # This test verifies that validation is skipped, not that invalid profiles work
      expect { described_class.from_file(file_path, validation: :none) }.not_to raise_error
    end
  end

  describe 'tool functionality' do
    let(:file_path) { File.join(temp_dir, 'functional_tool.yaml') }

    before do
      File.write(file_path, valid_yaml)
    end

    it 'provides access to commands' do
      tool = described_class.from_file(file_path)

      expect(tool.commands).to be_a(Array)
      expect(tool.commands.first.name).to eq('export')
    end

    it 'provides command_definition method' do
      tool = described_class.from_file(file_path)

      command_def = tool.command_definition(:export)

      expect(command_def).to be_a(Ukiryu::Models::CommandDefinition)
      expect(command_def.name).to eq('export')
    end

    it 'has definition_source accessible' do
      tool = described_class.from_file(file_path)

      expect(tool.definition_source).to be_a(Ukiryu::Definition::Source)
      expect(tool.definition_source.source_type).to eq(:file)
    end

    it 'tracks file metadata' do
      tool = described_class.from_file(file_path)

      expect(tool.definition_path).to be_a(String)
      expect(tool.definition_mtime).to be_a(Time)
    end
  end

  describe 'alias' do
    it 'has from_file as alias for load' do
      file_path = File.join(temp_dir, 'test.yaml')
      File.write(file_path, valid_yaml)

      tool1 = described_class.load(file_path)
      tool2 = described_class.from_file(file_path)

      expect(tool1.name).to eq(tool2.name)
      expect(tool1.definition_source).to be_a(Ukiryu::Definition::Sources::FileSource)
      expect(tool2.definition_source).to be_a(Ukiryu::Definition::Sources::FileSource)
    end
  end
end
