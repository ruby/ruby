# frozen_string_literal: true

# Should be done in rubygems test files?
ENV["GEM_SKIP"] = ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze
ENV.delete("RUBY_CODESIGN")

Warning[:experimental] = false

require_relative '../tool/test/runner'
