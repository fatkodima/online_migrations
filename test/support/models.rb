# frozen_string_literal: true

class User < ActiveRecord::Base
  has_many :projects
end

class Project < ActiveRecord::Base
end

class ShardRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to shards: {
    # Can be removed for Active Record 7.1+.
    # See https://github.com/rails/rails/pull/48353.
    default: { writing: :shard_one, reading: :shard_one },
    shard_one: { writing: :shard_one, reading: :shard_one },
    shard_two: { writing: :shard_two, reading: :shard_two },
  }
end

class Dog < ShardRecord
end
