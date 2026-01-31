# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Shell::Cmd do
  let(:shell) { described_class.new }

  describe '#name' do
    it 'returns :cmd' do
      expect(shell.name).to eq(:cmd)
    end
  end

  describe '#escape' do
    it 'escapes percent signs' do
      expect(shell.escape('100%')).to eq('100^%')
    end

    it 'escapes carets' do
      expect(shell.escape('a^b')).to eq('a^^b')
    end

    it 'escapes less than signs' do
      expect(shell.escape('a<b')).to eq('a^<b')
    end

    it 'escapes greater than signs' do
      expect(shell.escape('a>b')).to eq('a^>b')
    end

    it 'escapes ampersands' do
      expect(shell.escape('a&b')).to eq('a^&b')
    end

    it 'escapes pipes' do
      expect(shell.escape('a|b')).to eq('a^|b')
    end

    it 'handles empty strings' do
      expect(shell.escape('')).to eq('')
    end

    it 'handles strings with multiple special characters' do
      expect(shell.escape('a|b&c%d')).to eq('a^|b^&c^%d')
    end

    it 'preserves characters that do not need escaping' do
      expect(shell.escape('hello-world')).to eq('hello-world')
      expect(shell.escape('hello_world')).to eq('hello_world')
      expect(shell.escape('hello.world')).to eq('hello.world')
    end

    it 'handles already-escaped strings' do
      expect(shell.escape('a^^b')).to eq('a^^^^b')
    end

    context 'security: command injection prevention' do
      it 'escapes ampersands to prevent command chaining' do
        expect(shell.escape('arg1&malicious')).to eq('arg1^&malicious')
      end

      it 'escapes pipes to prevent command piping' do
        expect(shell.escape('arg1|malicious')).to eq('arg1^|malicious')
      end

      it 'escapes percent signs to prevent variable expansion' do
        # %PATH% has 2 percent signs, each gets escaped
        expect(shell.escape('%PATH%')).to eq('^%PATH^%')
      end
    end
  end

  describe '#quote' do
    context 'with whitespace' do
      it 'uses double quotes for strings with spaces' do
        expect(shell.quote('hello world')).to eq('"hello world"')
      end

      it 'uses double quotes for strings with tabs' do
        # Create the expected string with an actual tab character
        expected = "\"hello\tworld\""
        result = shell.quote("hello\tworld")
        expect(result).to eq(expected)
      end
    end

    context 'without whitespace' do
      it 'escapes special characters instead of quoting' do
        expect(shell.quote('test|file')).to eq('test^|file')
      end

      it 'escapes percent signs' do
        expect(shell.quote('100%')).to eq('100^%')
      end

      it 'escapes carets' do
        expect(shell.quote('a^b')).to eq('a^^b')
      end

      it 'returns simple strings as-is' do
        expect(shell.quote('hello')).to eq('hello')
      end

      it 'handles empty strings' do
        expect(shell.quote('')).to eq('')
      end
    end

    context 'security: command injection prevention' do
      it 'properly quotes or escapes arguments to prevent injection' do
        # With spaces - uses double quotes
        quoted = shell.quote('hello; malicious')
        expect(quoted).to eq('"hello; malicious"')
      end

      it 'escapes special characters in simple strings' do
        quoted = shell.quote('test|malicious')
        expect(quoted).to eq('test^|malicious')
      end
    end
  end

  describe '#env_var' do
    it 'formats environment variables with % syntax' do
      expect(shell.env_var('PATH')).to eq('%PATH%')
    end

    it 'handles variable names with underscores' do
      expect(shell.env_var('MY_VAR')).to eq('%MY_VAR%')
    end

    it 'handles variable names with numbers' do
      expect(shell.env_var('PATH2')).to eq('%PATH2%')
    end

    it 'handles lowercase variable names' do
      expect(shell.env_var('path')).to eq('%path%')
    end
  end

  describe '#format_path' do
    it 'converts forward slashes to backslashes' do
      expect(shell.format_path('/usr/bin/file')).to eq('\\usr\\bin\\file')
    end

    it 'handles paths with multiple forward slashes' do
      expect(shell.format_path('C:/Users/file.txt')).to eq('C:\\Users\\file.txt')
    end

    it 'handles paths that are already in Windows format' do
      expect(shell.format_path('C:\\Users\\file.txt')).to eq('C:\\Users\\file.txt')
    end

    it 'handles relative paths' do
      expect(shell.format_path('relative/path')).to eq('relative\\path')
    end

    it 'handles paths with spaces' do
      expect(shell.format_path('/path/with spaces/file')).to eq('\\path\\with spaces\\file')
    end
  end

  describe '#join' do
    it 'uses smart quoting for executable and arguments' do
      result = shell.join('echo', 'hello', 'world')
      # Simple strings are escaped but not quoted
      expect(result).to eq('echo hello world')
    end

    it 'quotes executable if it contains spaces' do
      result = shell.join('/path with spaces/echo', 'hello')
      expect(result).to eq('"/path with spaces/echo" hello')
    end

    it 'escapes special characters in simple arguments' do
      result = shell.join('echo', 'test|file')
      expect(result).to eq('echo test^|file')
    end

    it 'quotes arguments that contain whitespace' do
      result = shell.join('echo', 'hello world')
      expect(result).to eq('echo "hello world"')
    end

    it 'handles empty args array' do
      result = shell.join('echo')
      expect(result).to eq('echo')
    end

    it 'handles multiple arguments' do
      result = shell.join('echo', 'hello', 'beautiful', 'world')
      expect(result).to eq('echo hello beautiful world')
    end

    it 'handles arguments with percent signs' do
      result = shell.join('echo', '100%')
      expect(result).to eq('echo 100^%')
    end

    it 'handles complex paths' do
      # NOTE: join() doesn't call format_path(), so paths are not converted
      # The path is treated as a regular argument
      result = shell.join('type', '/path/to/file.txt')
      expect(result).to eq('type /path/to/file.txt')
    end

    context 'security: command injection prevention' do
      it 'properly escapes special characters in simple arguments' do
        result = shell.join('echo', 'arg1|malicious')
        expect(result).to eq('echo arg1^|malicious')
      end

      it 'quotes arguments with spaces (which may contain malicious content)' do
        result = shell.join('echo', 'hello; malicious')
        expect(result).to eq('echo "hello; malicious"')
      end
    end
  end

  describe '#headless_environment' do
    it 'returns empty hash (no headless environment needed)' do
      expect(shell.headless_environment).to eq({})
    end
  end
end
