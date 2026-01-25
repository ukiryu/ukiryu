# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Ukiryu::Tool Direct Loading' do
  let(:register_path) { '/dummy/register/path' }
  let(:valid_profile_content) do
    <<~YAML
      name: test_tool
      version: "1.0"
      display_name: Test Tool
      profiles:
        - name: default
          platforms: [macos, linux, windows]
          shells: [bash, zsh, powershell]
          commands:
            - name: test
              description: Test command
    YAML
  end

  let(:profile_with_new_fields) do
    <<~YAML
      ukiryu_schema: "1.1"
      $self: https://www.ukiryu.com/register/1.1/test/1.0
      name: test_tool
      version: "1.0"
      display_name: Test Tool
      profiles:
        - name: default
          platforms: [macos, linux, windows]
          shells: [bash, zsh, powershell]
          commands:
            - name: test
              description: Test command
    YAML
  end

  let(:invalid_yaml) { 'invalid: yaml: content: [unclosed' }

  let(:minimal_profile) do
    <<~YAML
      name: minimal
      version: "1.0"
      profiles:
        - name: default
          platforms: [macos, linux, windows]
          shells: [bash]
    YAML
  end

  let(:profile_with_missing_fields) do
    <<~YAML
      ukiryu_schema: "1.1"
      name: incomplete
    YAML
  end

  describe '.load_from_string' do
    context 'with valid YAML' do
      it 'creates a Tool instance' do
        tool = Ukiryu::Tool.load_from_string(valid_profile_content)

        expect(tool).to be_a(Ukiryu::Tool)
        expect(tool.name).to eq('test_tool')
        expect(tool.profile.version).to eq('1.0')
      end

      it 'parses ukiryu_schema field' do
        tool = Ukiryu::Tool.load_from_string(profile_with_new_fields)

        expect(tool.profile.ukiryu_schema).to eq('1.1')
      end

      it 'parses $self field' do
        tool = Ukiryu::Tool.load_from_string(profile_with_new_fields)

        expect(tool.profile.self_uri).to eq('https://www.ukiryu.com/register/1.1/test/1.0')
      end

      it 'works with minimal profile' do
        tool = Ukiryu::Tool.load_from_string(minimal_profile)

        expect(tool).to be_a(Ukiryu::Tool)
        expect(tool.name).to eq('minimal')
      end
    end

    context 'with invalid YAML' do
      it 'raises DefinitionLoadError for syntax errors' do
        expect do
          Ukiryu::Tool.load_from_string(invalid_yaml)
        end.to raise_error(Ukiryu::DefinitionLoadError)
      end
    end

    context 'with validation mode :strict' do
      it 'raises DefinitionValidationError for missing required fields' do
        expect do
          Ukiryu::Tool.load_from_string(profile_with_missing_fields, validation: :strict)
        end.to raise_error(Ukiryu::DefinitionValidationError, /Missing 'version' field/)
      end

      it 'raises DefinitionValidationError for invalid ukiryu_schema format' do
        invalid_schema = <<~YAML
          ukiryu_schema: "invalid"
          name: test
          version: "1.0"
          profiles:
            - name: default
              platforms: [macos]
              shells: [bash]
        YAML

        expect do
          Ukiryu::Tool.load_from_string(invalid_schema, validation: :strict)
        end.to raise_error(Ukiryu::DefinitionValidationError, /Invalid ukiryu_schema format/)
      end

      it 'raises DefinitionValidationError for invalid $self URI' do
        invalid_self = <<~YAML
          ukiryu_schema: "1.1"
          $self: "not-a-uri"
          name: test
          version: "1.0"
          profiles:
            - name: default
              platforms: [macos]
              shells: [bash]
        YAML

        expect do
          Ukiryu::Tool.load_from_string(invalid_self, validation: :strict)
        end.to raise_error(Ukiryu::DefinitionValidationError, /Invalid \$self URI format/)
      end
    end

    context 'with validation mode :lenient' do
      it 'warns but creates tool for missing fields' do
        expect do
          Ukiryu::Tool.load_from_string(profile_with_missing_fields, validation: :lenient)
        end.to output(/Profile validation failed/).to_stderr
                                                  .and raise_error(Ukiryu::ProfileNotFoundError)
      end
    end

    context 'with validation mode :none' do
      it 'skips validation but still fails on profile initialization' do
        expect do
          Ukiryu::Tool.load_from_string(profile_with_missing_fields, validation: :none)
        end.to raise_error(Ukiryu::ProfileNotFoundError)
      end
    end
  end

  describe '.load' do
    let(:temp_file) { File.join(Dir.tmpdir, "ukiryu_test_#{rand(1000)}.yaml") }

    after do
      File.delete(temp_file) if File.exist?(temp_file)
    end

    it 'loads a tool from a file path' do
      File.write(temp_file, valid_profile_content)

      tool = Ukiryu::Tool.load(temp_file)

      expect(tool).to be_a(Ukiryu::Tool)
      expect(tool.name).to eq('test_tool')
    end

    it 'raises DefinitionNotFoundError for non-existent file' do
      expect do
        Ukiryu::Tool.load('/nonexistent/path/to/file.yaml')
      end.to raise_error(Ukiryu::DefinitionNotFoundError)
    end

    it 'passes validation mode to load_from_string' do
      File.write(temp_file, profile_with_missing_fields)

      expect do
        Ukiryu::Tool.load(temp_file, validation: :strict)
      end.to raise_error(Ukiryu::DefinitionValidationError, /Missing 'version' field/)
    end
  end

  describe '.bundled_definition_search_paths' do
    let(:paths) { Ukiryu::Tool.bundled_definition_search_paths }

    it 'returns platform-specific paths' do
      expect(paths).to be_an(Array)
      expect(paths).to include(File.expand_path('~/.local/share/ukiryu'))

      if Ukiryu::Platform.windows?
        expect(paths).to include(File.expand_path('C:/Program Files/Ukiryu'))
        expect(paths).to include(File.expand_path('C:/Program Files (x86)/Ukiryu'))
      else
        expect(paths).to include('/usr/share/ukiryu')
        expect(paths).to include('/usr/local/share/ukiryu')
      end
    end

    it 'includes homebrew path on macOS' do
      skip 'Skipped on Windows - Homebrew is Unix-only' if Ukiryu::Platform.windows?

      allow(Ukiryu::Platform).to receive(:detect).and_return(:macos)

      platform_paths = Ukiryu::Tool.bundled_definition_search_paths
      expect(platform_paths).to include('/opt/homebrew/share/ukiryu')
    end
  end

  describe '.from_bundled' do
    let(:bundled_path) { File.join(Dir.tmpdir, "ukiryu_bundled_#{rand(1000)}") }

    after do
      FileUtils.rm_rf(bundled_path) if Dir.exist?(bundled_path)
    end

    context 'when tool definition exists in bundled paths' do
      before do
        # Create temporary bundled directory structure
        tool_dir = File.join(bundled_path, 'test_tool')
        FileUtils.mkdir_p(tool_dir)
        File.write(File.join(tool_dir, '1.0.yaml'), valid_profile_content)

        # Stub the search paths to include our temp directory
        allow(Ukiryu::Tool).to receive(:bundled_definition_search_paths).and_return([bundled_path])
      end

      it 'loads the tool from bundled location' do
        tool = Ukiryu::Tool.from_bundled(:test_tool)

        expect(tool).to be_a(Ukiryu::Tool)
        expect(tool.name).to eq('test_tool')
      end
    end

    context 'when tool definition does not exist' do
      it 'returns nil' do
        allow(Ukiryu::Tool).to receive(:bundled_definition_search_paths).and_return([Dir.tmpdir])

        tool = Ukiryu::Tool.from_bundled(:nonexistent_tool)

        expect(tool).to be_nil
      end
    end

    context 'when bundled file has errors' do
      before do
        # Create temporary bundled directory with invalid YAML
        tool_dir = File.join(bundled_path, 'bad_tool')
        FileUtils.mkdir_p(tool_dir)
        File.write(File.join(tool_dir, '1.0.yaml'), invalid_yaml)

        allow(Ukiryu::Tool).to receive(:bundled_definition_search_paths).and_return([bundled_path])
      end

      it 'skips invalid files and continues searching' do
        # Should return nil since all files are invalid
        tool = Ukiryu::Tool.from_bundled(:bad_tool)

        expect(tool).to be_nil
      end
    end
  end

  describe '.validate_profile (private method)' do
    let(:tool_definition_class) { Ukiryu::Models::ToolDefinition }
    let(:loader) { Ukiryu::Definition::Loader }

    it 'validates a complete profile' do
      profile = tool_definition_class.from_hash(
        YAML.safe_load(valid_profile_content, permitted_classes: [Symbol])
      )

      expect do
        loader.send(:validate_profile, profile, :strict)
      end.not_to raise_error
    end

    it 'detects missing name' do
      profile = tool_definition_class.new
      profile.version = '1.0'
      profile.profiles = []

      expect do
        loader.send(:validate_profile, profile, :strict)
      end.to raise_error(Ukiryu::DefinitionValidationError, /Missing 'name' field/)
    end

    it 'detects missing version' do
      profile = tool_definition_class.new
      profile.name = 'test'
      profile.profiles = []

      expect do
        loader.send(:validate_profile, profile, :strict)
      end.to raise_error(Ukiryu::DefinitionValidationError, /Missing 'version' field/)
    end

    it 'detects missing or empty profiles' do
      profile = tool_definition_class.new
      profile.name = 'test'
      profile.version = '1.0'

      expect do
        loader.send(:validate_profile, profile, :strict)
      end.to raise_error(Ukiryu::DefinitionValidationError, /Missing 'profiles' field/)
    end
  end

  describe '.valid_uri? (private method)' do
    let(:loader) { Ukiryu::Definition::Loader }

    it 'returns true for valid HTTP URI' do
      expect(loader.send(:valid_uri?, 'http://example.com')).to be true
    end

    it 'returns true for valid HTTPS URI' do
      expect(loader.send(:valid_uri?, 'https://www.ukiryu.com/register/1.1/test/1.0')).to be true
    end

    it 'returns true for file:// URI' do
      expect(loader.send(:valid_uri?, 'file:///path/to/file.yaml')).to be true
    end

    it 'returns false for invalid URI' do
      expect(loader.send(:valid_uri?, 'not-a-uri')).to be false
      expect(loader.send(:valid_uri?, 'ftp://example.com')).to be false
    end
  end
end
