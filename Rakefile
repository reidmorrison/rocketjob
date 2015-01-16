require 'rake/clean'
require 'rake/testtask'

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require 'batch_job/version'

task :gem do
  system "gem build batch_job.gemspec"
end

task :publish => :gem do
  system "git tag -a v#{BatchJob::VERSION} -m 'Tagging #{BatchJob::VERSION}'"
  system "git push --tags"
  system "gem push batch_job-#{BatchJob::VERSION}.gem"
  system "rm batch_job-#{BatchJob::VERSION}.gem"
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
