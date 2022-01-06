# frozen_string_literal: true

require_relative "lib/online_migrations/version"

Gem::Specification.new do |spec|
  spec.name          = "online_migrations"
  spec.version       = OnlineMigrations::VERSION
  spec.authors       = ["fatkodima"]
  spec.email         = ["fatkodima123@gmail.com"]

  spec.summary       = "Catch unsafe PostgreSQL migrations in development and run them easier in production"
  spec.homepage      = "https://github.com/fatkodima/online_migrations"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.1.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 4.2"
end
