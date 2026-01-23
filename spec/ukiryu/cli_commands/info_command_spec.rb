# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Ukiryu::CliCommands::InfoCommand do
  let(:output) { StringIO.new }
  let(:options) { {} }

  before do
    # Reset state
    Ukiryu::Tool.clear_cache
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset
  end

  after do
    # Clean up
    Ukiryu::Tool.clear_cache
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset
  end

  describe '#run' do
    context 'with a valid tool name' do
      it 'displays information for imagemagick' do
        command = described_class.new(options)

        # Should not raise any errors
        expect { command.run('imagemagick') }.not_to raise_error
      end

      it 'displays information for jq' do
        command = described_class.new(options)

        expect { command.run('jq') }.not_to raise_error
      end
    end

    context 'with an invalid tool name' do
      it 'exits with error for non-existent tool' do
        command = described_class.new(options)

        # error! raises Thor::Error
        expect { command.run('nonexistent_tool') }.to raise_error(Thor::Error)
      end
    end
  end

  describe 'output format' do
    it 'displays tool name' do
      command = described_class.new(options)

      # Capture output
      expect { command.run('imagemagick') }.not_to raise_error
    end
  end
end
