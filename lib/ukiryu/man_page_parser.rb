# frozen_string_literal: true

require 'time'
require 'date'

module Ukiryu
  # Man page date parser for extracting version information
  #
  # Parses man page `.Dd` macros to extract dates as version information.
  # Used as fallback for system tools that don't support --version flags.
  #
  # @example Parse man page date
  #   date = ManPageParser.parse_date('/usr/share/man/man1/xargs.1')
  #   # => "2020-09-21"
  module ManPageParser
    class << self
      # Parse date from man page
      #
      # Extracts the `.Dd` (date) macro from a man page and converts it to
      # ISO 8601 format (YYYY-MM-DD).
      #
      # @param man_page_path [String] path to the man page file
      # @return [String, nil] ISO 8601 date string or nil if not found
      def parse_date(man_page_path)
        return nil unless man_page_path
        return nil unless File.exist?(man_page_path)

        content = File.read(man_page_path, encoding: 'UTF-8')

        # Find .Dd line
        # Format: .Dd Month DD, YYYY or .Dd DD Month YYYY
        dd_line = content.lines.find { |line| line =~ /^\.Dd\s+/ }

        return nil unless dd_line

        # Extract and parse date
        extract_date_from_dd_line(dd_line)
      rescue Errno::ENOENT, Errno::EACCES
        # File not found or inaccessible - silent failure
        nil
      end

      # Get man page path for a tool on current platform
      #
      # @param tool_name [String] the tool name
      # @param paths [Hash] platform-specific path templates
      # @return [String, nil] resolved man page path or nil
      def resolve_man_page_path(tool_name, paths = {})
        platform = Ukiryu::Platform.current

        # Get platform-specific path pattern
        path_pattern = paths[platform]

        return nil unless path_pattern

        # Expand tool name placeholder if present
        path_pattern.gsub('{tool}', tool_name)
      end

      # Parse date from multiple possible man page locations
      #
      # Tries multiple paths in order and returns the first successfully
      # parsed date.
      #
      # @param possible_paths [Array<String>] list of possible man page paths
      # @return [String, nil] ISO 8601 date string or nil if none found
      def parse_from_fallback(possible_paths)
        possible_paths.each do |path|
          date = parse_date(path)
          return date if date
        end

        nil
      end

      private

      # Extract date from .Dd line
      #
      # Handles various man page date formats:
      # - .Dd September 21, 2020
      # - .Dd 21 September 2020
      # - .Dd 2020-09-21
      #
      # @param dd_line [String] the .Dd line
      # @return [String, nil] ISO 8601 date or nil
      def extract_date_from_dd_line(dd_line)
        # Remove .Dd prefix
        date_str = dd_line.sub(/^\.Dd\s+/, '').strip

        # Try parsing different formats
        parsed = try_parse_date_formats(date_str)

        parsed&.strftime('%Y-%m-%d')
      end

      # Try parsing various date formats
      #
      # @param date_str [String] the date string
      # @return [Date, nil] parsed date or nil
      def try_parse_date_formats(date_str)
        # Format: "September 21, 2020" or "21 September 2020"
        # Parse with Date.parse which handles many formats
        Date.parse(date_str)
      rescue ArgumentError, Date::Error
        # Try regex-based extraction
        extract_date_with_regex(date_str)
      end

      # Extract date using regex patterns
      #
      # @param date_str [String] the date string
      # @return [Date, nil] parsed date or nil
      def extract_date_with_regex(date_str)
        # Match "Month DD, YYYY" or "DD Month YYYY" or "YYYY-MM-DD"
        patterns = [
          /(\w+)\s+(\d+),?\s+(\d{4})/, # Month DD, YYYY
          /(\d+)\s+(\w+)\s+(\d{4})/,      # DD Month YYYY
          /(\d{4})-(\d{2})-(\d{2})/       # YYYY-MM-DD
        ]

        patterns.each do |pattern|
          match = date_str.match(pattern)
          next unless match

          captures = match.captures

          # Determine order based on capture count
          if captures[0]&.length == 4 # First capture is year (YYYY-MM-DD)
            year, month, day = captures
            return Date.new(year.to_i, month.to_i, day.to_i)
          elsif captures[2]&.length == 4 # Last capture is year
            month_or_day, _, year = captures

            # Check if first is month name or number
            if month_or_day =~ /^\d+$/
              # DD Month YYYY format
              day, month_name, year = captures
            else
              # Month DD, YYYY format
              month_name, day, year = captures
            end
            month = month_name_to_number(month_name)
            return Date.new(year.to_i, month, day.to_i) if month
          end
        end

        nil
      end

      # Convert month name to number
      #
      # @param month_name [String] the month name
      # @return [Integer, nil] month number (1-12) or nil
      def month_name_to_number(month_name)
        months = {
          'january' => 1, 'jan' => 1,
          'february' => 2, 'feb' => 2,
          'march' => 3, 'mar' => 3,
          'april' => 4, 'apr' => 4,
          'may' => 5,
          'june' => 6, 'jun' => 6,
          'july' => 7, 'jul' => 7,
          'august' => 8, 'aug' => 8,
          'september' => 9, 'sep' => 9, 'sept' => 9,
          'october' => 10, 'oct' => 10,
          'november' => 11, 'nov' => 11,
          'december' => 12, 'dec' => 12
        }

        months[month_name.downcase]
      end
    end
  end
end
