# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Ghostscript Tool Profile' do
  include ToolHelper

  before(:each) do
    @temp_dir = create_temp_dir
  end

  after(:each) do
    # Clean up temp directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  # Create a simple EPS file for testing
  # @param path [String] the path to create the EPS file at
  def create_test_eps(path)
    eps_content = <<~EPS
      %!PS-Adobe-3.0 EPSF-3.0
      %%BoundingBox: 0 0 100 100
      %%EndComments
      newpath
      0 0 moveto
      100 0 lineto
      100 100 lineto
      0 100 lineto
      closepath
      0 setgray
      fill
      showpage
      %%EOF
    EPS
    File.write(path, eps_content)
    path
  end

  describe 'tool availability' do
    it 'detects Ghostscript on the system' do
      skip_unless_tool_available(:ghostscript)

      tool = get_tool(:ghostscript)
      expect(tool.available?).to be true
      # Ghostscript executable names vary by platform
      # Unix: gs, ghostscript
      # Windows: gswin64c, gswin32c
      expect(tool.executable).to match(/gs|ghostscript/i)
    end
  end

  describe 'convert command' do
    before(:each) { skip_unless_tool_available(:ghostscript) }

    it 'converts EPS to PDF with -sDEVICE=pdfwrite' do
      input = File.join(@temp_dir, 'input.eps')
      output = File.join(@temp_dir, 'output.pdf')

      create_test_eps(input)

      tool = get_tool(:ghostscript)
      result = tool.execute(:convert,
                            execution_timeout: 60,
                            inputs: [input],
                            device: :pdfwrite,
                            output: output,
                            batch: true,
                            no_pause: true,
                            quiet: true)

      expect(result.success?).to be true
      expect(result.exit_code).to eq(0)
      expect(File.exist?(output)).to be true
      # PDF should be at least 100 bytes (minimal valid PDF)
      expect(File.size(output)).to be > 100
    end

    it 'handles -sDEVICE=pdfwrite style arguments correctly on all shells' do
      # This test specifically verifies that the -sDEVICE=pdfwrite argument
      # is preserved correctly on ALL shells, including PowerShell.
      #
      # On Windows PowerShell, arguments starting with - can be stripped by
      # PowerShell's parameter binder. This test ensures the fix works by
      # verifying the command succeeds and produces valid output.
      input = File.join(@temp_dir, 'test.eps')
      output = File.join(@temp_dir, 'test.pdf')

      create_test_eps(input)

      tool = get_tool(:ghostscript)

      # Execute the command - if the -sDEVICE prefix was stripped,
      # Ghostscript would fail with an error about unknown device
      result = tool.execute(:convert,
                            execution_timeout: 60,
                            inputs: [input],
                            device: :pdfwrite,
                            output: output,
                            batch: true,
                            no_pause: true,
                            quiet: true)

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
      expect(File.size(output)).to be > 100
    end

    it 'converts with EPS crop option' do
      input = File.join(@temp_dir, 'cropped.eps')
      output = File.join(@temp_dir, 'cropped.pdf')

      create_test_eps(input)

      tool = get_tool(:ghostscript)
      result = tool.execute(:convert,
                            execution_timeout: 60,
                            inputs: [input],
                            device: :pdfwrite,
                            output: output,
                            batch: true,
                            no_pause: true,
                            quiet: true,
                            eps_crop: true)

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end

    it 'handles multiple dash-prefixed options correctly' do
      # Test multiple options that start with dashes
      # All should be preserved on all shells including PowerShell
      input = File.join(@temp_dir, 'multi.eps')
      output = File.join(@temp_dir, 'multi.pdf')

      create_test_eps(input)

      tool = get_tool(:ghostscript)

      result = tool.execute(:convert,
                            execution_timeout: 60,
                            inputs: [input],
                            device: :pdfwrite,
                            output: output,
                            batch: true,
                            no_pause: true,
                            quiet: true,
                            safer: true)

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end

    it 'handles path with spaces' do
      # Create subdirectory with space in name
      subdir = File.join(@temp_dir, 'sub dir')
      Dir.mkdir(subdir)
      input = File.join(subdir, 'space test.eps')
      output = File.join(subdir, 'space test.pdf')

      create_test_eps(input)

      tool = get_tool(:ghostscript)
      result = tool.execute(:convert,
                            execution_timeout: 60,
                            inputs: [input],
                            device: :pdfwrite,
                            output: output,
                            batch: true,
                            no_pause: true,
                            quiet: true)

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end
  end

  describe 'PowerShell-specific argument handling' do
    # These tests verify the fix for PowerShell parameter binding
    # which was stripping the -sDEVICE prefix from arguments
    #
    # PowerShell Core (pwsh) is cross-platform and available on Windows, macOS, and Linux.
    # These tests can run on any platform with PowerShell and Ghostscript installed.
    #
    # BUG FIX: PowerShell was not quoting dash-prefixed arguments,
    # causing PowerShell's parameter binder to strip the prefix.
    # Example: -sDEVICE=pdfwrite became =pdfwrite
    # See: lib/ukiryu/shell/powershell.rb

    before(:each) do
      skip_unless_tool_available(:ghostscript)
      # Skip if PowerShell is not available on this system
      skip 'PowerShell (pwsh) is not available' unless system('which pwsh > /dev/null 2>&1')
    end

    it 'preserves -sDEVICE=pdfwrite when forced to PowerShell shell' do
      # Set test shell to PowerShell
      original_test_shell = ENV['UKIRYU_TEST_SHELL']
      ENV['UKIRYU_TEST_SHELL'] = 'powershell'

      # Use the fixture register which has PowerShell in the shells list
      fixture_register = File.expand_path('../../fixtures/register', __dir__)

      begin
        # Clear shell and tool caches to force reload with PowerShell
        Ukiryu::Shell.reset
        Ukiryu::Tool.clear_cache

        # Set register path programmatically
        Ukiryu::Register.default_register_path = fixture_register

        input = File.join(@temp_dir, 'ps_test.eps')
        output = File.join(@temp_dir, 'ps_test.pdf')

        create_test_eps(input)

        tool = Ukiryu::Tool.get('ghostscript')

        # Verify PowerShell is being used
        expect(Ukiryu::Shell.detect).to eq(:powershell)

        result = tool.execute(:convert,
                              execution_timeout: 60,
                              inputs: [input],
                              device: :pdfwrite,
                              output: output,
                              batch: true,
                              no_pause: true,
                              quiet: true)

        expect(result.success?).to be true
        expect(File.exist?(output)).to be true
        expect(File.size(output)).to be > 100
      ensure
        # Restore original environment
        ENV['UKIRYU_TEST_SHELL'] = original_test_shell if original_test_shell
        ENV.delete('UKIRYU_TEST_SHELL') unless original_test_shell
        Ukiryu::Shell.reset
        Ukiryu::Tool.clear_cache
      end
    end
  end
end
