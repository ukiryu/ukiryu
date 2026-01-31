# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Shell::Tcsh do
  let(:shell) { described_class.new }

  describe '#name' do
    it 'returns :tcsh' do
      expect(shell.name).to eq(:tcsh)
    end
  end

  describe '#escape' do
    it 'escapes exclamation marks (history expansion)' do
      expect(shell.escape('hello!')).to eq('hello\\!')
    end

    it 'escapes dollar signs' do
      expect(shell.escape('$VAR')).to eq('\\$VAR')
    end

    it 'escapes backticks' do
      expect(shell.escape('`command`')).to eq('\\`command\\`')
    end

    it 'escapes double quotes' do
      expect(shell.escape('say "hello"')).to eq('say \\"hello\\"')
    end

    it 'escapes backslashes' do
      expect(shell.escape('path\\to\\file')).to eq('path\\\\to\\\\file')
    end

    it 'handles strings with multiple special characters' do
      expect(shell.escape('!$`')).to eq('\\!\\$\\`')
    end

    it 'handles empty strings' do
      expect(shell.escape('')).to eq('')
    end

    it 'preserves characters that do not need escaping' do
      expect(shell.escape('hello-world')).to eq('hello-world')
      expect(shell.escape('hello_world')).to eq('hello_world')
      expect(shell.escape('hello.world')).to eq('hello.world')
    end

    context 'security: command injection prevention' do
      it 'escapes exclamation marks to prevent history expansion attacks' do
        expect(shell.escape('!rm -rf /')).to eq('\\!rm -rf /')
      end

      it 'escapes dollar signs to prevent variable expansion' do
        expect(shell.escape('$PATH')).to eq('\\$PATH')
      end

      it 'escapes backticks to prevent command substitution' do
        expect(shell.escape('`malicious`')).to eq('\\`malicious\\`')
      end

      it 'handles mixed special characters' do
        expect(shell.escape('!$(malicious)')).to eq('\\!\\$(malicious)')
      end
    end
  end

  describe '#quote' do
    it 'wraps strings in single quotes' do
      expect(shell.quote('hello')).to eq("'hello'")
    end

    it 'escapes exclamation marks within quoted strings' do
      expect(shell.quote('hello!')).to eq("'hello\\!'")
    end

    it 'escapes single quotes within quoted strings' do
      expect(shell.quote("it's")).to eq("'it'\\''s'")
    end

    it 'handles empty strings' do
      expect(shell.quote('')).to eq("''")
    end

    it 'handles strings with spaces' do
      expect(shell.quote('hello world')).to eq("'hello world'")
    end

    it 'handles strings with special characters' do
      # Dollar signs and other chars are safe inside single quotes
      # Only ! and ' need special handling
      expect(shell.quote('$VAR')).to eq("'$VAR'")
    end

    it 'handles strings with both ! and quotes' do
      expect(shell.quote("it's!")).to eq("'it'\\''s\\!'")
    end

    context 'security: command injection prevention' do
      it 'escapes exclamation marks to prevent history expansion' do
        quoted = shell.quote('!rm -rf /')
        expect(quoted).to eq("'\\!rm -rf /'")
      end

      it 'properly quotes arguments to prevent injection' do
        quoted = shell.quote('$(malicious)')
        expect(quoted).to eq("'$(malicious)'")
      end

      it 'handles complex injection attempts' do
        quoted = shell.quote('!$(rm -rf /)')
        expect(quoted).to eq("'\\!$(rm -rf /)'")
      end
    end
  end

  describe '#env_var' do
    it 'formats environment variables with $ syntax' do
      expect(shell.env_var('PATH')).to eq('$PATH')
    end

    it 'handles variable names with underscores' do
      expect(shell.env_var('MY_VAR')).to eq('$MY_VAR')
    end

    it 'handles variable names with numbers' do
      expect(shell.env_var('PATH2')).to eq('$PATH2')
    end

    it 'handles lowercase variable names' do
      expect(shell.env_var('path')).to eq('$path')
    end
  end

  describe '#join' do
    it 'quotes executable and all arguments' do
      expect(shell.join('echo', 'hello', 'world')).to eq("'echo' 'hello' 'world'")
    end

    it 'handles arguments with spaces' do
      expect(shell.join('echo', 'hello world')).to eq("'echo' 'hello world'")
    end

    it 'handles arguments with exclamation marks' do
      expect(shell.join('echo', 'hello!')).to eq("'echo' 'hello\\!'")
    end

    it 'handles empty args array' do
      expect(shell.join('echo')).to eq("'echo'")
    end

    it 'handles multiple arguments' do
      result = shell.join('echo', 'hello', 'beautiful', 'world')
      expect(result).to eq("'echo' 'hello' 'beautiful' 'world'")
    end

    it 'handles arguments with single quotes' do
      result = shell.join('echo', "it's", 'test')
      expect(result).to eq("'echo' 'it'\\''s' 'test'")
    end

    it 'handles paths with spaces' do
      result = shell.join('cat', '/path/with spaces/file.txt')
      expect(result).to eq("'cat' '/path/with spaces/file.txt'")
    end

    context 'security: command injection prevention' do
      it 'escapes exclamation marks through arguments' do
        result = shell.join('echo', 'hello! malicious')
        expect(result).to eq("'echo' 'hello\\! malicious'")
      end

      it 'properly quotes command substitution attempts' do
        result = shell.join('echo', '$(malicious)')
        expect(result).to eq("'echo' '$(malicious)'")
      end
    end
  end

  describe '#format_path' do
    it 'returns paths unchanged' do
      expect(shell.format_path('/usr/bin/file')).to eq('/usr/bin/file')
    end

    it 'handles relative paths' do
      expect(shell.format_path('relative/path')).to eq('relative/path')
    end

    it 'handles paths with spaces' do
      expect(shell.format_path('/path/with spaces/file')).to eq('/path/with spaces/file')
    end
  end

  describe '#headless_environment' do
    it 'returns an empty hash' do
      expect(shell.headless_environment).to eq({})
    end
  end
end
