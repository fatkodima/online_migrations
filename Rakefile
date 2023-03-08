# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

require "rdoc/task"

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.title    = "OnlineMigrations"
  rdoc.options << "--line-numbers"
  rdoc.rdoc_files.include("README.md")
  rdoc.rdoc_files.include("docs/background_migrations.md")
  rdoc.rdoc_files.include("docs/configuring.md")
  rdoc.rdoc_files.include("lib/**/*.rb")
end

require "rubocop/rake_task"

RuboCop::RakeTask.new
task default: [:rubocop, :test]
