# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::CliCommands::VersionCommand do
  let(:options) { {} }

  before do
    Ukiryu::Config.reset!
  end

  after do
    Ukiryu::Config.reset!
  end

  describe '#run' do
    it 'displays version without errors' do
      command = described_class.new(options)

      expect { command.run }.not_to raise_error
    end

    it 'outputs version information' do
      command = described_class.new(options)

      expect { command.run }.not_to raise_error
    end
  end
end
