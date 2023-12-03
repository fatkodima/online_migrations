# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Base class for all records used by this gem.
    #
    # Can be extended to setup different database where all tables related to
    # online_migrations will live.
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
