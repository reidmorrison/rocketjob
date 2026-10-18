#!/usr/bin/env bash
# Runs every command of the v7 / v8 compatibility harness, then compares the results, see README.md.
#
#   test/compat/run_all.sh          run everything, then drop the harness's databases
#   test/compat/run_all.sh --keep   keep the databases, to look at them afterwards
#
# Run it directly, not under `bundle exec`, since it runs each version under its own bundle:
#   v7: rocketjob 7.0.0 and iostreams 2.1.0 from rubygems.org   (test/compat/v7/Gemfile)
#   v8: this repository, with iostreams from GitHub main        (test/compat/v8/Gemfile)
set -euo pipefail

COMPAT="$(cd "$(dirname "$0")" && pwd)"
RUN="$COMPAT/run.rb"
KEEP="${1:-}"

v7() { BUNDLE_GEMFILE="$COMPAT/v7/Gemfile" bundle exec ruby "$RUN" "$@"; }
v8() { BUNDLE_GEMFILE="$COMPAT/v8/Gemfile" bundle exec ruby "$RUN" "$@"; }

for version in v7 v8; do
  export BUNDLE_GEMFILE="$COMPAT/$version/Gemfile"
  bundle check > /dev/null || bundle install
done
unset BUNDLE_GEMFILE

# Drop the databases at the end, also when a step fails, unless --keep.
cleanup() { if [[ "$KEEP" != "--keep" ]]; then v8 drop; fi; }
trap cleanup EXIT

# Scenarios 1-11: each version runs the property checks, then the matrix, in a database of its own. The matrix runs
# last, since each command drops the collections of its database first, so that --keep keeps the jobs of the matrix.
v7 checks
v8 checks
v7 matrix
v8 matrix

# Scenario 12: v7 saves the jobs, one copy for each way of processing them, without processing them. Then
#   v7     is processed by v7 with #perform_now (the baseline)
#   v8     is processed by v8 with #perform_now (v8 reading the jobs that v7 saved)
#   mixed  is loaded and saved by v8, then processed by v7 (a v7 worker during a rolling upgrade)
#   v7w    is processed the way a v7 server's worker processes it
#   v8w    is processed the way a v8 server's worker processes it
v7 persist-create
v7 persist-process v7
v8 persist-process v8
v8 persist-touch mixed
v7 persist-process mixed
v7 persist-worker v7w
v8 persist-worker v8w

ruby "$COMPAT/compare.rb" all
