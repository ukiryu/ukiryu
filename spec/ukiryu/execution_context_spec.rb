# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::ExecutionContext do
  let(:platform) { :macos }
  let(:shell) { :bash }
  let(:register_path) { '/test/register' }

  describe '.current' do
    it 'creates a context from Runtime when none is set' do
      described_class.reset_current!

      context = described_class.current

      expect(context).to be_a(described_class)
      expect(context.platform).to be_a(Symbol)
      expect(context.shell).to be_a(Symbol)
    end

    it 'returns the same context when called multiple times' do
      described_class.reset_current!

      context1 = described_class.current
      context2 = described_class.current

      expect(context1.object_id).to eq(context2.object_id)
    end
  end

  describe '.current=' do
    it 'sets the current context' do
      described_class.reset_current!

      new_context = described_class.new(platform: :linux, shell: :zsh)
      described_class.current = new_context

      expect(described_class.current).to eq(new_context)
      expect(described_class.current.platform).to eq(:linux)
    end
  end

  describe '.with_context' do
    it 'executes a block with a temporary context' do
      described_class.reset_current!
      original_context = described_class.current

      temp_context = described_class.new(platform: :linux, shell: :zsh)

      result = described_class.with_context(temp_context) do
        described_class.current
      end

      expect(result).to eq(temp_context)
      expect(described_class.current).to eq(original_context)
    end

    it 'restores the original context even if an error occurs' do
      described_class.reset_current!
      original_context = described_class.current

      temp_context = described_class.new(platform: :linux, shell: :zsh)

      begin
        described_class.with_context(temp_context) do
          raise 'test error'
        end
      rescue StandardError
        # Expected
      end

      expect(described_class.current).to eq(original_context)
    end
  end

  describe '.from_runtime' do
    it 'creates a context with values from Runtime' do
      context = described_class.from_runtime

      expect(context.platform).to be_a(Symbol)
      expect(context.shell).to be_a(Symbol)
    end
  end

  describe '.reset_current!' do
    it 'clears the current context' do
      described_class.current = described_class.new(platform: :linux)
      described_class.reset_current!

      expect(described_class.current).not_to eq(nil)
      # Should create a new context from Runtime
      expect(described_class.current.platform).to be_a(Symbol)
    end
  end

  describe '#initialize' do
    it 'creates a context with specified values' do
      context = described_class.new(
        platform: platform,
        shell: shell,
        register_path: register_path,
        timeout: 60,
        debug: true,
        metrics: true
      )

      expect(context.platform).to eq(:macos)
      expect(context.shell).to eq(:bash)
      expect(context.register_path).to eq('/test/register')
      expect(context.timeout).to eq(60)
      expect(context.debug).to be true
      expect(context.metrics).to be true
    end

    it 'uses default values when not specified' do
      context = described_class.new

      expect(context.platform).to be_nil
      expect(context.shell).to be_nil
      expect(context.register_path).to be_nil
      expect(context.timeout).to be_nil
      expect(context.debug).to be false
      expect(context.metrics).to be false
      expect(context.options).to eq({})
    end
  end

  describe '#shell_class' do
    it 'returns the shell class' do
      context = described_class.new(shell: :bash)

      expect(context.shell_class).to be_a(Class)
    end
  end

  describe '#on_platform?' do
    it 'returns true when on the specified platform' do
      context = described_class.new(platform: :macos)

      expect(context.on_platform?(:macos)).to be true
      expect(context.on_platform?(:linux)).to be false
    end
  end

  describe '#using_shell?' do
    it 'returns true when using the specified shell' do
      context = described_class.new(shell: :bash)

      expect(context.using_shell?(:bash)).to be true
      expect(context.using_shell?(:zsh)).to be false
    end
  end

  describe '#windows?' do
    it 'returns true when on Windows' do
      context = described_class.new(platform: :windows)

      expect(context.windows?).to be true
    end

    it 'returns false when not on Windows' do
      context = described_class.new(platform: :macos)

      expect(context.windows?).to be false
    end
  end

  describe '#macos?' do
    it 'returns true when on macOS' do
      context = described_class.new(platform: :macos)

      expect(context.macos?).to be true
    end

    it 'returns false when not on macOS' do
      context = described_class.new(platform: :linux)

      expect(context.macos?).to be false
    end
  end

  describe '#linux?' do
    it 'returns true when on Linux' do
      context = described_class.new(platform: :linux)

      expect(context.linux?).to be true
    end

    it 'returns false when not on Linux' do
      context = described_class.new(platform: :macos)

      expect(context.linux?).to be false
    end
  end

  describe '#unix_shell?' do
    it 'returns true for Unix-like shells' do
      %i[bash zsh fish sh].each do |sh|
        context = described_class.new(shell: sh)
        expect(context.unix_shell?).to be true
      end
    end

    it 'returns false for Windows shells' do
      %i[powershell cmd].each do |sh|
        context = described_class.new(shell: sh)
        expect(context.unix_shell?).to be false
      end
    end
  end

  describe '#windows_shell?' do
    it 'returns true for Windows shells' do
      %i[powershell cmd].each do |sh|
        context = described_class.new(shell: sh)
        expect(context.windows_shell?).to be true
      end
    end

    it 'returns false for Unix shells' do
      %i[bash zsh fish sh].each do |sh|
        context = described_class.new(shell: sh)
        expect(context.windows_shell?).to be false
      end
    end
  end

  describe '#merge' do
    it 'creates a new context with merged values' do
      context1 = described_class.new(
        platform: :macos,
        shell: :bash,
        timeout: 30
      )

      context2 = context1.merge(
        shell: :zsh,
        timeout: 60
      )

      # Original context unchanged
      expect(context1.platform).to eq(:macos)
      expect(context1.shell).to eq(:bash)
      expect(context1.timeout).to eq(30)

      # New context has merged values
      expect(context2.platform).to eq(:macos)
      expect(context2.shell).to eq(:zsh)
      expect(context2.timeout).to eq(60)
    end

    it 'preserves original values when not specified' do
      context1 = described_class.new(
        platform: :macos,
        shell: :bash,
        debug: true
      )

      context2 = context1.merge(shell: :zsh)

      expect(context2.platform).to eq(:macos)
      expect(context2.shell).to eq(:zsh)
      expect(context2.debug).to be true
    end
  end

  describe '#to_s' do
    it 'returns a string representation' do
      context = described_class.new(
        platform: :macos,
        shell: :bash,
        register_path: '/test/register'
      )

      str = context.to_s

      expect(str).to include('macos')
      expect(str).to include('bash')
      expect(str).to include('/test/register')
    end
  end

  describe '#inspect' do
    it 'returns an inspection string' do
      context = described_class.new(platform: :macos, shell: :bash)

      inspect_str = context.inspect

      expect(inspect_str).to include('ExecutionContext')
      expect(inspect_str).to include('macos')
      expect(inspect_str).to include('bash')
    end
  end
end
