$:.push File.expand_path('../lib', __FILE__)

# Maintain your gem's version:
require 'rocket_job/version'

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = 'rocketjob'
  s.version     = RocketJob::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Reid Morrison']
  s.email       = ['reidmo@gmail.com']
  s.homepage    = 'http://rocketjob.io'
  s.summary     = 'Batch Processing System for Ruby'
  s.description = 'Batch Processing System focused on performance, scalability, reliability, and visibility of every job in the system.'
  s.executables = ['rocketjob', 'rocketjob_perf']
  s.files       = Dir['lib/**/*', 'bin/*', 'LICENSE.txt', 'Rakefile', 'README.md']
  s.test_files  = Dir['test/**/*']
  s.license     = 'Apache-2.0'
  s.has_rdoc    = true
  s.add_dependency 'concurrent-ruby', '~> 1.0'
  s.add_dependency 'mongo_ha', '~> 1.11'
  s.add_dependency 'mongo_mapper', '~> 0.13'
  s.add_dependency 'semantic_logger', '~> 3.1'
  s.add_dependency 'symmetric-encryption', '>= 3.0'
  s.add_dependency 'aasm', '>= 4.3'
end
