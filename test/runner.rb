# frozen_string_literal: true

# NOTE: Do not add any settings here for test-all. Instead, please add it to ../tool/test/init.rb.

ENV["GEM_SKIP"] = ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze
ENV.delete("RUBY_CODESIGN")

require_relative '../tool/test/runner'
