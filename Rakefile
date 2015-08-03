require 'rake/clean'
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

desc 'Run Test Suite'
task :test do
  Rake::TestTask.new(:functional) do |t|
    t.test_files = FileList['test/**/*_test.rb']
    t.verbose    = true
  end

  Rake::Task['functional'].invoke
end

task default: :test
