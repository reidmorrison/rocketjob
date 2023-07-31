$LOAD_PATH.push File.expand_path("lib", __dir__)

require "rocket_job/version"

Gem::Specification.new do |s|
  s.name                  = "rocketjob"
  s.version               = RocketJob::VERSION
  s.platform              = Gem::Platform::RUBY
  s.authors               = ["Reid Morrison"]
  s.homepage              = "https://rocketjob.io"
  s.summary               = "Ruby's missing batch processing system."
  s.executables           = %w[rocketjob rocketjob_perf]
  s.files                 = Dir["lib/**/*", "bin/*", "LICENSE.txt", "README.md"]
  s.license               = "Apache-2.0"
  s.required_ruby_version = ">= 2.7"
  s.add_dependency "aasm", ">= 5.1"
  s.add_dependency "concurrent-ruby", ">= 1.1"
  s.add_dependency "fugit", ">= 1.4"
  s.add_dependency "iostreams", ">= 1.9"
  s.add_dependency "mongoid", ">= 7.5"
  s.add_dependency "semantic_logger", ">= 4.7"
  s.add_dependency "symmetric-encryption", ">= 4.3"
end
