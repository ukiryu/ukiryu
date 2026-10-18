# frozen_string_literal: true

# Test helper module for tool testing
module ToolHelper
  # Get a tool by name
  # @param name [String, Symbol] the tool name
  # @return [Ukiryu::Tool] the tool instance
  def get_tool(name)
    Ukiryu::Tool.get(name.to_s)
  end

  # Check if a tool is available on the system
  # @param name [String, Symbol] the tool name
  # @return [Boolean] true if the tool is available
  def tool_available?(name)
    tool = get_tool(name)
    tool.available?
  rescue Ukiryu::Errors::ToolNotFoundError
    false
  end

  # Get tool version if available
  # @param name [String, Symbol] the tool name
  # @return [String, nil] the tool version or nil if not available
  def tool_version(name)
    tool = get_tool(name)
    tool.version if tool.available?
  end

  # True when the local ImageMagick can ENCODE PNG. Some runner builds
  # (tool-setup/static installs) ship decode-only delegate sets: identify
  # works but every PNG write fails with "no encode delegate for this
  # image format `''". The fixture-copy specs decode fine; the
  # resize/mogrify specs need the encoder.
  def png_encode_available?
    magick = %w[magick convert].find do |m|
      system(m, "-version", out: File::NULL, err: File::NULL)
    end
    return false unless magick

    require "tmpdir"
    probe = File.join(Dir.tmpdir, "ukiryu_png_probe_#{Process.pid}.png")
    File.delete(probe) if File.exist?(probe)
    begin
      ok = system(magick, "-size", "4x4", "xc:white", "png:#{probe}",
                  out: File::NULL, err: File::NULL)
      ok && File.exist?(probe) && !File.zero?(probe)
    ensure
      File.delete(probe) if File.exist?(probe)
    end
  end

  # True when mogrify can rewrite an image IN PLACE. ImageMagick
  # 7.1.2-33 on macOS 26 regressed here: the same build encodes PNG
  # (the probe above passes) yet in-place mogrify dies with
  # "no encode delegate for this image format `'". Version-dependent,
  # so the probe — not a version list — is the gate.
  def mogrify_in_place_available?
    magick = %w[magick convert].find do |m|
      system(m, "-version", out: File::NULL, err: File::NULL)
    end
    return false unless magick

    require "tmpdir"
    require "fileutils"
    dir = Dir.mktmpdir("ukiryu_mogrify_probe")
    src = File.join(dir, "src.png")
    ok = system(magick, "-size", "4x4", "xc:white", "png:#{src}",
                out: File::NULL, err: File::NULL)
    return false unless ok && File.exist?(src) && !File.zero?(src)

    system(magick, "mogrify", "-resize", "2x2!", src,
           out: File::NULL, err: File::NULL)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  # Create a temporary test image by copying a fixture image

  # This avoids using ImageMagick's built-in formats which aren't available on all builds
  # @param path [String] the path to create the image at
  # @param size [String] the image size (e.g., "100x100", "200x150")
  # @param color [String] the color name (blue or red)
  def create_test_image(path, size: '100x100', color: 'blue')
    require 'open3'

    # Copy fixture image instead of generating with ImageMagick
    # This works on all platforms including Windows ARM64 with limited ImageMagick builds
    # Fixtures are in spec/fixtures/images/, __dir__ is spec/support/
    # So we need to go up one level from __dir__ to get to spec/, then into fixtures/
    fixture_dir = File.expand_path('../fixtures/images', __dir__)
    fixture_file = case color.to_sym
                   when :red
                     File.join(fixture_dir, 'test_red.png')
                   else
                     File.join(fixture_dir, 'test_blue.png')
                   end

    # If the requested size differs from the fixture (100x100), resize after copying
    if size != '100x100'
      # Build resize command based on platform
      if Ukiryu::Platform.windows?
        magick_exists = system('where magick.exe >nul 2>&1') if defined?(system)
      elsif defined?(system)
        magick_exists = system('which magick > /dev/null 2>&1')
      end
      base_cmd = magick_exists ? 'magick' : 'convert'

      # Resize the fixture image (this uses core ImageMagick functionality, not built-in formats)
      # Use ! to force exact dimensions and ignore aspect ratio
      cmd = "#{base_cmd} #{fixture_file} -resize #{size}! #{path}"
      _, stderr, status = Open3.capture3(cmd)
      raise "Failed to resize test image: #{stderr}" unless status.success?
    else
      # Just copy the fixture as-is
      FileUtils.cp(fixture_file, path)
    end

    path
  end

  # Create a temporary test directory
  # @param prefix [String] the prefix for the temp directory
  # @return [String] the path to the temp directory
  def create_temp_dir(prefix: 'ukiryu_test')
    require 'tmpdir'
    Dir.mktmpdir(prefix)
  end

  # Check if command exists on system
  # @param cmd [String] the command to check
  # @return [Boolean] true if the command exists
  def command_exists?(cmd)
    if Ukiryu::Platform.windows?
      system("where #{cmd} >nul 2>&1")
    else
      system("which #{cmd} > /dev/null 2>&1")
    end
  end

  # Skip test if tool is not available
  # @param name [String, Symbol] the tool name
  def skip_unless_tool_available(name)
    tool_name = name.to_s
    tool_name = tool_name.capitalize unless tool_name == 'imagemagick'
    skip "#{tool_name} is not available on this system" unless tool_available?(name)
  end

  # Get list of available tools for testing
  # @return [Hash] map of tool name => availability status
  def available_tools
    {
      imagemagick: tool_available?(:imagemagick),
      ffmpeg: tool_available?(:ffmpeg),
      pandoc: tool_available?(:pandoc),
      jpegoptim: tool_available?(:jpegoptim),
      optipng: tool_available?(:optipng)
    }
  end
end
