# Setup bundler to avoid having to run bundle exec all the time.
require "rubygems"
require "bundler/setup"

require "rake/testtask"
require "rubocop/rake_task"
require_relative "lib/rocket_job/version"

RuboCop::RakeTask.new

task :gem do
  system "gem build rocketjob.gemspec"
end

task publish: :gem do
  system "git tag -a v#{RocketJob::VERSION} -m 'Tagging #{RocketJob::VERSION}'"
  system "git push --tags"
  system "gem push rocketjob-#{RocketJob::VERSION}.gem"
  system "rm rocketjob-#{RocketJob::VERSION}.gem"
end

desc "Regenerate docs/llms-full.txt from the docs markdown pages"
task :llms_full do
  # Reading order, matching the sidebar in docs/_config.yml. Keep the two in
  # step: a page added to the nav and not to this list is served on the site
  # and missing from llms-full.txt.
  pages  = %w[index installation guide batch jobs dirmon events mission_control deployment architecture upgrading]
  header = <<~HEADER
    # Rocket Job - Complete Documentation

    > Rocket Job is a distributed, priority-based background job and batch processing system for Ruby, backed by MongoDB.

    This file concatenates every page of https://rocketjob.reidmorrison.com for consumption by AI assistants.
    It is generated from the markdown sources in docs/ by `bundle exec rake llms_full`; do not edit it directly.
    A per-page index is available at https://rocketjob.reidmorrison.com/llms.txt
  HEADER

  sections = pages.map do |page|
    raw = File.read("docs/#{page}.md")

    # The page title lives in front matter, which the shared docs theme renders
    # as the h1. This file strips front matter, so lift the title back out and
    # re-emit it as a heading; without this every section would open with no
    # indication of which page it is. `heading` wins where a page sets both,
    # the same precedence the theme uses, and index.md is the one page here
    # that sets only `heading`. Quotes are stripped because a title containing
    # a colon has to be quoted in YAML: "Mission Control: The Web UI".
    front_matter = raw[/\A---\n(.*?)\n---\n/m, 1].to_s
    title        = %w[heading title].
                   filter_map { |key| front_matter[/^#{key}:[ \t]*(.+)$/, 1] }.
                   first.to_s.strip.delete_prefix('"').delete_suffix('"')

    text = raw.
           sub(/\A---\n.*?\n---\n/m, ""). # Jekyll front matter
           gsub(/^\{:.*\}\n/, "").        # kramdown attribute lines ({:toc}, {:.no_toc}, ...)
           gsub(/^\* TOC\n/, "").
           gsub(/^\*\*Contents\*\*\n/, "").
           gsub(/^!\[.*\n/, "")           # images (relative paths, useless in plain text)

    body = title.empty? ? text.strip : "## #{title}\n\n#{text.strip}"
    "<!-- source: docs/#{page}.md -->\n\n#{body}\n"
  end

  File.write("docs/llms-full.txt", ([header] + sections).join("\n\n---\n\n"))
  puts "Wrote docs/llms-full.txt (#{File.size('docs/llms-full.txt')} bytes)"
end

Rake::TestTask.new(:test) do |t|
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
  t.warning = false
end

# By default lint once, then run tests against all appraisals
if !ENV["APPRAISAL_INITIALIZED"] && !ENV["TRAVIS"]
  require "appraisal"
  task default: %i[rubocop appraisal]
else
  task default: :test
end
