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
  s.summary     = 'Enterprise Batch Processing System for Ruby, JRuby, and Rubinius'
  s.description = 'Enterprise Batch Processing System focused on performance, scalability, reliability, and visibility of every job in the system.'
  s.executables = ['rocketjob']
  s.files       = Dir['lib/**/*', 'bin/*', 'LICENSE.txt', 'Rakefile', 'README.md']
  s.test_files  = Dir['test/**/*']
  s.license     = 'GPL-3.0'
  s.has_rdoc    = true
  s.add_dependency 'aasm', '~> 4.3'
  s.add_dependency 'semantic_logger', '~> 2.19'
  s.add_dependency 'mongo_ha', '~> 1.11'
  s.add_dependency 'mongo', '~> 1.11'
  s.add_dependency 'mongo_mapper', '~> 0.13'
  s.add_dependency 'symmetric-encryption', '~> 3.0'
  s.add_dependency 'concurrent-ruby', '~> 1.0'
  s.add_dependency 'rufus-scheduler', '~> 3.0'
end
