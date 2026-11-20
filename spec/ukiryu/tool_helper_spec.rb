# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ToolHelper do
  subject(:probe) { helper.inkscape_export_available? }

  let(:helper) { Object.new.extend(described_class) }
  let(:tool) { instance_double(Ukiryu::Tool, available?: true, executable: '/test/inkscape') }
  let(:result) do
    instance_double('Ukiryu::Execution::Result', success?: true, command: 'inkscape --export-type=png input.svg',
                                                 exit_code: 0, stderr: '')
  end

  before do
    allow(helper).to receive(:get_tool).with(:inkscape).and_return(tool)
  end

  describe '#inkscape_export_available?' do
    it 'rejects a missing executable without attempting an export' do
      allow(tool).to receive(:available?).and_return(false)
      expect(tool).not_to receive(:execute)

      expect(probe).to be false
    end

    it 'rejects an unavailable tool profile' do
      allow(helper).to receive(:get_tool).with(:inkscape).and_raise(Ukiryu::Errors::ToolNotFoundError)

      expect(probe).to be false
    end

    it 'exports a tiny SVG and removes the temporary directory' do
      input_path = nil
      allow(tool).to receive(:execute) do |command, inputs:, output:, format:, execution_timeout:|
        expect(command).to eq(:export)
        expect(format).to eq(:png)
        expect(execution_timeout).to eq(30)
        input = inputs.fetch(0)
        expect(File.read(input)).to include('<svg', '<rect')
        input_path = input
        # Renaming also checks that the input handle is closed on Windows.
        File.rename(input, "#{input}.closed")
        File.binwrite(output, "\x89PNG\r\n\x1a\n")
        result
      end

      expect(probe).to be true
      expect(helper.inkscape_export_failure).to be_nil
      expect(Dir.exist?(File.dirname(input_path))).to be false
    end

    it 'rejects a successful exit without an output file' do
      allow(tool).to receive(:execute).and_return(result)

      expect(probe).to be false
      expect(helper.inkscape_export_failure).to include('Exit status: 0', 'nonempty PNG: false')
    end

    it 'rejects an empty output file' do
      allow(tool).to receive(:execute) do |_, output:, **|
        File.write(output, '')
        result
      end

      expect(probe).to be false
    end

    it 'rejects a failed conversion even when it leaves an output file' do
      allow(result).to receive_messages(success?: false, exit_code: 1, stderr: 'export failed')
      allow(tool).to receive(:execute) do |_, output:, **|
        File.write(output, 'partial PNG')
        result
      end

      expect(probe).to be false
      expect(helper.inkscape_export_failure).to include(result.command, 'Exit status: 1', 'export failed')
    end

    it 'preserves executor diagnostics and cleans up after an export error' do
      input_path = nil
      allow(tool).to receive(:execute) do |_, inputs:, **|
        input_path = inputs.fetch(0)
        raise Ukiryu::Errors::ExecutionError,
              "Command: inkscape input.svg\nExit status: 1\nSTDOUT: noisy\nSTDERR: cannot export"
      end

      expect(probe).to be false
      expect(helper.inkscape_export_failure).to include('Command: inkscape input.svg', 'Exit status: 1',
                                                        'STDERR: cannot export')
      expect(helper.inkscape_export_failure).not_to include('noisy')
      expect(Dir.exist?(File.dirname(input_path))).to be false
    end
  end
end
