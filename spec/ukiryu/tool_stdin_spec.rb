# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Ukiryu::Tool do
  describe '#execute with stdin parameter' do
    let(:tool) { described_class.get(:jq) }

    before do
      # Skip test if jq is not available
      skip 'jq not available' unless tool.available?
    end

    context 'with string stdin data' do
      it 'passes stdin data to the command' do
        result = tool.execute(:process, execution_timeout: 90, stdin: '{"name": "value"}', filter: '.')

        expect(result.stdout).to include('"name"')
        expect(result.stdout).to include('"value"')
        expect(result.success?).to be true
      end

      it 'extracts and filters JSON from stdin' do
        result = tool.execute(:process, execution_timeout: 90, stdin: '{"foo": "bar", "baz": "qux"}', filter: '.foo')

        expect(result.stdout.strip).to eq('"bar"')
      end
    end

    context 'with file stdin data' do
      it 'reads from file and passes to stdin' do
        Tempfile.create('jq_test') do |file|
          file.write('{"test": "data"}')
          file.rewind

          result = tool.execute(:process, execution_timeout: 90, stdin: file.read, filter: '.test')

          expect(result.stdout.strip).to eq('"data"')
        end
      end
    end

    context 'with IO object stdin' do
      it 'reads from IO object' do
        reader, writer = IO.pipe

        thread = Thread.new do
          writer.write('{"io": "test"}')
          writer.close
        end

        result = tool.execute(:process, execution_timeout: 90, stdin: reader, filter: '.io')

        thread.join
        reader.close

        expect(result.stdout.strip).to eq('"test"')
      end
    end

    context 'stdin parameter isolation' do
      it 'does not pass stdin as a command argument' do
        # stdin should be extracted before building args
        result = tool.execute(:process, execution_timeout: 90, stdin: '{"test": "value"}', filter: '.')

        # If stdin was passed as an argument, jq would try to read it as a file
        # and would fail or produce different output
        expect(result.success?).to be true
      end
    end
  end
end
