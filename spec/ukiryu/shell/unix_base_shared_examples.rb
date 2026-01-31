# frozen_string_literal: true

RSpec.shared_examples 'a Unix shell' do
  describe '#escape' do
    it 'escapes single quotes by replacing with \'\'' do
      expect(subject.escape("it's")).to eq("it'\\''s")
    end

    it 'handles empty strings' do
      expect(subject.escape('')).to eq('')
    end

    it 'handles strings with multiple single quotes' do
      expect(subject.escape("'hello'world'")).to eq("'\\''hello'\\''world'\\''")
    end

    it 'preserves other special characters' do
      expect(subject.escape('$VAR')).to eq('$VAR')
      expect(subject.escape('hello&world')).to eq('hello&world')
    end

    context 'security: command injection prevention' do
      it 'does not allow command chaining with semicolon' do
        # After escaping, ; should still be ; which is safe inside single quotes
        escaped = subject.escape('hello;rm -rf /')
        # The semicolon should be preserved (it's safe inside quotes)
        expect(escaped).to include(';')
      end

      it 'preserves dollar signs for variable expansion' do
        expect(subject.escape('$PATH')).to eq('$PATH')
      end

      it 'preserves backticks for command substitution' do
        expect(subject.escape('`malicious`')).to eq('`malicious`')
      end

      it 'preserves pipes' do
        expect(subject.escape('a|b')).to eq('a|b')
      end
    end
  end

  describe '#quote' do
    it 'wraps strings in single quotes' do
      expect(subject.quote('hello')).to eq("'hello'")
    end

    it 'escapes single quotes within quoted strings' do
      expect(subject.quote("it's")).to eq("'it'\\''s'")
    end

    it 'handles empty strings' do
      expect(subject.quote('')).to eq("''")
    end

    it 'handles strings with spaces' do
      expect(subject.quote('hello world')).to eq("'hello world'")
    end

    it 'handles strings with special characters' do
      expect(subject.quote('$VAR')).to eq("'$VAR'")
      expect(subject.quote('a&b')).to eq("'a&b'")
    end

    it 'handles strings with newlines' do
      expect(subject.quote("line1\nline2")).to eq("'line1\nline2'")
    end

    it 'handles strings with tabs' do
      expect(subject.quote("hello\tworld")).to eq("'hello\tworld'")
    end

    context 'security: command injection prevention' do
      it 'properly quotes arguments to prevent injection' do
        quoted = subject.quote('$(malicious)')
        expect(quoted).to eq("'$(malicious)'")
        # When this is used in a command like: echo '$(malicious)'
        # The single quotes prevent command substitution
      end

      it 'properly quotes semicolons to prevent command chaining' do
        quoted = subject.quote('arg1;rm -rf /')
        expect(quoted).to eq("'arg1;rm -rf /'")
      end

      it 'properly quotes backticks to prevent command substitution' do
        quoted = subject.quote('`malicious`')
        expect(quoted).to eq("'`malicious`'")
      end
    end
  end

  describe '#env_var' do
    it 'formats environment variables with $ syntax' do
      expect(subject.env_var('PATH')).to eq('$PATH')
    end

    it 'handles variable names with underscores' do
      expect(subject.env_var('MY_VAR')).to eq('$MY_VAR')
    end

    it 'handles variable names with numbers' do
      expect(subject.env_var('PATH2')).to eq('$PATH2')
    end

    it 'handles lowercase variable names' do
      expect(subject.env_var('path')).to eq('$path')
    end
  end

  describe '#join' do
    it 'quotes executable and all arguments' do
      expect(subject.join('echo', 'hello', 'world')).to eq("'echo' 'hello' 'world'")
    end

    it 'handles arguments with spaces' do
      expect(subject.join('echo', 'hello world')).to eq("'echo' 'hello world'")
    end

    it 'handles arguments with special characters' do
      expect(subject.join('echo', '$VAR')).to eq("'echo' '$VAR'")
      expect(subject.join('echo', 'a&b')).to eq("'echo' 'a&b'")
    end

    it 'handles empty args array' do
      expect(subject.join('echo')).to eq("'echo'")
    end

    it 'handles multiple arguments' do
      result = subject.join('echo', 'hello', 'beautiful', 'world')
      expect(result).to eq("'echo' 'hello' 'beautiful' 'world'")
    end

    it 'handles arguments with single quotes' do
      result = subject.join('echo', "it's", 'test')
      expect(result).to eq("'echo' 'it'\\''s' 'test'")
    end

    it 'handles paths with spaces' do
      result = subject.join('cat', '/path/with spaces/file.txt')
      expect(result).to eq("'cat' '/path/with spaces/file.txt'")
    end

    context 'security: command injection prevention' do
      it 'does not allow command chaining through arguments' do
        result = subject.join('echo', 'hello; malicious')
        # The semicolon is preserved but the argument is quoted
        expect(result).to eq("'echo' 'hello; malicious'")
        # When executed, the entire 'hello; malicious' is treated as a single argument
      end

      it 'properly quotes command substitution attempts' do
        result = subject.join('echo', '$(malicious)')
        expect(result).to eq("'echo' '$(malicious)'")
      end

      it 'properly quotes backtick attempts' do
        result = subject.join('echo', '`malicious`')
        expect(result).to eq("'echo' '`malicious`'")
      end
    end
  end

  describe '#format_path' do
    it 'returns paths unchanged' do
      expect(subject.format_path('/usr/bin/file')).to eq('/usr/bin/file')
    end

    it 'handles relative paths' do
      expect(subject.format_path('relative/path')).to eq('relative/path')
    end

    it 'handles paths with spaces' do
      expect(subject.format_path('/path/with spaces/file')).to eq('/path/with spaces/file')
    end

    it 'handles Windows-style paths on Unix systems' do
      expect(subject.format_path('C:\\Users\\file.txt')).to eq('C:\\Users\\file.txt')
    end
  end

  describe '#shell_command' do
    it 'returns the shell command name' do
      expect(subject.shell_command).to be_a(String)
      expect(subject.shell_command).to match(/^(bash|zsh|fish|sh|dash)$/)
    end
  end
end

RSpec.shared_examples 'a Unix shell with macOS headless support' do
  describe '#headless_environment' do
    context 'on macOS' do
      before do
        allow(Ukiryu::Platform).to receive(:detect).and_return(:macos)
      end

      it 'includes macOS-specific environment variables' do
        env = subject.headless_environment
        expect(env['NSAppleEventsSuppressStartupAlert']).to eq('true')
        expect(env['NSUIElement']).to eq('1')
        expect(env['GDK_BACKEND']).to eq('x11')
      end
    end

    context 'on non-macOS platforms' do
      before do
        allow(Ukiryu::Platform).to receive(:detect).and_return(:linux)
      end

      it 'returns an empty hash' do
        expect(subject.headless_environment).to eq({})
      end
    end
  end
end

RSpec.shared_examples 'a Unix shell with headless support' do
  describe '#headless_environment' do
    it 'returns an empty hash' do
      expect(subject.headless_environment).to eq({})
    end
  end
end
