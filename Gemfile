# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in online_migrations.gemspec
gemspec

gem "minitest"
gem "minitest-mock"
gem "rake"
gem "sidekiq", "7.3.3"
gem "rubocop"
gem "rubocop-minitest"
gem "rubocop-disable_syntax"

gem "yard"
gem "pg"
gem "logger" # remove when dropping activerecord < 8 support

if defined?(@ar_gem_requirement)
  gem "activerecord", @ar_gem_requirement
  gem "railties", @ar_gem_requirement
else
  gem "activerecord" # latest
  gem "railties" # to test generator
end
