# frozen_string_literal: true

module Ukiryu
  # Validation module for constraint-based option validation
  #
  # This module provides an OOP approach to validation using:
  # - Constraint objects (not procedural code)
  # - Validator classes that apply constraints
  # - Proper error objects (not just strings)
  #
  # @example Validating options
  #   validator = Validation::Validator.new(options, command_def)
  #   validator.validate!  # Raises ValidationError if invalid
  #   validator.valid?     # Returns true/false
  #   validator.errors     # Returns array of error messages
  module Validation
  end
end
