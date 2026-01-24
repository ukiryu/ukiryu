# frozen_string_literal: true

require_relative '../source'

module Ukiryu
  module Definition
    module Sources
      # Load tool definitions from a file
      #
      # This source reads YAML tool definitions from the filesystem.
      # It tracks file metadata for cache invalidation.
      class FileSource < Source
        # The path to the definition file
        # @return [String] absolute path to the file
        attr_reader :path

        # The file modification time
        # @return [Time] file mtime
        attr_reader :mtime

        # Create a new file-based definition source
        #
        # @param path [String] path to the definition file
        # @raise [DefinitionNotFoundError] if the file doesn't exist
        # @raise [DefinitionLoadError] if the file is not readable
        def initialize(path)
          @path = expand_path(path)
          @mtime = nil # Will be set on first load
          @cached_content = nil

          validate_file_exists!
          validate_file_readable!
        end

        # Load the YAML definition content from the file
        #
        # @return [String] the YAML content
        # @raise [DefinitionLoadError] if the file cannot be read
        def load
          current_mtime = get_mtime

          # Check if file has changed since init
          if @mtime && @mtime != current_mtime
            raise DefinitionLoadError,
                  "File #{@path} has been modified since it was loaded. " \
                  "Original mtime: #{@mtime}, Current mtime: #{current_mtime}"
          end

          @mtime = current_mtime

          # Read and cache content
          @load ||= read_file
        end

        # Get the source type
        #
        # @return [Symbol] :file
        def source_type
          :file
        end

        # Get a unique cache key for this file source
        #
        # The cache key includes a hash of the path and the mtime,
        # ensuring that file changes invalidate the cache.
        #
        # @return [String] unique cache key
        def cache_key
          "file:#{sha256(path)}:#{mtime || get_mtime}"
        end

        # Get the real path (resolves symlinks)
        #
        # @return [String] real path to the file
        def real_path
          @real_path ||= File.realpath(path)
        rescue Errno::ENOENT
          path
        end

        private

        # Expand the path to an absolute path
        #
        # @param path [String] the path to expand
        # @return [String] absolute path
        def expand_path(path)
          File.expand_path(path)
        end

        # Validate that the file exists
        #
        # @raise [DefinitionNotFoundError] if file doesn't exist
        def validate_file_exists!
          return if File.exist?(path)

          raise DefinitionNotFoundError,
                "Definition file not found: #{path}"
        end

        # Validate that the file is readable
        #
        # @raise [DefinitionLoadError] if file is not readable
        def validate_file_readable!
          return if File.readable?(path)

          raise DefinitionLoadError,
                "Definition file is not readable: #{path}"
        end

        # Get the file modification time
        #
        # @return [Time] file mtime
        # @raise [DefinitionLoadError] if mtime cannot be determined
        def get_mtime
          File.mtime(path)
        rescue Errno::ENOENT, Errno::EACCES => e
          raise DefinitionLoadError,
                "Cannot access file metadata for #{path}: #{e.message}"
        end

        # Read the file content
        #
        # @return [String] file content
        # @raise [DefinitionLoadError] if file cannot be read
        def read_file
          File.read(path)
        rescue Errno::EACCES => e
          raise DefinitionLoadError,
                "Permission denied reading file #{path}: #{e.message}"
        rescue IOError, SystemCallError => e
          raise DefinitionLoadError,
                "Error reading file #{path}: #{e.message}"
        end
      end
    end
  end
end
