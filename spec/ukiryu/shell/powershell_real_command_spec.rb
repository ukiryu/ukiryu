# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'PowerShell Real Command Integration', if: system('which pwsh > /dev/null 2>&1') do
  let(:shell) { Ukiryu::Shell::PowerShell.new }
  let(:env) { Ukiryu::Environment.system }

  describe 'End-to-end command execution with Ghostscript-style args' do
    it 'correctly passes -sDEVICE=pdfwrite style arguments' do
      # This is the exact pattern Vectory uses with Ghostscript
      args = [
        '-sDEVICE=pdfwrite',
        '-sOutputFile=output.pdf',
        '-dBATCH',
        '-dNOPAUSE',
        'input.eps'
      ]

      result = shell.execute_command('echo', args, env, 30, nil)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include('-sDEVICE=pdfwrite')
      expect(result[:stdout]).to include('-sOutputFile=output.pdf')
      expect(result[:stdout]).to include('-dBATCH')
      expect(result[:stdout]).to include('-dNOPAUSE')
      expect(result[:stdout]).to include('input.eps')

      # Ensure the full arguments are present (prefix not stripped)
      expect(result[:stdout]).to match(/-sDEVICE=pdfwrite/)
      expect(result[:stdout]).to match(/-sOutputFile=output.pdf/)

      # Ensure we don't see arguments that start with = (prefix stripped)
      # This would indicate the -sDEVICE prefix was stripped
      expect(result[:stdout]).not_to match(/\s=pdfwrite\s/)
      expect(result[:stdout]).not_to match(/\s=output\.pdf\s/)
    end

    it 'handles multiple consecutive dash-prefixed args' do
      args = ['-a', '-b', '-c=value', '-d:value', 'file.txt']
      result = shell.execute_command('echo', args, env, 30, nil)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include('-a')
      expect(result[:stdout]).to include('-b')
      expect(result[:stdout]).to include('-c=value')
      expect(result[:stdout]).to include('-d:value')
    end

    it 'handles dash-prefixed args with spaces in values' do
      args = ['-sOutputFile=C:/Program Files/output.pdf', 'input.eps']
      result = shell.execute_command('echo', args, env, 30, nil)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include('-sOutputFile=C:/Program Files/output.pdf')
    end
  end

  describe 'Command line building via join()' do
    it 'produces correct command line for Ghostscript-style args' do
      cmd = shell.join(
        'C:/Program Files/gs/gs10.00.0/bin/gswin64c.exe',
        '-sDEVICE=pdfwrite',
        '-sOutputFile=output.pdf',
        '-dBATCH',
        'input.eps'
      )

      # All dash-prefixed args should be quoted
      expect(cmd).to include('"-sDEVICE=pdfwrite"')
      expect(cmd).to include('"-sOutputFile=output.pdf"')
      expect(cmd).to include('"-dBATCH"')

      # Simple arg should not be quoted
      expect(cmd).to include(' input.eps')

      # Should NOT contain stripped prefixes (standalone = without the - prefix)
      expect(cmd).not_to match(/\s=pdfwrite\b/)
      expect(cmd).not_to match(/\s=output\.pdf\b/)
    end

    it 'handles executable paths with spaces' do
      cmd = shell.join('C:/Program Files/gs/gswin64c.exe', '-sDEVICE=pdfwrite')

      # Executable path should be quoted
      expect(cmd).to include('"C:/Program Files/gs/gswin64c.exe"')

      # Dash-prefixed arg should be quoted
      expect(cmd).to include('"-sDEVICE=pdfwrite"')
    end
  end

  describe 'Tool integration with Ghostscript profile' do
    let(:ghostscript_profile) { 'spec/fixtures/profiles/ghostscript_10.0.yaml' }

    it 'builds correct args through Tool#build_args' do
      skip 'Ghostscript profile not found' unless File.exist?(ghostscript_profile)

      tool = Ukiryu::Tool.from_file(ghostscript_profile, platform: :windows, shell: :powershell)

      command = tool.command_definition(:convert)
      params = { device: 'pdfwrite', output: 'output.pdf', inputs: ['input.eps'] }

      args = tool.build_args(command, params)

      # Verify args are correct
      expect(args).to be_an(Array)
      expect(args).to include('-sDEVICE=pdfwrite')
      expect(args).to include('-sOutputFile=output.pdf')

      # Each arg should be a String, not an Array
      args.each do |arg|
        expect(arg).to be_a(String), "Expected String, got #{arg.class}: #{arg.inspect}"
      end
    end
  end

  describe 'Edge cases that could cause prefix stripping' do
    it 'handles args passed as nested arrays (should be flattened)' do
      # This simulates what might happen if someone passes args incorrectly
      nested_args = [['-sDEVICE=pdfwrite', 'input.eps']]

      # When nested arrays are passed to join, they get stringified
      # This is the problematic behavior we need to detect
      cmd = shell.join('gswin64c.exe', *nested_args)

      # The nested array becomes a string like '["-sDEVICE=pdfwrite", "input.eps"]'
      # which is NOT what we want
      # This test documents the current behavior - we should NOT have nested arrays
      expect(cmd).to include('[') # Array stringification
    end

    it 'correctly handles flat args vs nested args' do
      flat_args = ['-sDEVICE=pdfwrite', 'input.eps']
      cmd_flat = shell.join('gswin64c.exe', *flat_args)

      # Flat args should NOT have array stringification
      expect(cmd_flat).not_to include('[')
      expect(cmd_flat).not_to include(']')
      expect(cmd_flat).to include('"-sDEVICE=pdfwrite"')
    end
  end
end
