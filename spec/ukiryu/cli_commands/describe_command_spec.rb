# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::CliCommands::DescribeCommand do
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
    context 'with a valid tool' do
      it 'shows overview for imagemagick without errors' do
        command = described_class.new(options)

        expect { command.run('imagemagick') }.not_to raise_error
      end

      it 'shows overview for jq without errors' do
        command = described_class.new(options)

        expect { command.run('jq') }.not_to raise_error
      end
    end

    context 'with a tool and command' do
      it 'shows detailed description for a specific command' do
        command = described_class.new(options)

        expect { command.run('imagemagick', 'convert') }.not_to raise_error
      end
    end

    context 'with an invalid tool' do
      it 'exits with error for non-existent tool' do
        command = described_class.new(options)

        # error! raises Thor::Error
        expect { command.run('nonexistent_tool') }.to raise_error(Thor::Error)
      end
    end
  end
end
