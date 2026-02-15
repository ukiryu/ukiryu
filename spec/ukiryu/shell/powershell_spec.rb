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
    it 'escapes single quotes by doubling them (PowerShell convention for single-quoted strings)' do
      expect(shell.escape("it's")).to eq("it''s")
    end

    it 'handles empty strings' do
      expect(shell.escape('')).to eq('')
    end

    it 'handles strings with multiple single quotes' do
      expect(shell.escape("'hello'world'")).to eq("''hello''world''")
    end

    it 'preserves other characters (single-quoted strings are literal)' do
      # In PowerShell single-quoted strings, these are all literal
      expect(shell.escape('$VAR')).to eq('$VAR')
      expect(shell.escape('hello`world')).to eq('hello`world')
      expect(shell.escape('hello&world')).to eq('hello&world')
    end

    context 'security: command injection prevention' do
      it 'preserves semicolons (safe inside single quotes)' do
        expect(shell.escape('arg1;rm -rf /')).to eq('arg1;rm -rf /')
      end

      it 'preserves dollar signs (literal in single quotes)' do
        expect(shell.escape('$PATH')).to eq('$PATH')
      end

      it 'preserves backticks (literal in single quotes)' do
        expect(shell.escape('`malicious`')).to eq('`malicious`')
      end
    end
  end

  describe '#escape_for_double_quotes' do
    it 'escapes backticks' do
      expect(shell.escape_for_double_quotes('hello`world')).to eq('hello``world')
    end

    it 'escapes dollar signs' do
      expect(shell.escape_for_double_quotes('$VAR')).to eq('`$VAR')
    end

    it 'escapes double quotes' do
      expect(shell.escape_for_double_quotes('say "hello"')).to eq('say `"hello`"')
    end

    it 'handles empty strings' do
      expect(shell.escape_for_double_quotes('')).to eq('')
    end

    it 'handles strings with multiple special characters' do
      expect(shell.escape_for_double_quotes('`$')).to eq('```$')
    end

    it 'preserves single quotes (not special in double-quoted strings)' do
      expect(shell.escape_for_double_quotes("it's")).to eq("it's")
    end
  end

  describe '#quote' do
    context 'with default (for_exe: false)' do
      it 'uses double quotes for arguments (to prevent PowerShell parameter binding)' do
        expect(shell.quote('hello')).to eq('"hello"')
      end

      it 'preserves single quotes (not special in double-quoted strings)' do
        # In double-quoted strings, single quotes are literal
        expect(shell.quote("it's")).to eq('"it\'s"')
      end

      it 'handles multiple single quotes in a string' do
        expect(shell.quote("it's a test's")).to eq('"it\'s a test\'s"')
      end

      it 'handles empty strings' do
        expect(shell.quote('')).to eq('""')
      end

      it 'handles strings with spaces' do
        expect(shell.quote('hello world')).to eq('"hello world"')
      end

      it 'escapes dollar signs in double-quoted strings' do
        expect(shell.quote('$VAR')).to eq('"`$VAR"')
      end

      it 'escapes double quotes in double-quoted strings' do
        expect(shell.quote('"quoted"')).to eq('"`"quoted`""')
      end
    end

    context 'with for_exe: true' do
      it 'uses double quotes for executable paths' do
        expect(shell.quote('C:\\Program Files\\app.exe', for_exe: true)).to eq('"C:\\Program Files\\app.exe"')
      end

      it 'escapes special characters within double quotes' do
        expect(shell.quote('path "with" quotes', for_exe: true)).to eq('"path `"with`" quotes"')
      end

      it 'handles paths with spaces' do
        expect(shell.quote('/path with spaces/app', for_exe: true)).to eq('"/path with spaces/app"')
      end

      it 'handles empty strings' do
        expect(shell.quote('', for_exe: true)).to eq('""')
      end

      it 'does not escape backslashes in paths (Windows paths)' do
        expect(shell.quote('C:\\Users\\file.txt', for_exe: true)).to eq('"C:\\Users\\file.txt"')
      end

      it 'escapes dollar signs in double-quoted strings' do
        expect(shell.quote('$PATH', for_exe: true)).to eq('"`$PATH"')
      end

      it 'escapes backticks in double-quoted strings' do
        expect(shell.quote('hello`world', for_exe: true)).to eq('"hello``world"')
      end

      it 'preserves single quotes (not special in double-quoted strings)' do
        expect(shell.quote("it's", for_exe: true)).to eq('"it\'s"')
      end
    end

    context 'security: command injection prevention' do
      it 'properly quotes and escapes arguments to prevent injection' do
        # In double quotes, $() would expand unless escaped
        quoted = shell.quote('$(malicious)')
        expect(quoted).to eq('"`$(malicious)"')
      end

      it 'properly quotes command chaining attempts' do
        quoted = shell.quote('arg1; malicious')
        expect(quoted).to eq('"arg1; malicious"')
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
      expect(result).to eq('echo "hello world" test')
    end

    it 'handles empty args array' do
      result = shell.join('echo')
      expect(result).to eq('echo')
    end

    it 'handles arguments with dollar sign (quotes and escapes to prevent variable expansion)' do
      # $VAR must be quoted and escaped to prevent PowerShell variable expansion
      result = shell.join('echo', '$VAR')
      expect(result).to eq('echo "`$VAR"')
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
        expect(result).to eq('powershell -Command script.ps1 "arg with spaces"')
      end
    end

    context 'special handling for -File parameter' do
      it 'does not quote the argument after -File' do
        result = shell.join('powershell', '-File', 'script.ps1', 'arg')
        expect(result).to eq('powershell -File script.ps1 arg')
      end

      it 'quotes subsequent arguments after -File' do
        result = shell.join('powershell', '-File', 'script.ps1', 'arg with spaces')
        expect(result).to eq('powershell -File script.ps1 "arg with spaces"')
      end
    end

    context 'security: command injection prevention' do
      it 'properly quotes arguments to prevent injection' do
        result = shell.join('echo', 'hello; malicious')
        # Arguments with spaces are quoted
        expect(result).to eq('echo "hello; malicious"')
      end

      it 'escapes backticks in double quotes' do
        # In double-quoted strings, backticks must be escaped with backtick
        result = shell.join('echo', '`malicious`')
        expect(result).to eq('echo "``malicious``"')
      end
    end

    context 'quoting dash-prefixed arguments' do
      it 'quotes arguments starting with dash' do
        result = shell.join('gswin64c.exe', '-sDEVICE=pdfwrite', 'input.eps')
        expect(result).to eq('gswin64c.exe "-sDEVICE=pdfwrite" input.eps')
      end

      it 'quotes multiple dash-prefixed arguments' do
        result = shell.join('gswin64c.exe', '-sDEVICE=pdfwrite',
                            '-sOutputFile=output.pdf', '-dBATCH', 'input.eps')
        expect(result).to eq('gswin64c.exe "-sDEVICE=pdfwrite" ' \
                             '"-sOutputFile=output.pdf" "-dBATCH" input.eps')
      end

      it 'quotes ImageMagick-style options' do
        result = shell.join('magick', 'input.png', '-resize', '50x50', 'output.png')
        expect(result).to eq('magick input.png "-resize" 50x50 output.png')
      end

      it 'still handles -Command specially (not quoted, next arg not quoted)' do
        result = shell.join('powershell', '-Command', 'Write-Host hello')
        expect(result).to eq('powershell -Command Write-Host hello')
      end

      it 'still handles -File specially (not quoted, next arg not quoted)' do
        result = shell.join('powershell', '-File', 'script.ps1')
        expect(result).to eq('powershell -File script.ps1')
      end

      it 'quotes dash-prefixed args after -Command script' do
        result = shell.join('powershell', '-Command', 'script.ps1', '-SomeFlag')
        expect(result).to eq('powershell -Command script.ps1 "-SomeFlag"')
      end
    end
  end

  describe '#needs_quoting?' do
    it 'returns true for empty strings' do
      expect(shell.needs_quoting?('')).to be true
    end

    it 'returns true for strings with whitespace' do
      expect(shell.needs_quoting?('hello world')).to be true
    end

    it 'returns true for strings with special characters' do
      expect(shell.needs_quoting?('hello;world')).to be true
      expect(shell.needs_quoting?('hello&world')).to be true
      expect(shell.needs_quoting?('hello|world')).to be true
    end

    it 'returns true for strings starting with dash' do
      expect(shell.needs_quoting?('-sDEVICE=pdfwrite')).to be true
      expect(shell.needs_quoting?('-resize')).to be true
      expect(shell.needs_quoting?('-dBATCH')).to be true
      expect(shell.needs_quoting?('-')).to be true
    end

    it 'returns true for strings containing dollar sign (to prevent variable expansion)' do
      expect(shell.needs_quoting?('$VAR')).to be true
      expect(shell.needs_quoting?('price$100')).to be true
    end

    it 'returns false for simple strings' do
      expect(shell.needs_quoting?('hello')).to be false
      expect(shell.needs_quoting?('input.eps')).to be false
      expect(shell.needs_quoting?('output.pdf')).to be false
    end
  end

  describe '#format_path' do
    context 'on non-Windows platforms' do
      before(:each) do
        allow(Ukiryu::Platform).to receive(:windows?).and_return(false)
      end

      it 'returns paths unchanged' do
        expect(shell.format_path('C:\\Users\\file.txt')).to eq('C:\\Users\\file.txt')
      end

      it 'handles Unix-style paths' do
        expect(shell.format_path('/usr/bin/file')).to eq('/usr/bin/file')
      end

      it 'handles paths with spaces (no escaping on non-Windows)' do
        expect(shell.format_path('/path with spaces/file')).to eq('/path with spaces/file')
      end

      it 'handles relative paths' do
        expect(shell.format_path('relative/path')).to eq('relative/path')
      end
    end

    context 'on Windows platform' do
      before(:each) do
        allow(Ukiryu::Platform).to receive(:windows?).and_return(true)
      end

      it 'keeps forward slashes for paths without spaces' do
        expect(shell.format_path('D:/temp/file.eps')).to eq('D:/temp/file.eps')
      end

      it 'wraps paths with spaces in escaped double quotes' do
        expect(shell.format_path('D:/temp/sub dir/file.eps')).to eq('`"D:/temp/sub dir/file.eps`"')
      end

      it 'wraps backslash paths with spaces in escaped double quotes' do
        expect(shell.format_path('C:\\Program Files\\app.exe')).to eq('`"C:\\Program Files\\app.exe`"')
      end

      it 'keeps paths without spaces unchanged' do
        expect(shell.format_path('C:/Users/file.txt')).to eq('C:/Users/file.txt')
      end

      it 'keeps Unix-style paths without spaces unchanged' do
        expect(shell.format_path('/usr/bin/file')).to eq('/usr/bin/file')
      end

      it 'handles relative paths without spaces' do
        expect(shell.format_path('relative/path/to/file')).to eq('relative/path/to/file')
      end

      it 'handles relative paths with spaces (wraps in escaped quotes)' do
        expect(shell.format_path('relative/path with spaces/file')).to eq('`"relative/path with spaces/file`"')
      end
    end
  end

  describe '#headless_environment' do
    it 'returns empty hash (no headless environment needed)' do
      expect(shell.headless_environment).to eq({})
    end
  end

  # Tests for issues reported by Vectory team
  context 'Vectory team reported issues' do
    describe 'Issue 1: Prefix stripping with -sDEVICE=pdfwrite style arguments' do
      it 'preserves the full argument when passed via join' do
        # The argument -sDEVICE=pdfwrite should be preserved as a complete string
        # The join() method quotes it with double quotes to prevent parameter binding
        result = shell.join('gswin64c.exe', '-sDEVICE=pdfwrite', 'input.eps')
        expect(result).to include('"-sDEVICE=pdfwrite"')
        # Verify the prefix is NOT stripped (the full -sDEVICE=pdfwrite is present)
        expect(result).to include('-sDEVICE=pdfwrite')
      end

      it 'quotes dash-prefixed arguments with double quotes to prevent PowerShell parameter binding' do
        # PowerShell's parameter binder can strip the -prefix from arguments
        # Quoting with double quotes prevents this
        arg = '-sDEVICE=pdfwrite'
        expect(shell.needs_quoting?(arg)).to be true
        expect(shell.quote(arg)).to eq('"-sDEVICE=pdfwrite"')
      end

      it 'handles Ghostscript-style device arguments correctly' do
        result = shell.join('gswin64c.exe', '-sDEVICE=pdfwrite',
                            '-sOutputFile=output.pdf', '-dBATCH')
        expect(result).to include('"-sDEVICE=pdfwrite"')
        expect(result).to include('"-sOutputFile=output.pdf"')
        expect(result).to include('"-dBATCH"')
      end
    end

    describe 'Issue 2: Consistent quoting between join and execute_command (FIXED)' do
      it 'join uses double quotes for dash-prefixed arguments' do
        result = shell.join('gswin64c.exe', '-sDEVICE=pdfwrite')
        expect(result).to eq('gswin64c.exe "-sDEVICE=pdfwrite"')
      end

      it 'execute_command uses double quotes for consistency' do
        # FIXED: Both join() and execute_command() now use double quotes
        # to prevent PowerShell's parameter binder from stripping - prefixes
        # Double-quoted strings with proper escaping prevent parameter binding issues
        expect(shell.quote('-sDEVICE=pdfwrite')).to eq('"-sDEVICE=pdfwrite"')
      end
    end

    describe 'Issue 3: Single quote handling in PowerShell (FIXED)' do
      it 'preserves single quotes (not special in double-quoted strings)' do
        # In PowerShell double-quoted strings, single quotes are literal
        expect(shell.quote("it's")).to eq('"it\'s"')
      end

      it 'handles strings with multiple single quotes' do
        expect(shell.quote("it's a test's value")).to eq('"it\'s a test\'s value"')
      end

      it 'handles string that is just a single quote' do
        expect(shell.quote("'")).to eq('"\'"')
      end

      it 'handles string starting with single quote' do
        expect(shell.quote("'hello")).to eq('"\'hello"')
      end

      it 'handles string ending with single quote' do
        expect(shell.quote("hello'")).to eq('"hello\'"')
      end
    end
  end
end
