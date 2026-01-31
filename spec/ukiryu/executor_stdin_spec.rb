# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Ukiryu::Executor do
  let(:shell_symbol) { :bash }

  describe '.execute with stdin' do
    # Use platform-appropriate executable for stdin tests
    let(:executable) do
      if Ukiryu::Platform.windows?
        # Use ruby as a portable stdin echo on Windows
        # ruby -e "print ARGF.read" echoes stdin to stdout (without trailing newline)
        'ruby'
      else
        # Use cat on Unix-like systems
        '/bin/cat'
      end
    end
    let(:args) do
      if Ukiryu::Platform.windows?
        ['-e', 'print ARGF.read']
      else
        []
      end
    end

    context 'with string stdin data' do
      it 'passes stdin data to the command' do
        result = described_class.execute(executable, args, stdin: 'test data', shell: shell_symbol, timeout: 90)

        expect(result.stdout).to eq('test data')
        expect(result.success?).to be true
      end

      it 'passes multi-line stdin data' do
        stdin_data = "line1\nline2\nline3"
        result = described_class.execute(executable, args, stdin: stdin_data, shell: shell_symbol, timeout: 90)

        expect(result.stdout).to eq(stdin_data)
      end

      it 'passes binary stdin data' do
        stdin_data = "\x00\x01\x02\x03"
        result = described_class.execute(executable, args, stdin: stdin_data, shell: shell_symbol, timeout: 90)

        expect(result.stdout).to eq(stdin_data)
      end
    end

    context 'with IO object stdin' do
      it 'reads from file IO object' do
        Tempfile.create('stdin_test') do |file|
          file.write('file content')
          file.rewind

          result = described_class.execute(executable, args, stdin: file, shell: shell_symbol, timeout: 90)

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

        result = described_class.execute(executable, args, stdin: reader, shell: shell_symbol, timeout: 90)

        thread.join
        reader.close

        expect(result.stdout).to eq('pipe data')
      end
    end

    context 'with commands that close stdin early' do
      it 'handles Errno::EPIPE gracefully', unix: true do
        skip 'Skipped on Windows - Unix-specific test' if Ukiryu::Platform.windows?

        # head command closes stdin after reading 10 lines
        result = described_class.execute('/usr/bin/head', ['-n', '1'],
                                         stdin: "line1\nline2\nline3\n",
                                         shell: shell_symbol,
                                         timeout: 90)

        expect(result.stdout).to eq("line1\n")
        expect(result.success?).to be true
      end
    end
  end
end
