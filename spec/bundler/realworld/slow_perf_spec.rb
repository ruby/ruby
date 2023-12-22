# frozen_string_literal: true

require "spec_helper"

RSpec.describe "bundle install with complex dependencies", realworld: true do
  it "resolves quickly" do
    gemfile <<-G
      source 'https://rubygems.org'

      gem "actionmailer"
      gem "mongoid", ">= 0.10.2"
    G

    expect { bundle "lock" }.to take_less_than(18) # seconds
  end

  it "resolves quickly (case 2)" do
    gemfile <<-G
      source "https://rubygems.org"

      gem 'metasploit-erd'
      gem 'rails-erd'
      gem 'yard'

      gem 'coveralls'
      gem 'rails'
      gem 'simplecov'
      gem 'rspec-rails'
    G

    expect { bundle "lock" }.to take_less_than(30) # seconds
  end

  it "resolves big gemfile quickly" do
    gemfile <<~G
      # frozen_string_literal: true

      source "https://rubygems.org"

      gem "rails"
      gem "pg", ">= 0.18", "< 2.0"
      gem "goldiloader"
      gem "awesome_nested_set"
      gem "circuitbox"
      gem "passenger"
      gem "globalid"
      gem "rack-cors"
      gem "rails-pg-extras"
      gem "linear_regression_trend"
      gem "rack-protection"
      gem "pundit"
      gem "remote_ip_proxy_scrubber"
      gem "bcrypt"
      gem "searchkick"
      gem "excon"
      gem "faraday_middleware-aws-sigv4"
      gem "typhoeus"
      gem "sidekiq"
      gem "sidekiq-undertaker"
      gem "sidekiq-cron"
      gem "storext"
      gem "appsignal"
      gem "fcm"
      gem "business_time"
      gem "tzinfo"
      gem "holidays"
      gem "bigdecimal"
      gem "progress_bar"
      gem "redis"
      gem "hiredis"
      gem "state_machines"
      gem "state_machines-audit_trail"
      gem "state_machines-activerecord"
      gem "interactor"
      gem "ar_transaction_changes"
      gem "redis-rails"
      gem "seed_migration"
      gem "lograge"
      gem "graphiql-rails", group: :development
      gem "graphql"
      gem "pusher"
      gem "rbnacl"
      gem "jwt"
      gem "json-schema"
      gem "discard"
      gem "money"
      gem "strip_attributes"
      gem "validates_email_format_of"
      gem "audited"
      gem "concurrent-ruby"
      gem "with_advisory_lock"

      group :test do
        gem "rspec-sidekiq"
        gem "simplecov", require: false
      end

      group :development, :test do
        gem "byebug", platform: :mri
        gem "guard"
        gem "guard-bundler"
        gem "guard-rspec"
        gem "rb-fsevent"
        gem "rspec_junit_formatter"
        gem "rspec-collection_matchers"
        gem "rspec-rails"
        gem "rspec-retry"
        gem "state_machines-rspec"
        gem "dotenv-rails"
        gem "database_cleaner-active_record"
        gem "database_cleaner-redis"
        gem "timecop"
      end

      gem "factory_bot_rails"
      gem "faker"

      group :development do
        gem "listen"
        gem "sql_queries_count"
        gem "rubocop"
        gem "rubocop-performance"
        gem "rubocop-rspec"
        gem "rubocop-rails"
        gem "brakeman"
        gem "bundler-audit"
        gem "solargraph"
        gem "annotate"
      end
    G

    expect do
      bundle "lock", env: { "DEBUG_RESOLVER" => "1" }, raise_on_error: !Bundler.feature_flag.bundler_3_mode?
    end.to take_less_than(30) # seconds
  end
end
