# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::Sources::FileSource do
  let(:temp_dir) { Dir.mktmpdir('ukiryu-spec-') }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe '#initialize' do
    context 'with existing file' do
      it 'creates a source without error' do
        file_path = File.join(temp_dir, 'test.yaml')
        File.write(file_path, 'name: test')

        expect { described_class.new(file_path) }.not_to raise_error
      end

      it 'expands relative paths to absolute paths' do
        file_path = File.join(temp_dir, 'test.yaml')
        File.write(file_path, 'name: test')

        # Change to temp dir so relative path works
        Dir.chdir(temp_dir) do
          source = described_class.new('./test.yaml')
          expect(source.path).to eq(File.expand_path('./test.yaml'))
        end
      end

      it 'stores the file path' do
        file_path = File.join(temp_dir, 'test.yaml')
        File.write(file_path, 'name: test')

        source = described_class.new(file_path)
        expect(source.path).to eq(File.expand_path(file_path))
      end
    end

    context 'with non-existent file' do
      it 'raises DefinitionNotFoundError' do
        file_path = File.join(temp_dir, 'nonexistent.yaml')

        expect { described_class.new(file_path) }.to raise_error(
          Ukiryu::Errors::DefinitionNotFoundError,
          /Definition file not found: #{Regexp.escape(file_path)}/
        )
      end

      it 'includes the full path in error message' do
        file_path = File.join(temp_dir, 'nonexistent.yaml')

        expect { described_class.new(file_path) }.to raise_error do |error|
          expect(error.message).to include(File.expand_path(file_path))
        end
      end
    end

    context 'with unreadable file' do
      it 'raises DefinitionLoadError' do
        file_path = File.join(temp_dir, 'unreadable.yaml')
        File.write(file_path, 'name: test')
        File.chmod(0o000, file_path)

        # Skip on platforms where chmod may not work as expected
        skip 'File permissions test skipped on this platform' if Gem.win_platform?

        # Skip in Docker/CI environments where chmod 000 doesn't prevent owner reads
        skip 'File permissions test skipped in container environment' if ENV['CI'] || File.exist?('/.dockerenv')

        expect { described_class.new(file_path) }.to raise_error(
          Ukiryu::Errors::DefinitionLoadError,
          /not readable/
        )
      end
    end
  end

  describe '#load' do
    let(:file_path) { File.join(temp_dir, 'test.yaml') }
    let(:yaml_content) { 'name: test_tool\nversion: "1.0"' }

    before do
      File.write(file_path, yaml_content)
    end

    it 'returns the file content' do
      source = described_class.new(file_path)

      expect(source.load).to eq(yaml_content)
    end

    it 'sets the mtime on first load' do
      source = described_class.new(file_path)

      expect(source.mtime).to be_nil

      source.load

      expect(source.mtime).to be_a(Time)
    end

    it 'tracks file modification time' do
      source = described_class.new(file_path)
      original_mtime = File.mtime(file_path)

      source.load

      # Check that mtime is set and close to file mtime (within 2 seconds)
      expect(source.mtime).to be_a(Time)
      time_diff = (source.mtime - original_mtime).abs
      expect(time_diff).to be < 2
    end

    context 'when file is modified after init' do
      it 'raises DefinitionLoadError on subsequent load' do
        source = described_class.new(file_path)

        # First load should succeed
        source.load

        # Modify the file
        sleep 0.1 # Ensure different mtime
        File.write(file_path, 'name: modified')

        # Second load should fail
        expect { source.load }.to raise_error(
          Ukiryu::Errors::DefinitionLoadError,
          /has been modified since it was loaded/
        )
      end

      it 'includes both mtimes in error message' do
        source = described_class.new(file_path)

        source.load

        sleep 0.1
        File.write(file_path, 'name: modified')

        expect { source.load }.to raise_error do |error|
          expect(error.message).to match(/Original mtime:/)
          expect(error.message).to match(/Current mtime:/)
        end
      end
    end

    context 'with empty file' do
      it 'returns empty string' do
        empty_path = File.join(temp_dir, 'empty.yaml')
        File.write(empty_path, '')

        source = described_class.new(empty_path)

        expect(source.load).to eq('')
      end
    end
  end

  describe '#source_type' do
    it 'returns :file' do
      file_path = File.join(temp_dir, 'test.yaml')
      File.write(file_path, 'name: test')

      source = described_class.new(file_path)

      expect(source.source_type).to eq(:file)
    end
  end

  describe '#cache_key' do
    let(:file_path) { File.join(temp_dir, 'test.yaml') }

    before do
      File.write(file_path, 'name: test')
    end

    it 'includes file hash and mtime' do
      source = described_class.new(file_path)
      source.load # Set mtime

      cache_key = source.cache_key

      # Cache key format: file:{sha256}:{mtime}
      # Just verify it starts with the right prefix and has a valid structure
      expect(cache_key).to start_with('file:')
      # Verify it has multiple parts (file:hash:mtime with colons in mtime string)
      parts = cache_key.split(':')
      expect(parts.length).to be >= 3
      expect(parts[0]).to eq('file')
      # Second part should be a SHA256 hash
      expect(parts[1]).to match(/^[a-f0-9]{64}$/)
    end

    it 'generates consistent cache keys for same file state' do
      source1 = described_class.new(file_path)
      source2 = described_class.new(file_path)

      source1.load
      source2.load

      expect(source1.cache_key).to eq(source2.cache_key)
    end

    it 'generates different cache keys for different files' do
      file_path2 = File.join(temp_dir, 'test2.yaml')
      File.write(file_path2, 'name: test2')

      source1 = described_class.new(file_path)
      source2 = described_class.new(file_path2)

      source1.load
      source2.load

      expect(source1.cache_key).not_to eq(source2.cache_key)
    end

    it 'generates different cache keys when file is modified' do
      source = described_class.new(file_path)
      source.load

      original_key = source.cache_key

      # Modify file and create new source
      # Touch file to ensure mtime changes
      sleep 1.1 # Ensure at least 1 second difference
      File.write(file_path, 'name: modified')
      source2 = described_class.new(file_path)
      source2.load

      # Cache keys should be different due to different content and mtime
      expect(original_key).not_to eq(source2.cache_key)
    end
  end

  describe '#real_path' do
    it 'returns the real path resolving symlinks' do
      file_path = File.join(temp_dir, 'real.yaml')
      File.write(file_path, 'name: test')

      source = described_class.new(file_path)

      expect(source.real_path).to eq(File.realpath(file_path))
    end

    it 'handles regular files' do
      file_path = File.join(temp_dir, 'regular.yaml')
      File.write(file_path, 'name: test')

      source = described_class.new(file_path)

      expect(source.real_path).to eq(File.realpath(file_path))
    end
  end

  describe 'with YAML content' do
    it 'can load valid YAML' do
      file_path = File.join(temp_dir, 'valid.yaml')
      yaml_content = <<~YAML
        name: test_tool
        version: "1.0"
        profiles:
          - name: default
            platforms: [linux]
            shells: [bash]
      YAML

      File.write(file_path, yaml_content)
      source = described_class.new(file_path)

      # File.read returns the exact content, which may have trailing newline
      expect(source.load).to eq(yaml_content)
    end

    it 'preserves YAML formatting' do
      file_path = File.join(temp_dir, 'formatted.yaml')
      yaml_content = "name: test\nversion: \"1.0\"\nprofiles:\n  - name: default"

      File.write(file_path, yaml_content)
      source = described_class.new(file_path)

      expect(source.load).to eq(yaml_content)
    end
  end
end
