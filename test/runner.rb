# frozen_string_literal: true

# Should be done in rubygems test files?
ENV["GEM_SKIP"] = ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze

# Get bundled gems on load path
Dir.glob("#{__dir__}/../gems/*/*.gemspec")
  .reject {|f| f =~ /minitest|test-unit|power_assert/ }
  .map {|f| $LOAD_PATH.unshift File.join(File.dirname(f), "lib") }

require_relative '../tool/test/runner'
