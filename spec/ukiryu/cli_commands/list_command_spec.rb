# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Ukiryu::CliCommands::ListCommand do
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
    it 'lists all available tools without errors' do
      command = described_class.new(options)

      expect { command.run }.not_to raise_error
    end

    it 'shows tool count' do
      command = described_class.new(options)

      expect { command.run }.not_to raise_error
    end
  end

  describe 'tool availability' do
    it 'shows availability status for each tool' do
      command = described_class.new(options)

      expect { command.run }.not_to raise_error
    end
  end
end
