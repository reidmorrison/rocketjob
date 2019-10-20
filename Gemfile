source 'https://rubygems.org'

gemspec

gem 'iostreams', path: '../iostreams'

gem 'activerecord', '~> 5.2.0'
gem 'mongoid', '~> 7.0'

gem 'appraisal'
gem 'awesome_print'
gem 'rake'
gem 'rubyzip', platform: :ruby

gem 'activerecord-jdbcsqlite3-adapter', platform: :jruby
gem 'jdbc-sqlite3', platform: :jruby
gem 'sqlite3', '~> 1.3.0', platform: :ruby

group :development do
  gem 'rubocop'

  # Test against master
  #gem 'iostreams', git: 'https://github.com/rocketjob/iostreams'

  # Testing against locally cloned repos
  # gem 'iostreams', path: '../iostreams'
  # gem 'semantic_logger', path: '../semantic_logger'
  # gem 'symmetric-encryption', path: '../symmetric-encryption'
end

group :test do
  gem 'minitest'
  gem 'minitest-stub_any_instance'
  gem 'minitest-reporters'
end
