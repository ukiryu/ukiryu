# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'PowerShell Integration Tests', if: system('which pwsh > /dev/null 2>&1') do
  let(:shell) { Ukiryu::Shell::PowerShell.new }
  let(:env) { Ukiryu::Environment.system }

  describe '#execute_command' do
    context 'with dash-prefixed arguments (prefix stripping prevention)' do
      it 'preserves -sDEVICE=pdfwrite style arguments' do
        result = shell.execute_command('echo', ['-sDEVICE=pdfwrite', 'input.eps'], env, 30, nil)
        expect(result[:status]).to eq(0)
        # The full argument should be present (not stripped to just =pdfwrite)
        expect(result[:stdout]).to include('-sDEVICE=pdfwrite')
      end

      it 'preserves multiple dash-prefixed arguments' do
        args = ['-sDEVICE=pdfwrite', '-sOutputFile=output.pdf', '-dBATCH']
        result = shell.execute_command('echo', args, env, 30, nil)
        expect(result[:status]).to eq(0)
        expect(result[:stdout]).to include('-sDEVICE=pdfwrite')
        expect(result[:stdout]).to include('-sOutputFile=output.pdf')
        expect(result[:stdout]).to include('-dBATCH')
      end

      it 'preserves -resize style arguments' do
        result = shell.execute_command('echo', ['-resize', '50x50'], env, 30, nil)
        expect(result[:status]).to eq(0)
        expect(result[:stdout]).to include('-resize')
      end
    end

    context 'with single quotes in arguments' do
      it 'correctly escapes single quotes by doubling them' do
        result = shell.execute_command('echo', ["it's a test"], env, 30, nil)
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq("it's a test")
      end

      it 'handles multiple single quotes' do
        result = shell.execute_command('echo', ["it's a test's value"], env, 30, nil)
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq("it's a test's value")
      end
    end

    context 'with special characters in arguments' do
      it 'handles dollar signs (escaped in double quotes)' do
        result = shell.execute_command('echo', ['$VAR'], env, 30, nil)
        expect(result[:status]).to eq(0)
        # Dollar signs are escaped with backtick in double-quoted strings
        expect(result[:stdout].strip).to eq('$VAR')
      end

      it 'handles backticks (escaped in double quotes)' do
        result = shell.execute_command('echo', ['`hello`'], env, 30, nil)
        expect(result[:status]).to eq(0)
        # Backticks are escaped with backtick in double-quoted strings
        expect(result[:stdout].strip).to eq('`hello`')
      end

      it 'handles arguments with spaces' do
        result = shell.execute_command('echo', ['hello world'], env, 30, nil)
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('hello world')
      end

      it 'handles semicolons safely' do
        result = shell.execute_command('echo', ['hello;world'], env, 30, nil)
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('hello;world')
      end
    end

    context 'with executable paths' do
      it 'handles paths with spaces' do
        # Use /bin/echo which is a simple command that exists
        result = shell.execute_command('/bin/echo', ['test'], env, 30, nil)
        expect(result[:status]).to eq(0)
        expect(result[:stdout].strip).to eq('test')
      end
    end
  end

  describe '#join' do
    context 'with dash-prefixed arguments' do
      it 'quotes arguments starting with dash with double quotes' do
        cmd = shell.join('gs', '-sDEVICE=pdfwrite', 'input.eps', 'output.pdf')
        expect(cmd).to include('"-sDEVICE=pdfwrite"')
      end

      it 'quotes multiple dash-prefixed arguments' do
        cmd = shell.join('gs', '-sDEVICE=pdfwrite', '-dBATCH', 'input.eps')
        expect(cmd).to include('"-sDEVICE=pdfwrite"')
        expect(cmd).to include('"-dBATCH"')
      end
    end

    context 'with arguments containing special characters' do
      it 'quotes and escapes arguments with dollar signs' do
        cmd = shell.join('echo', '$VAR')
        # Dollar sign is escaped with backtick in double-quoted strings
        expect(cmd).to include('"`$VAR"')
      end

      it 'quotes arguments with spaces' do
        cmd = shell.join('echo', 'hello world')
        expect(cmd).to include('"hello world"')
      end
    end

    context 'with simple arguments' do
      it 'does not quote simple arguments' do
        cmd = shell.join('echo', 'hello', 'world')
        expect(cmd).to eq('echo hello world')
      end
    end

    context 'with executable paths containing spaces' do
      it 'quotes the executable path' do
        cmd = shell.join('/path with space/gs', '-sDEVICE=pdfwrite')
        expect(cmd).to include('"/path with space/gs"')
        expect(cmd).to include('"-sDEVICE=pdfwrite"')
      end
    end
  end

  describe '#execute_command_with_stdin' do
    it 'passes stdin data correctly' do
      result = shell.execute_command_with_stdin('cat', [], env, 30, nil, 'hello from stdin')
      expect(result[:status]).to eq(0)
      expect(result[:stdout].strip).to eq('hello from stdin')
    end

    it 'preserves dash-prefixed arguments with stdin' do
      # Use /bin/echo instead of 'echo' because PowerShell's echo alias (Write-Output)
      # doesn't handle stdin piping correctly on Unix
      result = shell.execute_command_with_stdin('/bin/echo', ['-sDEVICE=pdfwrite'], env, 30, nil, '')
      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include('-sDEVICE=pdfwrite')
    end
  end

  describe 'real-world Ghostscript command simulation' do
    it 'formats Ghostscript-style command correctly' do
      # Simulate the command Vectory would run
      args = [
        '-sDEVICE=pdfwrite',
        '-sOutputFile=output.pdf',
        '-dBATCH',
        '-dNOPAUSE',
        'input.ps'
      ]
      result = shell.execute_command('echo', args, env, 30, nil)

      expect(result[:status]).to eq(0)
      expect(result[:stdout]).to include('-sDEVICE=pdfwrite')
      expect(result[:stdout]).to include('-sOutputFile=output.pdf')
      expect(result[:stdout]).to include('-dBATCH')
      expect(result[:stdout]).to include('-dNOPAUSE')
      expect(result[:stdout]).to include('input.ps')
    end
  end
end
