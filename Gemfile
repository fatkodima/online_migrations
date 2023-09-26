# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in online_migrations.gemspec
gemspec

gem "minitest", "~> 5.0"
gem "rake", "~> 12.0"
gem "rubocop", "< 2"
gem "rubocop-minitest"

if RUBY_VERSION >= "2.7"
  gem "rubocop-disable_syntax"
end

gem "yard"

if defined?(@ar_gem_requirement)
  gem "activerecord", @ar_gem_requirement
  gem "railties", @ar_gem_requirement
else
  gem "activerecord" # latest
  gem "railties" # to test generator
end

if defined?(@pg_gem_requirement)
  gem "pg", @pg_gem_requirement
else
  gem "pg", "~> 1.2"
end
