# Runs one command of the v7 / v8 compatibility harness under the bundle that BUNDLE_GEMFILE names, and writes its
# results to <results>/<v7|v8>-<command>.json, see README.md and Compat::Command. run_all.sh runs every command under
# both bundles. For example, from the root of the repository:
#
#   BUNDLE_GEMFILE=test/compat/v8/Gemfile bundle exec ruby test/compat/run.rb matrix '^A0'
#
# It is not named *_test.rb, so `rake test` never collects it, and CI never runs it.
require_relative "support/compat"

Compat::Command.new(*ARGV).run
