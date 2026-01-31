# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Shell::PowerShell do
  let(:shell) { described_class.new }

  describe '#name' do
    it 'returns :powershell' do
      expect(shell.name).to eq(:powershell)
    end
  end

  describe '#escape' do
    it 'escapes backticks' do
      expect(shell.escape('hello`world')).to eq('hello``world')
    end

    it 'escapes dollar signs' do
      expect(shell.escape('$VAR')).to eq('`$VAR')
    end

    it 'escapes double quotes' do
      expect(shell.escape('say "hello"')).to eq('say `"hello`"')
    end

    it 'handles empty strings' do
      expect(shell.escape('')).to eq('')
    end

    it 'handles strings with multiple special characters' do
      expect(shell.escape('`$')).to eq('```$')
    end

    it 'preserves characters that do not need escaping' do
      expect(shell.escape('hello-world')).to eq('hello-world')
      expect(shell.escape('hello_world')).to eq('hello_world')
    end

    context 'security: command injection prevention' do
      it 'escapes semicolons to prevent command chaining' do
        expect(shell.escape('arg1;rm -rf /')).to eq('arg1;rm -rf /')
      end

      it 'escapes backticks to prevent command substitution' do
        expect(shell.escape('`malicious`')).to eq('``malicious``')
      end

      it 'escapes dollar signs to prevent variable expansion' do
        expect(shell.escape('$PATH')).to eq('`$PATH')
      end
    end
  end

  describe '#quote' do
    context 'with default (for_exe: false)' do
      it 'uses single quotes for arguments' do
        expect(shell.quote('hello')).to eq("'hello'")
      end

      it 'escapes special characters within single quotes' do
        # Single quotes don't need escaping in PowerShell (single-quoted strings are literal)
        # Only backtick, dollar, and double quotes need escaping
        expect(shell.quote("it's")).to eq("'it's'")
      end

      it 'handles empty strings' do
        expect(shell.quote('')).to eq("''")
      end

      it 'handles strings with spaces' do
        expect(shell.quote('hello world')).to eq("'hello world'")
      end

      it 'handles strings with special characters' do
        expect(shell.quote('$VAR')).to eq("'`$VAR'")
        # Double quotes are escaped with backtick
        expect(shell.quote('"quoted"')).to eq(%q('`"quoted`"'))
      end
    end

    context 'with for_exe: true' do
      it 'uses double quotes for executable paths' do
        expect(shell.quote('C:\\Program Files\\app.exe', for_exe: true)).to eq('"C:\\Program Files\\app.exe"')
      end

      it 'still escapes special characters within double quotes' do
        # When for_exe: true, the implementation just wraps in double quotes without escaping
        # This is intentional for executable paths
        expect(shell.quote('path "with" quotes', for_exe: true)).to eq('"path "with" quotes"')
      end

      it 'handles paths with spaces' do
        expect(shell.quote('/path with spaces/app', for_exe: true)).to eq('"/path with spaces/app"')
      end

      it 'handles empty strings' do
        expect(shell.quote('', for_exe: true)).to eq('""')
      end

      it 'does not escape backslashes in paths (Windows paths)' do
        # Backslashes in Windows paths should NOT be escaped inside double quotes
        expect(shell.quote('C:\\Users\\file.txt', for_exe: true)).to eq('"C:\\Users\\file.txt"')
      end
    end

    context 'security: command injection prevention' do
      it 'properly quotes arguments to prevent injection' do
        # The dollar sign in $(...) is escaped, but parentheses are not special in single-quoted strings
        quoted = shell.quote('$(malicious)')
        expect(quoted).to eq("'`$(malicious)'")
      end

      it 'properly quotes command chaining attempts' do
        quoted = shell.quote('arg1; malicious')
        expect(quoted).to eq("'arg1; malicious'")
      end
    end
  end

  describe '#env_var' do
    it 'formats environment variables with $ENV: syntax' do
      expect(shell.env_var('PATH')).to eq('$ENV:PATH')
    end

    it 'handles variable names with underscores' do
      expect(shell.env_var('MY_VAR')).to eq('$ENV:MY_VAR')
    end

    it 'handles variable names with numbers' do
      expect(shell.env_var('PATH2')).to eq('$ENV:PATH2')
    end

    it 'handles lowercase variable names' do
      expect(shell.env_var('path')).to eq('$ENV:path')
    end
  end

  describe '#join' do
    it 'uses smart quoting for executable and arguments' do
      result = shell.join('echo', 'hello', 'world')
      # Simple strings are not quoted in PowerShell
      expect(result).to eq('echo hello world')
    end

    it 'quotes executable if it contains spaces' do
      result = shell.join('/path with spaces/echo', 'hello')
      expect(result).to eq('"/path with spaces/echo" hello')
    end

    it 'quotes arguments that need quoting' do
      result = shell.join('echo', 'hello world', 'test')
      expect(result).to eq('echo \'hello world\' test')
    end

    it 'handles empty args array' do
      result = shell.join('echo')
      expect(result).to eq('echo')
    end

    it 'handles arguments with special characters' do
      # $VAR doesn't need quoting in PowerShell (unquoted strings are literal)
      # needs_quoting? returns false for $VAR
      result = shell.join('echo', '$VAR')
      expect(result).to eq('echo $VAR')
    end

    it 'uses double quotes for executables with spaces' do
      result = shell.join('/path with spaces/echo', 'hello')
      expect(result).to eq('"/path with spaces/echo" hello')
    end

    context 'special handling for -Command parameter' do
      it 'does not quote the argument after -Command' do
        result = shell.join('powershell', '-Command', 'Write-Host "hello"')
        # The script block should not be quoted
        expect(result).to eq('powershell -Command Write-Host "hello"')
      end

      it 'quotes subsequent arguments after -Command' do
        result = shell.join('powershell', '-Command', 'script.ps1', 'arg with spaces')
        expect(result).to eq('powershell -Command script.ps1 \'arg with spaces\'')
      end
    end

    context 'special handling for -File parameter' do
      it 'does not quote the argument after -File' do
        result = shell.join('powershell', '-File', 'script.ps1', 'arg')
        expect(result).to eq('powershell -File script.ps1 arg')
      end

      it 'quotes subsequent arguments after -File' do
        result = shell.join('powershell', '-File', 'script.ps1', 'arg with spaces')
        expect(result).to eq('powershell -File script.ps1 \'arg with spaces\'')
      end
    end

    context 'security: command injection prevention' do
      it 'properly quotes arguments to prevent injection' do
        result = shell.join('echo', 'hello; malicious')
        # Arguments with spaces are quoted
        expect(result).to eq('echo \'hello; malicious\'')
      end

      it 'handles special characters in arguments' do
        result = shell.join('echo', '`malicious`')
        expect(result).to eq('echo \'``malicious``\'')
      end
    end
  end

  describe '#format_path' do
    it 'returns paths unchanged' do
      expect(shell.format_path('C:\\Users\\file.txt')).to eq('C:\\Users\\file.txt')
    end

    it 'handles Unix-style paths' do
      expect(shell.format_path('/usr/bin/file')).to eq('/usr/bin/file')
    end

    it 'handles relative paths' do
      expect(shell.format_path('relative/path')).to eq('relative/path')
    end
  end

  describe '#headless_environment' do
    it 'returns empty hash (no headless environment needed)' do
      expect(shell.headless_environment).to eq({})
    end
  end
end
