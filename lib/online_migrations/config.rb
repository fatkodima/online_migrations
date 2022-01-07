# frozen_string_literal: true

module OnlineMigrations
  # Class representing configuration options for the gem.
  class Config
    include ErrorMessages

    # Whether to perform checks when migrating down
    #
    # Disabled by default
    # @return [Boolean]
    #
    attr_accessor :check_down

    attr_accessor :error_messages

    def initialize
      @error_messages = ERROR_MESSAGES
      @check_down = false
    end
  end
end
