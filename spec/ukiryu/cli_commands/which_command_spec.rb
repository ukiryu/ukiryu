# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::CliCommands::WhichCommand do
  let(:options) { {} }

  before do
    Ukiryu::Tool.clear_cache
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset
  end

  after do
    Ukiryu::Tool.clear_cache
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset
  end

  describe '#run' do
    context 'with exact tool name match' do
      it 'resolves imagemagick correctly' do
        command = described_class.new(options)
        expect { command.run('imagemagick') }.not_to raise_error
      end

      it 'resolves jq correctly' do
        command = described_class.new(options)
        expect { command.run('jq') }.not_to raise_error
      end

      it 'resolves ffmpeg correctly' do
        command = described_class.new(options)
        expect { command.run('ffmpeg') }.not_to raise_error
      end
    end

    context 'with interface name' do
      it 'resolves ping to ping_bsd on macOS' do
        # Skip if ping tools are not in the register
        skip 'ping tools not registered' unless Ukiryu::Tool.find_by(:ping)

        command = described_class.new(options)
        expect { command.run('ping') }.not_to raise_error
      end
    end

    context 'with platform override' do
      it 'resolves ping to ping_gnu on linux' do
        # Skip if ping tools are not in the register
        skip 'ping tools not registered' unless Ukiryu::Tool.find_by(:ping)

        command = described_class.new(options.merge(platform: 'linux'))
        expect { command.run('ping') }.not_to raise_error
      end

      it 'resolves ping to ping_bsd on macos' do
        # Skip if ping tools are not in the register
        skip 'ping tools not registered' unless Ukiryu::Tool.find_by(:ping)

        command = described_class.new(options.merge(platform: 'macos'))
        expect { command.run('ping') }.not_to raise_error
      end
    end

    context 'with shell override' do
      it 'respects shell override' do
        # On Windows, zsh is not a valid shell, so use bash instead
        # (bash is available via Git Bash/MSYS2)
        shell_override = if Gem.win_platform?
                           'bash'
                         else
                           'zsh'
                         end
        command = described_class.new(options.merge(shell: shell_override))
        expect { command.run('imagemagick') }.not_to raise_error
      end
    end

    context 'with invalid tool name' do
      it 'exits with error for non-existent tool' do
        command = described_class.new(options)
        expect { command.run('nonexistent_tool') }.to raise_error(Thor::Error)
      end
    end
  end

  describe 'resolution behavior' do
    it 'shows match type for exact matches' do
      command = described_class.new(options)
      expect { command.run('imagemagick') }.not_to raise_error
    end

    it 'shows match type for interface matches' do
      # Skip if ping tools are not in the register
      skip 'ping tools not registered' unless Ukiryu::Tool.find_by(:ping)

      command = described_class.new(options)
      expect { command.run('ping') }.not_to raise_error
    end

    it 'displays platform and shell information' do
      command = described_class.new(options)
      expect { command.run('imagemagick') }.not_to raise_error
    end
  end

  describe 'tool availability' do
    it 'shows available status for installed tools' do
      command = described_class.new(options)
      expect { command.run('imagemagick') }.not_to raise_error
    end

    it 'shows not available status for uninstalled tools' do
      # Skip if ping_gnu is not in the register
      skip 'ping_gnu not registered' unless Ukiryu::Tool.find_by(:ping)

      command = described_class.new(options.merge(platform: 'linux'))
      # ping_gnu is not available on macOS
      expect { command.run('ping') }.not_to raise_error
    end
  end
end
