source "https://rubygems.org"

gemspec

gem "activerecord", "~> 6.0"
# gem "mongoid", "~> 7.3"
gem "mongoid", git: "https://github.com/reidmorrison/mongoid", branch: "ruby_3"

gem "amazing_print"
gem "appraisal"
gem "rake"
gem "rubyzip", platform: :ruby
# BZip2 file support
gem "bzip2-ffi"

gem "activerecord-jdbcsqlite3-adapter", platform: :jruby
gem "jdbc-sqlite3", platform: :jruby
gem "sqlite3", "~> 1.4", platform: :ruby

# v1.8.9 blows up with `NoMethodError: undefined method 'deep_merge!' for {}:Concurrent::Hash` on JRuby
gem "i18n", "1.8.7"

group :development do
  gem "rubocop"

  # Test against master
  # gem "iostreams", git: "https://github.com/rocketjob/iostreams"

  # Testing against locally cloned repos
  # gem "iostreams", path: "../iostreams"
  # gem "semantic_logger", path: "../semantic_logger"
  # gem "symmetric-encryption", path: "../symmetric-encryption"
end

group :test do
  gem "minitest"
  gem "minitest-reporters"
  gem "minitest-stub_any_instance"
end
