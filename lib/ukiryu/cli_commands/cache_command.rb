# frozen_string_literal: true

require 'thor'
require_relative '../definition/definition_cache'

module Ukiryu
  module CliCommands
    # Manage definition cache
    #
    # The cache command allows users to view and manage the definition cache.
    class CacheCommand < Thor
      class_option :verbose, type: :boolean, default: false
      class_option :dry_run, type: :boolean, default: false

      desc 'info', 'Show cache information'
      def info
        show_cache_info
      end

      desc 'stats', 'Show detailed cache statistics'
      def stats
        show_cache_stats
      end

      desc 'clear', 'Clear all cached definitions'
      def clear
        clear_cache
      end

      private

      # Show cache information
      def show_cache_info
        cache = Ukiryu::Definition::DefinitionCache.instance
        stats = cache.stats

        say 'Definition Cache:', :cyan
        say '', :clear

        say "Status: #{stats[:size].positive? ? 'Active' : 'Empty'}", stats[:size].positive? ? :green : :dim
        say "Entries: #{stats[:size]}", :white
        say "TTL: #{stats[:ttl]} seconds", :white
        say "Refresh Strategy: #{stats[:refresh_strategy]}", :white

        return unless stats[:entries] && !stats[:entries].empty?

        say '', :clear
        say 'Cached Definitions:', :white
        stats[:entries].each do |key|
          say "  - #{key}", :dim
        end
      end

      # Clear the cache
      def clear_cache
        cache = Ukiryu::Definition::DefinitionCache.instance

        if options[:dry_run]
          say 'Dry run: Would clear cache', :cyan
          count = cache.stats[:size]
          say "Entries to be cleared: #{count}", :white
          return
        end

        count = cache.clear

        say "✓ Cache cleared (#{count} entries)", :green
      end

      # Show cache statistics
      def show_cache_stats
        cache = Ukiryu::Definition::DefinitionCache.instance
        stats = cache.stats

        say 'Cache Statistics:', :cyan
        say '', :clear

        say "Total Entries: #{stats[:size]}", :white
        say "TTL: #{stats[:ttl]} seconds (#{(stats[:ttl] / 60).round(1)} minutes)", :white
        say "Refresh Strategy: #{stats[:refresh_strategy]}", :white
        say '', :clear

        return unless stats[:entries] && !stats[:entries].empty?

        say 'Cached Keys:', :white
        stats[:entries].each do |key|
          entry = cache.get(key)
          if entry
            age = Time.now - entry.loaded_at
            stale = entry.stale? ? ' (stale)' : ''
            say "  - #{key}#{stale}", :white
            say "    Age: #{age.round}s", :dim
          else
            say "  - #{key} (empty)", :dim
          end
        end
      end
    end
  end
end
