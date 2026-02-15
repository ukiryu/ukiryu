# frozen_string_literal: true

require 'fileutils'

module Ukiryu
  # Backward compatibility shim for RegisterAutoManager
  #
  # @deprecated Use Ukiryu::Register instead
  class RegisterAutoManager
    # GitHub repository URL for the register
    REGISTER_URL = 'https://github.com/ukiryu/register'

    # Default local directory for the register
    DEFAULT_DIR = '~/.ukiryu/register'

    # Error class for backward compatibility
    class RegisterError < StandardError; end

    class << self
      # @deprecated Use Register.default.path instead
      def register_path
        Register.default.path
      rescue Register::Error => e
        raise RegisterError, e.message
      end

      # @deprecated Use Register.exists? instead
      def register_exists?
        Register.exists?
      end

      # @deprecated Use Register.default.update! instead
      def update_register(force: false)
        register = Register.default
        if force
          FileUtils.rm_rf(register.path) if Dir.exist?(register.path)
          register.clone!
        else
          register.update!
        end
        true
      rescue Register::Error => e
        raise RegisterError, e.message
      rescue Git::Error => e
        raise RegisterError, "Failed to update register: #{e.message}"
      rescue StandardError => e
        raise RegisterError, "Register update failed: #{e.message}"
      end

      # @deprecated Use Register.default.info instead
      def register_info
        register = begin
          Register.default
        rescue Register::Error
          nil
        end

        return { status: :not_found } unless register

        info = register.info

        {
          status: info[:valid?] ? :ok : :invalid,
          path: info[:path],
          source: info[:source],
          branch: info[:git_info]&.dig(:branch),
          commit: info[:git_info]&.dig(:commit),
          last_update: info[:git_info]&.dig(:last_update),
          tools_count: info[:tools_count]
        }
      end

      # @deprecated Use Register.at(path) or check for register existence differently
      # This method resolves path without triggering auto-clone
      def resolve_register_path
        # Check environment variable
        env_path = ENV['UKIRYU_REGISTER']
        return env_path if env_path && Dir.exist?(env_path)

        # Check development register
        begin
          dev_path = calculate_dev_path
          return dev_path.to_s if dev_path&.exist?
        rescue StandardError
          nil
        end

        # Check user clone
        user_path = File.expand_path(DEFAULT_DIR)
        Dir.exist?(user_path) ? user_path : nil
      end

      private

      def calculate_dev_path
        this_file = Pathname.new(__FILE__).realpath
        this_file.parent.parent.parent.parent.join('register')
      rescue StandardError
        nil
      end
    end
  end
end
