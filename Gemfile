# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in online_migrations.gemspec
gemspec

gem "minitest", "~> 5.0"
gem "rake", "~> 12.0"
gem "yard"

if defined?(@ar_gem_requirement)
  gem "activerecord", @ar_gem_requirement
  gem "railties", @ar_gem_requirement
else
  gem "activerecord" # latest
  gem "railties" # to test generator

  # Run Rubocop only on latest rubies, because it is incompatible with older versions.
  gem "rubocop", "~> 1.24"
end

if defined?(@pg_gem_requirement)
  gem "pg", @pg_gem_requirement
else
  gem "pg", "~> 1.2"
end
