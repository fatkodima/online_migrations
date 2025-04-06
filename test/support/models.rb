# frozen_string_literal: true

class User < ActiveRecord::Base
  has_many :projects
  has_many :commits
end

class Project < ActiveRecord::Base
  belongs_to :user
  has_many :commits
end

class Commit < ActiveRecord::Base
  belongs_to :user
end

class ShardRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to shards: {
    shard_one: { writing: :shard_one, reading: :shard_one },
    shard_two: { writing: :shard_two, reading: :shard_two },
  }
end

class Dog < ShardRecord
end
