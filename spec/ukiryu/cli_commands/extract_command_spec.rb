# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Ukiryu::CliCommands::ExtractCommand do
  let(:options) { {} }

  before do
    # Reset state
    Ukiryu::Config.reset!
  end

  after do
    # Clean up
    Ukiryu::Config.reset!
  end

  describe '#run' do
    context 'with a valid tool that has help output' do
      it 'extracts definition successfully' do
        command = described_class.new(options)

        # Capture stdout
        expect { command.run('git') }.not_to raise_error
      end
    end

    context 'with output option' do
      let(:temp_file) { File.join(Dir.tmpdir, "ukiryu_extract_test_#{rand(1000)}.yaml") }

      after do
        File.delete(temp_file) if File.exist?(temp_file)
      end

      it 'writes to output file' do
        command = described_class.new(output: temp_file)

        expect { command.run('git') }.not_to raise_error
        expect(File.exist?(temp_file)).to be true

        content = File.read(temp_file)
        expect(content).to include('git')
        expect(content).to include('ukiryu_schema')
      end
    end

    context 'with method option' do
      it 'uses specified method' do
        command = described_class.new(method: 'help')

        expect { command.run('git') }.not_to raise_error
      end
    end

    context 'using Tool.extract_definition directly' do
      it 'extracts definition' do
        result = Ukiryu::Tool.extract_definition('git')

        expect(result[:success]).to be true
        expect(result[:yaml]).to include('git')
        expect(result[:yaml]).to include('ukiryu_schema')
      end

      it 'accepts options hash' do
        result = Ukiryu::Tool.extract_definition('git', method: :help)

        expect(result[:success]).to be true
        expect(result[:method]).to eq(:help)
      end
    end
  end
end
