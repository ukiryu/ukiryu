# frozen_string_literal: true

require 'tempfile'
require_relative '../spec_helper'

RSpec.describe 'Ukiryu Tool Profiles Smoke Tests' do
  # These are smoke tests that verify each tool profile works correctly
  # Like Homebrew formula tests, they run simple commands to validate functionality

  let(:register_path) { ENV['UKIRYU_REGISTER'] }

  before do
    skip 'Set UKIRYU_REGISTER environment variable to run smoke tests' unless register_path && Dir.exist?(register_path)
    Ukiryu::Register.default_register_path = register_path
  end

  after do
    Ukiryu::Tool.clear_cache
  end

  describe 'Ghostscript' do
    let(:tool) { Ukiryu::Tool.find_by(:ghostscript) }

    it 'detects version' do
      skip 'Ghostscript not installed on Windows ARM64 (emulation timeout)' if Ukiryu::Platform.windows? && ENV['RUNNER_ARCH'] == 'ARM64'
      expect(tool).to be_available
      version = tool.version
      expect(version).to match(/\d+\.\d+/)
      puts "  Ghostscript version: #{version}"
    end

    it 'converts PDF to PNG' do
      skip 'Ghostscript not installed on Windows ARM64 (emulation timeout)' if Ukiryu::Platform.windows? && ENV['RUNNER_ARCH'] == 'ARM64'
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        test_pdf = File.join(tmpdir, 'test-smoke.pdf')
        test_png = File.join(tmpdir, 'test-smoke.png')

        # Create minimal PDF
        File.write(test_pdf,
                   "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n/Pages 2 0 R\n>>\nendobj\n2 0 obj\n<<\n/Type /Pages\n/Count 1\n/Kids [3 0 R]\n>>\nendobj\n3 0 obj\n<<\n/Type /Page\n/Parent 2 0 R\n/MediaBox [0 0 612 792]\n/Contents 4 0 R\n>>\nendobj\n4 0 obj\n<<\n/Length 44\n>>\nstream\nBT\n/F1 12 Tf\n100 700 Td\n(Test) Tj\nET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f\n0000000009 00000 n\n0000000058 00000 n\n0000000115 00000 n\n0000000206 00000 n\ntrailer\n<<\n/Size 5\n/Root 1 0 R\n>>\nstartxref\n293\n%%EOF")

        result = tool.execute(:convert,
                              inputs: [test_pdf],
                              output: test_png,
                              device: 'png16m',
                              quiet: true,
                              batch: true,
                              no_pause: true,
                              execution_timeout: 30)

        expect(result.success?).to be true
        expect(File.exist?(test_png)).to be true
      end
    end
  end

  describe 'bzip2' do
    # bzip2 has separate implementations: GNU and BusyBox
    # - Alpine Linux uses BusyBox bzip2 (minimal implementation)
    # - Debian/Ubuntu/macOS use GNU bzip2 (full implementation)

    let(:tool) do
      # Use the interface - the system will resolve to the correct implementation
      # (GNU on most systems, BusyBox on Alpine, etc.)
      Ukiryu::Tool.find_by(:bzip2)
    end

    it 'detects version' do
      skip 'bzip2 tools not installed on this system' unless tool&.available?

      version = tool.version
      expect(version).to match(/\d[\d.]+/)
      puts "  bzip2 version: #{version} (#{tool.name})"
    end

    it 'compresses and decompresses a file' do
      skip 'bzip2 tools not installed on this system' unless tool&.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-bzip2.txt')
        compressed_file = "#{test_file}.bz2"

        # Create test file
        File.write(test_file, 'Hello, World! ' * 100)

        # Compress
        compress_result = tool.execute(:compress,
                                       inputs: [test_file],
                                       execution_timeout: 30)
        expect(compress_result.success?).to be true
        expect(File.exist?(compressed_file)).to be true

        # Decompress
        decompress_result = tool.execute(:decompress,
                                         inputs: [compressed_file],
                                         keep: true,
                                         execution_timeout: 30)
        expect(decompress_result.success?).to be true

        # Verify content
        expect(File.read(test_file)).to eq('Hello, World! ' * 100)
      end
    end
  end

  describe 'gzip' do
    # gzip uses the unified interface - system resolves to correct implementation
    # (GNU on most systems, BusyBox on Alpine)
    let(:tool) do
      Ukiryu::Tool.find_by(:gzip)
    end

    it 'detects version' do
      skip 'gzip tools not installed on this system' unless tool&.available?

      version = tool.version
      expect(version).to match(/\d[\d.]+/)
      puts "  gzip version: #{version} (#{tool.name})"
    end

    it 'compresses and decompresses a file' do
      skip 'gzip tools not installed on this system' unless tool&.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-gzip.txt')
        compressed_file = "#{test_file}.gz"

        # Create test file
        File.write(test_file, 'Hello, World! ' * 100)

        # Compress
        compress_result = tool.execute(:compress,
                                       inputs: [test_file],
                                       execution_timeout: 30)
        expect(compress_result.success?).to be true
        expect(File.exist?(compressed_file)).to be true

        # Decompress using gunzip
        decompress_result = tool.execute(:decompress,
                                         inputs: [compressed_file],
                                         keep: true,
                                         execution_timeout: 30)
        expect(decompress_result.success?).to be true

        # Verify content
        expect(File.read(test_file)).to eq('Hello, World! ' * 100)
      end
    end
  end

  describe 'tar' do
    let(:tool) { Ukiryu::Tool.find_by(:tar) }

    it 'detects version' do
      expect(tool).to be_available

      result = `tar --version 2>&1`
      # macOS uses bsdtar, Linux uses GNU tar
      expect(result).to match(/[\d.]+/)
    end

    it 'creates and extracts an archive' do
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        old_pwd = Dir.pwd
        begin
          Dir.chdir(tmpdir)

          test_dir = 'test-smoke-tar-dir'
          test_file = File.join(test_dir, 'test.txt')
          archive_file = 'test-smoke.tar'
          extract_dir = 'test-smoke-extract'

          # Create test directory and file
          FileUtils.mkdir_p(test_dir)
          File.write(test_file, 'Hello, Tar!')

          # Create archive
          create_result = tool.execute(:create,
                                       inputs: [test_dir],
                                       file: archive_file,
                                       execution_timeout: 30)
          expect(create_result.success?).to be true
          expect(File.exist?(archive_file)).to be true

          # Extract archive (use Dir.chdir for bsdtar)
          FileUtils.mkdir_p(extract_dir)
          Dir.chdir(extract_dir) do
            extract_result = tool.execute(:extract, file: "../#{archive_file}", execution_timeout: 30)
            expect(extract_result.success?).to be true
          end

          # Verify extracted content
          extracted_file = File.join(extract_dir, test_dir, 'test.txt')
          expect(File.exist?(extracted_file)).to be true
          expect(File.read(extracted_file)).to eq('Hello, Tar!')
        ensure
          Dir.chdir(old_pwd)
        end
      end
    end
  end

  describe 'unzip' do
    let(:tool) { Ukiryu::Tool.find_by(:unzip) }

    it 'detects version' do
      expect(tool).to be_available

      result = `unzip -v 2>&1`
      expect(result).to match(/UnZip [\d.]+/)
    end

    it 'lists and extracts a zip archive' do
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        old_pwd = Dir.pwd
        begin
          Dir.chdir(tmpdir)

          test_file = 'test-smoke-zip.txt'
          zip_file = 'test-smoke.zip'
          extract_dir = 'test-smoke-unzip'

          # Create test file and zip it
          File.write(test_file, 'Hello, Zip!')
          `zip #{zip_file} #{test_file} 2>&1`

          expect(File.exist?(zip_file)).to be true

          # List archive
          list_result = tool.execute(:extract,
                                     zipfile: zip_file,
                                     list: true,
                                     execution_timeout: 30)
          expect(list_result.success?).to be true

          # Extract archive
          FileUtils.mkdir_p(extract_dir)
          extract_result = tool.execute(:extract,
                                        zipfile: zip_file,
                                        directory: extract_dir,
                                        execution_timeout: 30)
          expect(extract_result.success?).to be true

          # Verify extracted content
          extracted_file = File.join(extract_dir, test_file)
          expect(File.exist?(extracted_file)).to be true
          expect(File.read(extracted_file)).to eq('Hello, Zip!')
        ensure
          Dir.chdir(old_pwd)
        end
      end
    end
  end

  describe 'sort' do
    let(:tool) { Ukiryu::Tool.find_by(:sort) }

    it 'detects version' do
      expect(tool).to be_available

      result = `sort --version 2>&1`
      # macOS sort has different format
      expect(result).to match(/[\d.]+/)
    end

    it 'sorts input lines' do
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-sort.txt')
        output_file = File.join(tmpdir, 'test-smoke-sorted.txt')

        # Create test file with unsorted lines
        File.write(test_file, "zebra\napple\nbanana\ncherry\n")

        # Sort
        result = tool.execute(:sort,
                              inputs: [test_file],
                              output: output_file,
                              execution_timeout: 30)
        expect(result.success?).to be true

        # Verify sorted content
        content = File.read(output_file)
        expect(content).to eq("apple\nbanana\ncherry\nzebra\n")
      end
    end

    it 'sorts numerically' do
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-numeric.txt')
        output_file = File.join(tmpdir, 'test-smoke-numeric-sorted.txt')

        # Create test file with unsorted numbers
        File.write(test_file, "100\n20\n5\n1000\n")

        # Sort numerically
        result = tool.execute(:sort,
                              inputs: [test_file],
                              output: output_file,
                              numeric_sort: true,
                              execution_timeout: 30)
        expect(result.success?).to be true

        # Verify sorted content
        content = File.read(output_file)
        expect(content).to eq("5\n20\n100\n1000\n")
      end
    end
  end

  describe 'pdf2ps' do
    let(:tool) { Ukiryu::Tool.find_by(:pdf2ps) }

    it 'detects version' do
      skip 'pdf2ps is Unix-only (not available on Windows)' if Ukiryu::Platform.windows?
      expect(tool).to be_available

      # pdf2ps uses -v - to show Ghostscript version
      result = `pdf2ps -v - 2>&1`
      expect(result).to match(/[\d.]+/)
    end

    it 'converts PDF to PostScript' do
      skip 'pdf2ps is Unix-only (not available on Windows)' if Ukiryu::Platform.windows?
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        old_pwd = Dir.pwd
        begin
          Dir.chdir(tmpdir)

          test_pdf = 'test-smoke-pdf2ps.pdf'
          test_ps = 'test-smoke-pdf2ps.ps'

          # Create minimal PDF
          File.write(test_pdf,
                     "%PDF-1.4\n1 0 obj\n<<\n/Type /Catalog\n/Pages 2 0 R\n>>\nendobj\n2 0 obj\n<<\n/Type /Pages\n/Count 1\n/Kids [3 0 R]\n>>\nendobj\n3 0 obj\n<<\n/Type /Page\n/Parent 2 0 R\n/MediaBox [0 0 612 792]\n/Contents 4 0 R\n>>\nendobj\n4 0 obj\n<<\n/Length 44\n>>\nstream\nBT\n/F1 12 Tf\n100 700 Td\n(Test) Tj\nET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f\n0000000009 00000 n\n0000000058 00000 n\n0000000115 00000 n\n0000000206 00000 n\ntrailer\n<<\n/Size 5\n/Root 1 0 R\n>>\nstartxref\n293\n%%EOF")

          result = tool.execute(:convert,
                                input: test_pdf,
                                output: test_ps,
                                execution_timeout: 30)

          expect(result.success?).to be true
          expect(File.exist?(test_ps)).to be true

          # Verify it's a PostScript file
          content = File.read(test_ps)
          expect(content).to include('%!PS-Adobe')
        ensure
          Dir.chdir(old_pwd)
        end
      end
    end
  end

  describe 'FFmpeg' do
    let(:tool) { Ukiryu::Tool.find_by(:ffmpeg) }

    it 'detects version' do
      skip 'FFmpeg not available on this system' unless tool&.available?

      expect(tool).to be_available
      version = tool.version
      expect(version).to match(/\d+\.\d+/)
      puts "  FFmpeg version: #{version}"
    end
  end

  describe 'exiftool' do
    let(:tool) { Ukiryu::Tool.find_by(:exiftool) }

    it 'detects version' do
      expect(tool).to be_available

      version = tool.version
      expect(version).to match(/\d+\.\d+/)
      puts "  exiftool version: #{version}"
    end

    it 'reads metadata from file' do
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-exiftool.txt')
        File.write(test_file, 'Hello, World!')

        result = tool.execute(:read,
                              inputs: [test_file],
                              execution_timeout: 30)

        expect(result.success?).to be true
        expect(result.stdout).not_to be_empty
      end
    end
  end

  describe 'ping_bsd' do
    let(:tool) { Ukiryu::Tool.find_by(:ping) }

    it 'pings localhost' do
      skip 'ping_bsd is BSD-only (not available on Linux or Windows)' if Ukiryu::Platform.linux? || Ukiryu::Platform.windows?
      expect(tool).to be_available

      # Verify we got the BSD implementation on BSD systems
      skip 'Not on BSD platform' unless Ukiryu::Platform.macos? || Ukiryu::Platform.freebsd?
      expect(tool.name).to eq('ping_bsd')

      result = tool.execute(:ping,
                            host: 'localhost',
                            count: 1,
                            execution_timeout: 30)

      expect(result.success?).to be true
      expect(result.stdout).to include('localhost')
    end
  end

  describe 'ping' do
    it 'pings localhost' do
      # Tool.find_by auto-selects the correct implementation (ping_gnu on Linux, ping_bsd on macOS/BSD)
      # based on platform compatibility defined in the tool profiles
      tool = Ukiryu::Tool.find_by(:ping)
      expect(tool).to be_available

      result = tool.execute(:ping,
                            host: 'localhost',
                            count: 1,
                            execution_timeout: 30)

      expect(result.success?).to be true
      # On Windows, ping resolves localhost to the actual hostname
      # On Unix-like systems, the output contains "localhost"
      if Ukiryu::Platform.windows?
        # Windows ping output contains "Pinging" which indicates success
        expect(result.stdout).to match(/Pinging|Reply from/)
      else
        expect(result.stdout).to include('localhost')
      end
    end
  end

  describe 'jq' do
    let(:tool) { Ukiryu::Tool.find_by(:jq) }

    it 'detects version' do
      expect(tool).to be_available

      result = `jq --version 2>&1`
      expect(result).to match(/jq-[\d.]+/)
    end

    it 'processes JSON' do
      expect(tool).to be_available

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-jq.json')
        File.write(test_file, '{"foo": "bar", "baz": [1, 2, 3]}')

        result = tool.execute(:process,
                              filter: '.',
                              inputs: [test_file],
                              execution_timeout: 30)

        expect(result.success?).to be true
        expect(result.stdout).to include('foo')
        expect(result.stdout).to include('bar')
      end
    end
  end

  describe 'yq' do
    let(:tool) { Ukiryu::Tool.find_by(:yq) }

    it 'detects version' do
      expect(tool).to be_available

      result = `yq --version 2>&1`
      # Only match mikefarah/yq which includes version info
      # Formats:
      # - "yq (https://github.com/mikefarah/yq/) version v4.50.1" (homebrew)
      # - "yq version v4.44.3" (binary download)
      # - "yq 3.4.3" (APT/APK package)
      # The jq wrapper (impostor) outputs "yq 0.0.0" without version info
      skip 'jq wrapper impostor detected (not mikefarah/yq)' if result.strip == 'yq 0.0.0'
      # Match both with and without "version" word, and with or without v prefix
      expect(result).to match(/yq(?:.*version.*v?[\d.]+| [\d.]+)/)
    end

    it 'evaluates YAML expression' do
      expect(tool).to be_available

      # Skip for jq wrapper impostor which doesn't support yq's eval subcommand
      result = `yq --version 2>&1`
      skip 'jq wrapper impostor detected (not mikefarah/yq)' if result.strip == 'yq 0.0.0'

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-yq.yaml')
        File.write(test_file, "foo:\n  bar: baz\n")

        result = tool.execute(:eval_all,
                              expression: '.foo.bar',
                              inputs: [test_file],
                              raw_output: true,
                              execution_timeout: 30)

        expect(result.success?).to be true
        # Some yq installations (like the jq wrapper on Ubuntu) may return
        # quoted strings. Strip surrounding quotes if present.
        output = result.stdout.strip.gsub(/^"|"$/, '')
        expect(output).to eq('baz')
      end
    end
  end

  describe 'Ping (platform-independent)' do
    it 'resolves to platform-specific implementation' do
      tool = Ukiryu::Tool.find_by(:ping)
      expect(tool).to be_available

      # On macOS, should resolve to ping_bsd
      # On Linux, should resolve to ping_gnu
      # On Windows, should resolve to ping_windows
      expect(tool.name).to match(/ping_(bsd|gnu|windows)/)
    end

    it 'pings localhost' do
      tool = Ukiryu::Tool.find_by(:ping)
      expect(tool).to be_available

      result = tool.execute(:ping,
                            host: 'localhost',
                            count: 1,
                            execution_timeout: 30)

      expect(result.success?).to be true
      # On Windows, ping resolves localhost to the actual hostname
      # On Unix-like systems, the output contains "localhost"
      if Ukiryu::Platform.windows?
        # Windows ping output contains "Pinging" which indicates success
        expect(result.stdout).to match(/Pinging|Reply from/)
      else
        expect(result.stdout).to include('localhost')
      end
    end
  end
end
