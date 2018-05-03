# sqlite3 and activerecord gems added to test the around_perform transaction support.
appraise 'mongoid_5' do
  gem 'activerecord', '~> 4.2.0'
  gem 'activerecord-jdbcsqlite3-adapter', '~> 1.0', platform: :jruby
  gem 'mongoid', '~> 5.0'
end

appraise 'mongoid_6' do
  gem 'activerecord', '~> 5.1.0'
  gem 'activerecord-jdbcsqlite3-adapter', platform: :jruby
  gem 'mongoid', '~> 6.0'
end

appraise 'mongoid_7' do
  gem 'activerecord', '~> 5.2.0'
  gem 'activerecord-jdbcsqlite3-adapter', platform: :jruby
  gem 'mongoid', '~> 7.0'
end
