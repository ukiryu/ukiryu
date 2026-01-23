# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Ukiryu::Executor do
  describe '.execute with stdin' do
    let(:executable) { '/bin/cat' }
    let(:args) { [] }

    context 'with string stdin data' do
      it 'passes stdin data to the command' do
        result = described_class.execute(executable, args, stdin: 'test data')

        expect(result.stdout).to eq('test data')
        expect(result.success?).to be true
      end

      it 'passes multi-line stdin data' do
        stdin_data = "line1\nline2\nline3"
        result = described_class.execute(executable, args, stdin: stdin_data)

        expect(result.stdout).to eq(stdin_data)
      end

      it 'passes binary stdin data' do
        stdin_data = "\x00\x01\x02\x03"
        result = described_class.execute(executable, args, stdin: stdin_data)

        expect(result.stdout).to eq(stdin_data)
      end
    end

    context 'with IO object stdin' do
      it 'reads from file IO object' do
        Tempfile.create('stdin_test') do |file|
          file.write('file content')
          file.rewind

          result = described_class.execute(executable, args, stdin: file)

          expect(result.stdout).to eq('file content')
        end
      end

      it 'reads from pipe IO object' do
        reader, writer = IO.pipe

        # Write in separate thread to avoid deadlock
        thread = Thread.new do
          writer.write('pipe data')
          writer.close
        end

        result = described_class.execute(executable, args, stdin: reader)

        thread.join
        reader.close

        expect(result.stdout).to eq('pipe data')
      end
    end

    context 'with commands that close stdin early' do
      it 'handles Errno::EPIPE gracefully' do
        # head command closes stdin after reading 10 lines
        result = described_class.execute('/usr/bin/head', ['-n', '1'],
                                         stdin: "line1\nline2\nline3\n")

        expect(result.stdout).to eq("line1\n")
        expect(result.success?).to be true
      end
    end
  end
end
