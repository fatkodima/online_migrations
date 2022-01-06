# frozen_string_literal: true

module OnlineMigrations
  # Class representing configuration options for the gem.
  class Config
    include ErrorMessages

    attr_accessor :error_messages

    def initialize
      @error_messages = ERROR_MESSAGES
    end
  end
end
