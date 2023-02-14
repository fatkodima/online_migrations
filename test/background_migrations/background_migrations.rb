# frozen_string_literal: true

module BackgroundMigrations
  class User < ActiveRecord::Base
    has_many :projects
  end

  class Project < ActiveRecord::Base
  end

  class MakeAllNonAdmins < OnlineMigrations::BackgroundMigration
    def relation
      User.all
    end

    def process_batch(users)
      users.update_all(admin: false)
    end
  end

  class FailingBatch < OnlineMigrations::BackgroundMigration
    class << self
      attr_accessor :process_batch_called, :fail_counter
    end
    self.process_batch_called = 0

    def relation
      User.all
    end

    def process_batch(_users)
      self.class.process_batch_called += 1
      raise "Boom!" if self.class.process_batch_called == self.class.fail_counter
    end
  end

  class EachBatchCalled < OnlineMigrations::BackgroundMigration
    class << self
      attr_accessor :process_batch_called
    end
    self.process_batch_called = 0

    def relation
      User.all
    end

    def process_batch(users)
      self.class.process_batch_called += 1
      users.update_all(admin: false)
    end
  end

  class EachBatchFails < OnlineMigrations::BackgroundMigration
    def relation
      User.all
    end

    def process_batch(_users)
      raise "Boom!"
    end
  end

  class RelationNotARRelation < OnlineMigrations::BackgroundMigration
    def relation
      [1, 2, 3]
    end
  end

  class JoinsRelation < OnlineMigrations::BackgroundMigration
    def relation
      User.joins(:projects)
    end
  end

  class OrderClauseRelation < OnlineMigrations::BackgroundMigration
    def relation
      User.order(:name)
    end
  end

  class EmptyRelation < OnlineMigrations::BackgroundMigration
    def relation
      User.none
    end
  end

  class MigrationWithCount < OnlineMigrations::BackgroundMigration
    def relation
      User.all
    end

    def process_batch(_users)
      # no-op
    end

    def count
      relation.count
    end
  end

  class NotAMigration
    def relation; end
    def process_batch(*); end
  end
end
