# frozen_string_literal: true

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
    let(:tool) { Ukiryu::Tools::Ghostscript.new }

    it 'detects version' do
      skip 'Ghostscript not installed or profile not configured' unless tool.available?

      version = tool.version
      expect(version).to match(/\d+\.\d+/)
      puts "  Ghostscript version: #{version}"
    end

    it 'converts PDF to PNG' do
      skip 'Ghostscript not installed or profile not configured' unless tool.available?

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
                              no_pause: true)

        expect(result.success?).to be true
        expect(File.exist?(test_png)).to be true
      end
    end
  end

  describe 'bzip2' do
    let(:tool) { Ukiryu::Tools::Bzip2.new }

    it 'detects version' do
      skip 'bzip2 not installed' unless tool.available?

      result = `bzip2 --help 2>&1`

      # Handle possible encoding issues
      result = result.encode('UTF-8', invalid: :replace, undef: :replace) if result.respond_to?(:encode)
      expect(result).to match(/Version [\d.]+/)
    end

    it 'compresses and decompresses a file' do
      skip 'bzip2 not installed' unless tool.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-bzip2.txt')
        compressed_file = "#{test_file}.bz2"

        # Create test file
        File.write(test_file, 'Hello, World! ' * 100)

        # Compress
        compress_result = tool.execute(:compress,
                                       inputs: [test_file])
        expect(compress_result.success?).to be true
        expect(File.exist?(compressed_file)).to be true

        # Decompress
        decompress_result = tool.execute(:decompress,
                                         inputs: [compressed_file],
                                         keep: true)
        expect(decompress_result.success?).to be true

        # Verify content
        expect(File.read(test_file)).to eq('Hello, World! ' * 100)
      end
    end
  end

  describe 'gzip' do
    let(:tool) { Ukiryu::Tools::Gzip.new }

    it 'detects version' do
      skip 'gzip not installed' unless tool.available?

      result = `gzip --version 2>&1`
      expect(result).to match(/gzip [\d.]+/)
    end

    it 'compresses and decompresses a file' do
      skip 'gzip not installed' unless tool.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-gzip.txt')
        compressed_file = "#{test_file}.gz"

        # Create test file
        File.write(test_file, 'Hello, World! ' * 100)

        # Compress
        compress_result = tool.execute(:compress,
                                       inputs: [test_file])
        expect(compress_result.success?).to be true
        expect(File.exist?(compressed_file)).to be true

        # Decompress using gunzip
        decompress_result = tool.execute(:decompress,
                                         inputs: [compressed_file],
                                         keep: true)
        expect(decompress_result.success?).to be true

        # Verify content
        expect(File.read(test_file)).to eq('Hello, World! ' * 100)
      end
    end
  end

  describe 'tar' do
    let(:tool) { Ukiryu::Tools::Tar.new }

    it 'detects version' do
      skip 'tar not installed' unless tool.available?

      result = `tar --version 2>&1`
      # macOS uses bsdtar, Linux uses GNU tar
      expect(result).to match(/[\d.]+/)
    end

    it 'creates and extracts an archive' do
      skip 'tar not installed' unless tool.available?

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
                                       file: archive_file)
          expect(create_result.success?).to be true
          expect(File.exist?(archive_file)).to be true

          # Extract archive (use Dir.chdir for bsdtar)
          FileUtils.mkdir_p(extract_dir)
          Dir.chdir(extract_dir) do
            extract_result = tool.execute(:extract, file: "../#{archive_file}")
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
    let(:tool) { Ukiryu::Tools::Unzip.new }

    it 'detects version' do
      skip 'unzip not installed' unless tool.available?

      result = `unzip -v 2>&1`
      expect(result).to match(/UnZip [\d.]+/)
    end

    it 'lists and extracts a zip archive' do
      skip 'unzip not installed' unless tool.available?

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
                                     inputs: [zip_file],
                                     list: true)
          expect(list_result.success?).to be true

          # Extract archive
          FileUtils.mkdir_p(extract_dir)
          extract_result = tool.execute(:extract,
                                        inputs: [zip_file],
                                        output_dir: extract_dir)
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
    let(:tool) { Ukiryu::Tools::Sort.new }

    it 'detects version' do
      skip 'sort not installed' unless tool.available?

      result = `sort --version 2>&1`
      # macOS sort has different format
      expect(result).to match(/[\d.]+/)
    end

    it 'sorts input lines' do
      skip 'sort not installed' unless tool.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-sort.txt')
        output_file = File.join(tmpdir, 'test-smoke-sorted.txt')

        # Create test file with unsorted lines
        File.write(test_file, "zebra\napple\nbanana\ncherry\n")

        # Sort
        result = tool.execute(:sort,
                              inputs: [test_file],
                              output: output_file)
        expect(result.success?).to be true

        # Verify sorted content
        content = File.read(output_file)
        expect(content).to eq("apple\nbanana\ncherry\nzebra\n")
      end
    end

    it 'sorts numerically' do
      skip 'sort not installed' unless tool.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-numeric.txt')
        output_file = File.join(tmpdir, 'test-smoke-numeric-sorted.txt')

        # Create test file with unsorted numbers
        File.write(test_file, "100\n20\n5\n1000\n")

        # Sort numerically
        result = tool.execute(:sort,
                              inputs: [test_file],
                              output: output_file,
                              numeric_sort: true)
        expect(result.success?).to be true

        # Verify sorted content
        content = File.read(output_file)
        expect(content).to eq("5\n20\n100\n1000\n")
      end
    end
  end

  describe 'pdf2ps' do
    let(:tool) { Ukiryu::Tools::Pdf2ps.new }

    it 'detects version' do
      skip 'pdf2ps not installed' unless tool.available?

      # pdf2ps uses -v - to show Ghostscript version
      result = `pdf2ps -v - 2>&1`
      expect(result).to match(/[\d.]+/)
    end

    it 'converts PDF to PostScript' do
      skip 'pdf2ps not installed' unless tool.available?

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
                                output: test_ps)

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
    let(:tool) { Ukiryu::Tools::Ffmpeg.new }

    it 'detects version' do
      skip 'FFmpeg not installed' unless tool.available?

      version = tool.version
      expect(version).to match(/\d+\.\d+/)
      puts "  FFmpeg version: #{version}"
    end

    it 'has convert command defined' do
      skip 'FFmpeg not installed' unless tool.available?

      # Verify that FFmpeg has the convert command with proper options
      tool_def = tool.tool_definition
      expect(tool_def).not_to be_nil

      # Get the compatible profile
      profile = tool_def.compatible_profile
      expect(profile).not_to be_nil

      # Get the convert command
      convert_cmd = profile.command('convert')
      expect(convert_cmd).not_to be_nil

      # Check for essential options (stored as strings in YAML)
      expect(convert_cmd.options).to be_a(Array)

      option_names = convert_cmd.options.map { |opt| opt.name.to_sym }
      expect(option_names).to include(:codec)
      expect(option_names).to include(:video_codec)
      expect(option_names).to include(:audio_codec)
      expect(option_names).to include(:format)
      expect(option_names).to include(:duration)
    end
  end

  describe 'exiftool' do
    let(:tool) { Ukiryu::Tools::Exiftool.new }

    it 'detects version' do
      skip 'exiftool not installed' unless tool.available?

      version = tool.version
      expect(version).to match(/\d+\.\d+/)
      puts "  exiftool version: #{version}"
    end

    it 'reads metadata from file' do
      skip 'exiftool not installed' unless tool.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-exiftool.txt')
        File.write(test_file, 'Hello, World!')

        result = tool.execute(:read,
                              inputs: [test_file])

        expect(result.success?).to be true
        expect(result.stdout).not_to be_empty
      end
    end
  end

  describe 'ping_bsd' do
    let(:tool) { Ukiryu::Tools::PingBsd.new }

    it 'pings localhost' do
      skip 'ping_bsd not installed' unless tool.available?

      result = tool.execute(:ping,
                            host: 'localhost',
                            count: 1)

      expect(result.success?).to be true
      expect(result.stdout).to include('localhost')
    end
  end

  describe 'ping' do
    it 'pings localhost' do
      # Tool.find_by auto-selects the correct implementation (ping_gnu on Linux, ping_bsd on macOS/BSD)
      # based on platform compatibility defined in the tool profiles
      tool = Ukiryu::Tool.find_by(:ping)

      skip 'ping tool not installed' unless tool

      result = tool.execute(:ping,
                            host: 'localhost',
                            count: 1)

      expect(result.success?).to be true
      expect(result.stdout).to include('localhost')
    end
  end

  describe 'jq' do
    let(:tool) { Ukiryu::Tools::Jq.new }

    it 'detects version' do
      skip 'jq not installed' unless tool.available?

      result = `jq --version 2>&1`
      expect(result).to match(/jq-[\d.]+/)
    end

    it 'processes JSON' do
      skip 'jq not installed' unless tool.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-jq.json')
        File.write(test_file, '{"foo": "bar", "baz": [1, 2, 3]}')

        result = tool.execute(:process,
                              filter: '.',
                              inputs: [test_file])

        expect(result.success?).to be true
        expect(result.stdout).to include('foo')
        expect(result.stdout).to include('bar')
      end
    end
  end

  describe 'yq' do
    let(:tool) { Ukiryu::Tools::Yq.new }

    it 'detects version' do
      skip 'yq not installed' unless tool.available?

      result = `yq --version 2>&1`
      expect(result).to match(/version v[\d.]+/)
    end

    it 'evaluates YAML expression' do
      skip 'yq not installed' unless tool.available?

      Dir.mktmpdir do |tmpdir|
        test_file = File.join(tmpdir, 'test-smoke-yq.yaml')
        File.write(test_file, "foo:\n  bar: baz\n")

        result = tool.execute(:eval,
                              expression: '.foo.bar',
                              inputs: [test_file])

        expect(result.success?).to be true
        expect(result.stdout.strip).to eq('baz')
      end
    end
  end

  describe 'Ping (platform-independent)' do
    it 'resolves to platform-specific implementation' do
      tool = Ukiryu::Tools::Ping.new
      skip 'ping not installed' unless tool.available?

      # On macOS, should resolve to ping_bsd
      # On Linux, should resolve to ping_gnu
      expect(tool.name).to match(/ping_(bsd|gnu)/)
    end

    it 'pings localhost' do
      tool = Ukiryu::Tools::Ping.new
      skip 'ping not installed' unless tool.available?

      result = tool.execute(:ping,
                            host: 'localhost',
                            count: 1)

      expect(result.success?).to be true
      expect(result.stdout).to include('localhost')
    end
  end
end
