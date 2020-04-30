$LOAD_PATH.push File.expand_path("lib", __dir__)

require "rocket_job/version"

Gem::Specification.new do |s|
  s.name                  = "rocketjob"
  s.version               = RocketJob::VERSION
  s.platform              = Gem::Platform::RUBY
  s.authors               = ["Reid Morrison"]
  s.homepage              = "http://rocketjob.io"
  s.summary               = "Ruby's missing batch processing system."
  s.executables           = %w[rocketjob rocketjob_perf]
  s.files                 = Dir["lib/**/*", "bin/*", "LICENSE.txt", "README.md"]
  s.license               = "Apache-2.0"
  s.required_ruby_version = ">= 2.3"
  s.add_dependency "aasm", ">= 4.12"
  s.add_dependency "concurrent-ruby", "~> 1.1"
  s.add_dependency "iostreams", "~> 1.2"
  s.add_dependency "mongoid", "~> 7.0"
  s.add_dependency "semantic_logger", "~> 4.1"
  s.add_dependency "symmetric-encryption", ">= 4.0"
end
