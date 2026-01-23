# frozen_string_literal: true

require 'spec_helper'
require 'tool_helper'

RSpec.describe 'ImageMagick Tool Profile' do
  include ToolHelper

  before(:each) { @temp_dir = create_temp_dir }

  after(:each) do
    # Clean up temp directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  describe 'tool availability' do
    it 'detects ImageMagick on the system' do
      skip_unless_tool_available(:imagemagick)

      tool = get_tool(:imagemagick)
      expect(tool.available?).to be true
      expect(tool.executable).to match(/magick/)
      expect(tool.version).to match(/\d+\.\d+/)
    end
  end

  describe 'convert command' do
    before(:each) { skip_unless_tool_available(:imagemagick) }

    it 'converts between formats' do
      input = File.join(@temp_dir, 'input.png')
      output = File.join(@temp_dir, 'output.jpg')

      create_test_image(input)

      tool = get_tool(:imagemagick)
      result = tool.execute(:convert, {
                              inputs: [input],
                              output: output
                            })

      expect(result.success?).to be true
      expect(result.exit_code).to eq(0)
      expect(result.execution_time).to be_a(Numeric)
      expect(result.started_at).to be_a(Time)
      expect(result.finished_at).to be_a(Time)
      expect(File.exist?(output)).to be true
    end

    it 'resizes images' do
      input = File.join(@temp_dir, 'input.png')
      output = File.join(@temp_dir, 'resized.jpg')

      create_test_image(input)

      tool = get_tool(:imagemagick)
      result = tool.execute(:convert, {
                              inputs: [input],
                              output: output,
                              resize: '50x50'
                            })

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true

      # Verify dimensions
      info = `magick identify #{output}`
      expect(info).to match(/50x50/)
    end

    it 'applies quality setting' do
      input = File.join(@temp_dir, 'input.png')
      output = File.join(@temp_dir, 'quality.jpg')

      create_test_image(input)

      tool = get_tool(:imagemagick)
      result = tool.execute(:convert, {
                              inputs: [input],
                              output: output,
                              quality: 50
                            })

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end

    it 'strips metadata' do
      input = File.join(@temp_dir, 'input.png')
      output = File.join(@temp_dir, 'stripped.jpg')

      create_test_image(input)

      tool = get_tool(:imagemagick)
      result = tool.execute(:convert, {
                              inputs: [input],
                              output: output,
                              strip: true
                            })

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end

    it 'combines multiple options' do
      input = File.join(@temp_dir, 'input.png')
      output = File.join(@temp_dir, 'combined.jpg')

      create_test_image(input)

      tool = get_tool(:imagemagick)
      result = tool.execute(:convert, {
                              inputs: [input],
                              output: output,
                              resize: '75x75',
                              quality: 85,
                              strip: true
                            })

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true

      # Verify dimensions
      info = `magick identify #{output}`
      expect(info).to match(/75x75/)
    end

    it 'handles multiple input files' do
      input1 = File.join(@temp_dir, 'input1.png')
      input2 = File.join(@temp_dir, 'input2.png')
      output = File.join(@temp_dir, 'combined.gif') # GIF for multi-frame output

      create_test_image(input1)
      create_test_image(input2, color: 'red')

      tool = get_tool(:imagemagick)
      result = tool.execute(:convert, {
                              inputs: [input1, input2],
                              output: output
                            })

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end
  end

  describe 'identify command' do
    before(:each) { skip_unless_tool_available(:imagemagick) }

    it 'identifies image format and characteristics' do
      input = File.join(@temp_dir, 'test.png')
      create_test_image(input, size: '200x150')

      tool = get_tool(:imagemagick)
      result = tool.execute(:identify, {
                              input: [input]
                            })

      expect(result.success?).to be true
      expect(result.stdout).to match(/200x150/)
    end

    it 'identifies multiple images' do
      input1 = File.join(@temp_dir, 'test1.png')
      input2 = File.join(@temp_dir, 'test2.png')
      create_test_image(input1)
      create_test_image(input2)

      tool = get_tool(:imagemagick)
      result = tool.execute(:identify, {
                              input: [input1, input2]
                            })

      expect(result.success?).to be true
      expect(result.stdout).to match(/PNG.*\d+x\d+/)
    end
  end

  describe 'mogrify command' do
    before(:each) { skip_unless_tool_available(:imagemagick) }

    it 'modifies images in place' do
      input = File.join(@temp_dir, 'test.png')
      create_test_image(input, size: '100x100')

      tool = get_tool(:imagemagick)
      result = tool.execute(:mogrify, {
                              inputs: [input],
                              resize: '50x50'
                            })

      expect(result.success?).to be true

      # Verify the file was modified
      info = `magick identify #{input}`
      expect(info).to match(/50x50/)
    end
  end
end
