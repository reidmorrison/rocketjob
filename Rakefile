require 'rake/clean'
require 'rake/testtask'

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require 'rocket_job/version'

task :gem do
  system "gem build rocket_job.gemspec"
end

task :publish => :gem do
  system "git tag -a v#{RocketJob::VERSION} -m 'Tagging #{RocketJob::VERSION}'"
  system "git push --tags"
  system "gem push rocket_job-#{RocketJob::VERSION}.gem"
  system "rm rocket_job-#{RocketJob::VERSION}.gem"
end

desc "Run Test Suite"
task :test do
  Rake::TestTask.new(:functional) do |t|
    t.test_files = FileList['test/*_test.rb']
    t.verbose    = true
  end

  Rake::Task['functional'].invoke
end

task :default => :test
