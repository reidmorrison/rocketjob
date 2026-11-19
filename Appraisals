appraise "mongoid_8.1" do
  # json 3 rejects the quirks_mode: option that Active Support before 8.1 passes to JSON.generate in #to_json
  gem "json", "~> 2.21"
  gem "activejob", "~> 7.2.3"
  gem "activerecord", "~> 7.2.3"
  gem "activerecord-jdbcsqlite3-adapter", "~> 72.1", platform: :jruby
  gem "jdbc-sqlite3", platform: :jruby
  gem "mongoid", "~> 8.1.0"
end

appraise "mongoid_9.0" do
  # json 3 rejects the quirks_mode: option that Active Support before 8.1 passes to JSON.generate in #to_json
  gem "json", "~> 2.21"
  gem "activejob", "~> 8.0.0"
  gem "activerecord", "~> 8.0.0"
  gem "activerecord-jdbcsqlite3-adapter", "~> 80.0.pre1", platform: :jruby
  gem "jdbc-sqlite3", platform: :jruby
  gem "mongoid", "~> 9.0.0"
end

appraise "mongoid_9.1" do
  gem "activejob", "~> 8.1.0"
  gem "activerecord", "~> 8.1.0"
  gem "mongoid", "~> 9.1.0"
end
