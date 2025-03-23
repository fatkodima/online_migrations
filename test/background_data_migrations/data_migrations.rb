# frozen_string_literal: true

module BackgroundDataMigrations
  class SimpleDataMigration < OnlineMigrations::DataMigration
    cattr_accessor :processed_objects, default: []
    cattr_accessor :after_start_called, default: 0
    cattr_accessor :around_process_called, default: 0
    cattr_accessor :after_stop_called, default: 0
    cattr_accessor :after_complete_called, default: 0
    cattr_accessor :after_pause_called, default: 0
    cattr_accessor :after_cancel_called, default: 0

    collection_batch_size(1000)

    def after_start
      self.class.after_start_called += 1
    end

    def around_process
      self.class.around_process_called += 1
      yield
    end

    def after_stop
      self.class.after_stop_called += 1
    end

    def after_complete
      self.class.after_complete_called += 1
    end

    def after_pause
      self.class.after_pause_called += 1
    end

    def after_cancel
      self.class.after_cancel_called += 1
    end
  end

  class MakeAllNonAdmins < SimpleDataMigration
    def initialize(*_dummy_args) end

    def collection
      User.in_batches
    end

    def process(relation)
      relation.update_all(admin: false)
    end
  end

  class MakeAllDogsNice < SimpleDataMigration
    def collection
      Dog.in_batches
    end

    def process(dogs)
      dogs.update_all(nice: true)
    end

    def count
      collection.count
    end
  end

  class EmptyCollection < SimpleDataMigration
    def collection
      User.none
    end

    def count
      0
    end
  end

  class MigrationWithCount < SimpleDataMigration
    def collection
      User.all
    end

    def process(_user)
      # no-op
    end

    def count
      collection.count
    end
  end

  class MigrationWithArguments < SimpleDataMigration
    def initialize(_arg1, _arg2)
      # no-op
    end

    def collection
      User.none
    end

    def process(_user)
      # no-op
    end
  end

  class NotAMigration
    def collection; end
    def process(*); end
  end

  class NoCollectionMigration < SimpleDataMigration
    def process(*); end
  end

  class NoProcessMigration < SimpleDataMigration
    def collection
      [1, 2, 3]
    end
  end

  class CustomEnumeratorMigration < SimpleDataMigration
    def build_enumerator(*)
      [1, 2, 3].each
    end

    def process(item)
      processed_objects << item
    end
  end

  class NonEnumeratorMigration < SimpleDataMigration
    def build_enumerator(*)
      1
    end

    def process(*); end
  end

  class RelationCollectionMigration < SimpleDataMigration
    def collection
      User.all
    end

    def process(user)
      processed_objects << user
    end
  end

  class BatchesCollectionMigration < SimpleDataMigration
    def collection
      User.in_batches(of: 1)
    end

    def process(relation)
      processed_objects << relation
    end
  end

  class BadBatchesCollectionMigration < SimpleDataMigration
    def collection
      User.in_batches(start: 1)
    end

    def process(*); end
  end

  class ArrayCollectionMigration < SimpleDataMigration
    def collection
      [1, 2, 3]
    end

    def process(item)
      processed_objects << item
    end
  end

  class BadCollectionMigration < SimpleDataMigration
    def collection
      1
    end

    def process(*); end
  end

  class WithCountMigration < SimpleDataMigration
    def collection
      [1, 2, 3]
    end

    def process(*); end

    def count
      collection.count
    end
  end

  class FailingProcessMigration < SimpleDataMigration
    def collection
      [1, 2]
    end

    def process(_item)
      raise "Boom!"
    end
  end
end
