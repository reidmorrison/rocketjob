$LOAD_PATH.push File.expand_path("lib", __dir__)

require "rocket_job/version"

Gem::Specification.new do |s|
  s.name                  = "rocketjob"
  s.version               = RocketJob::VERSION
  s.platform              = Gem::Platform::RUBY
  s.authors               = ["Reid Morrison"]
  s.homepage              = "https://rocketjob.io"
  s.summary               = "Process millions of records across thousands of workers. " \
                            "A distributed, MongoDB-backed batch processing system for Ruby."
  s.description           = "Rocket Job is a distributed, priority-based, MongoDB-backed batch processing system for Ruby. " \
                            "Run conventional background jobs, or split a single job's input into slices and process it " \
                            "concurrently across thousands of workers, spilling from memory to disk so very large files " \
                            "never fall over."
  s.executables           = %w[rocketjob rocketjob_perf rocketjob_batch_perf]
  s.files                 = Dir["lib/**/*", "bin/*", "LICENSE.txt", "README.md"]
  s.license               = "Apache-2.0"
  s.required_ruby_version = ">= 3.2.0"
  s.add_dependency "aasm", ">= 5.1"
  s.add_dependency "concurrent-ruby", ">= 1.1"
  s.add_dependency "fugit", ">= 1.4"
  s.add_dependency "iostreams", "~> 2.0"
  s.add_dependency "mongoid", ">= 8.1"
  s.add_dependency "semantic_logger", "~> 5.0"
  s.add_dependency "symmetric-encryption", "~> 4.6"
  s.metadata = {
    "bug_tracker_uri"       => "https://github.com/reidmorrison/rocketjob/issues",
    "changelog_uri"         => "https://github.com/reidmorrison/rocketjob/releases",
    "documentation_uri"     => "https://rocketjob.io",
    "homepage_uri"          => "https://rocketjob.io",
    "source_code_uri"       => "https://github.com/reidmorrison/rocketjob/tree/v#{RocketJob::VERSION}",
    "rubygems_mfa_required" => "true"
  }
end
