# frozen_string_literal: true

module Ukiryu
  module Shell
    # Cached shell instances for performance
    #
    # Reuses shell instances to avoid repeated object creation
    # in hot paths. Thread-safe using Mutex.
    #
    class InstanceCache
      @cache = {}
      @mutex = Mutex.new

      class << self
        # Get a cached shell instance for the given shell name
        #
        # @param name [Symbol] the shell name or platform group
        # @return [Shell::Base] a shell instance
        #
        def instance_for(name)
          @mutex.synchronize do
            @cache[name] ||= create_instance(name)
          end
        end

        # Clear the cache (mainly for testing)
        #
        def clear
          @mutex.synchronize do
            @cache.clear
          end
        end

        # Get cache size (for debugging)
        #
        # @return [Integer] number of cached instances
        #
        def size
          @mutex.synchronize do
            @cache.size
          end
        end

        private

        def create_instance(name)
          shell_class = Shell.class_for(name)
          shell_class.new
        end
      end
    end
  end
end
