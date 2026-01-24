# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::DocumentationGenerator do
  describe '.generate' do
    let(:definition) do
      {
        name: 'test-tool',
        version: '1.0.0',
        description: 'A test tool for documentation',
        homepage: 'https://example.com/test-tool',
        profiles: [{
          name: 'default',
          platforms: %i[macos linux],
          shells: %i[bash zsh],
          commands: {
            convert: {
              description: 'Convert files',
              arguments: [
                { name: 'input', type: 'file', description: 'Input file', required: true },
                { name: 'output', type: 'file', description: 'Output file' }
              ],
              options: [
                { name: 'quality', cli: '--quality', type: 'integer', description: 'Quality level' }
              ],
              flags: [
                { name: 'verbose', cli: '--verbose', description: 'Verbose output' }
              ]
            }
          }
        }]
      }
    end

    context 'with markdown format' do
      it 'generates markdown documentation' do
        result = described_class.generate(definition, format: :markdown)
        expect(result).to include('# test-tool')
        expect(result).to include('Version: 1.0.0')
        expect(result).to include('A test tool for documentation')
        expect(result).to include('## Commands')
        expect(result).to include('### `convert`')
      end

      it 'includes platform information' do
        result = described_class.generate(definition, format: :markdown)
        expect(result).to include('Supported Platforms')
        expect(result).to include('**Macos**')
        expect(result).to include('**Linux**')
      end

      it 'includes command arguments' do
        result = described_class.generate(definition, format: :markdown)
        expect(result).to include('#### Arguments')
        expect(result).to include('**`input`**')
        expect(result).to include('**`output`**')
      end

      it 'includes options and flags' do
        result = described_class.generate(definition, format: :markdown)
        expect(result).to include('--quality')
        expect(result).to include('--verbose')
      end
    end

    context 'with asciidoc format' do
      it 'generates asciidoc documentation' do
        result = described_class.generate(definition, format: :asciidoc)
        expect(result).to include('= test-tool')
        expect(result).to include('== Overview')
        expect(result).to include('== Commands')
        expect(result).to include('=== `convert`')
      end
    end

    context 'with unsupported format' do
      it 'raises error' do
        expect do
          described_class.generate(definition, format: :pdf)
        end.to raise_error(ArgumentError, /Unsupported format/)
      end
    end

    context 'with minimal definition' do
      it 'handles missing optional fields' do
        minimal_def = { name: 'minimal' }
        result = described_class.generate(minimal_def, format: :markdown)
        expect(result).to include('# minimal')
      end
    end
  end

  describe '.generate_to_file' do
    let(:tmp_path) { 'spec/fixtures/tmp/docs.md' }

    before do
      FileUtils.mkdir_p('spec/fixtures/tmp')
    end

    after do
      FileUtils.rm_rf('spec/fixtures/tmp') if File.exist?('spec/fixtures/tmp')
    end

    it 'writes documentation to file' do
      definition = { name: 'test' }
      described_class.generate_to_file(definition, tmp_path, format: :markdown)
      expect(File.exist?(tmp_path)).to be true
      content = File.read(tmp_path)
      expect(content).to include('# test')
    end
  end

  describe '.generate_command_docs' do
    let(:command_def) do
      {
        description: 'Test command',
        arguments: [
          { name: 'input', type: 'file', required: true }
        ]
      }
    end

    context 'with markdown format' do
      it 'generates command documentation' do
        result = described_class.generate_command_docs('test', command_def, format: :markdown)
        expect(result).to include('### `test`')
        expect(result).to include('Test command')
        expect(result).to include('#### Arguments')
      end
    end

    context 'with asciidoc format' do
      it 'generates command documentation' do
        result = described_class.generate_command_docs('test', command_def, format: :asciidoc)
        expect(result).to include('=== `test`')
        expect(result).to include('Test command')
        expect(result).to include('==== Arguments')
      end
    end
  end
end
