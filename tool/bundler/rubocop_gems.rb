# frozen_string_literal: true

source "https://rubygems.org"

<<<<<<< HEAD:tool/bundler/rubocop_gems.rb
gem "rubocop", ">= 1.52.1", "< 2"
=======
ruby "~> 3.3.5", engine: "truffleruby", engine_version: "~> 24.2.0"
>>>>>>> 2afe89f8ce (Update truffleruby version):gemfiles/truffleruby/Gemfile

gem "minitest"
gem "irb"
gem "rake"
gem "rake-compiler"
gem "rspec"
gem "test-unit"
gem "rb_sys"
