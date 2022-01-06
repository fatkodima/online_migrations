# OnlineMigrations

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/online_migrations`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'online_migrations'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install online_migrations

## Usage

TODO: Write usage instructions here

## Checks

Potentially dangerous operations:

- [adding an index non-concurrently](#adding-an-index-non-concurrently)

### Adding an index non-concurrently

#### Bad

Adding an index non-concurrently blocks writes.

```ruby
class AddIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email, unique: true
  end
end
```

#### Good

Add indexes concurrently.

```ruby
class AddIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :users, :email, unique: true, algorithm: :concurrently
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail. Also, note that indexes on new tables (those created in the same migration) don't require this.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/online_migrations.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
