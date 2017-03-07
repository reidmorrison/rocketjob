# Setup bundler to avoid having to run bundle exec all the time.
require 'rubygems'
require 'bundler/setup'

require 'rake/testtask'
require_relative 'lib/rocket_job/version'

task :gem do
  system 'gem build rocketjob.gemspec'
end

task publish: :gem do
  system "git tag -a v#{RocketJob::VERSION} -m 'Tagging #{RocketJob::VERSION}'"
  system 'git push --tags'
  system "gem push rocketjob-#{RocketJob::VERSION}.gem"
  system "rm rocketjob-#{RocketJob::VERSION}.gem"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
  t.warning = false
end

# By default run tests against all appraisals
if !ENV["APPRAISAL_INITIALIZED"] && !ENV["TRAVIS"]
  require 'appraisal'
  task default: :appraisal
else
  task default: :test
end
