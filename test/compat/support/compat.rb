# Loads the harness under the bundle that BUNDLE_GEMFILE names, see README.md: turns deprecation warnings on and
# records them before Rocket Job is loaded, then loads Rocket Job, the support code and the scenarios.
require_relative "paths"
require_relative "capture"

Compat::Capture.install

require "bundler/setup"
require "bigdecimal"
require "rocketjob"

require_relative "environment"
require_relative "result"
require_relative "job_factory"
require_relative "inspection"
require_relative "processing"
require_relative "scenario"
require_relative "runner"
require_relative "persisted_jobs"
require_relative "checks"
require_relative "command"
require_relative "../scenarios"
