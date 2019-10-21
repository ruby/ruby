# frozen_string_literal: true

require 'rbconfig'

# Should be done in rubygems test files?
ENV["GEM_SKIP"] = ENV["GEM_HOME"] = ENV["GEM_PATH"] = "".freeze

# Get bundled gems on load path, try install dir first
gem_dir = "#{RbConfig::CONFIG['rubylibdir'].sub('/ruby/', '/ruby/gems/')}/gems"
unless Dir.exist? gem_dir
  gem_dir = "#{__dir__}/../gems"
end

# we need to pick up gems without a gemspec, so pick folders with a lib sub-folder
# the 'tz' gems for Windows do not have gemspec files
Dir.glob("#{gem_dir}/*/lib")
  .reject {|f| Dir.exist?(f) and f =~ /minitest|test-unit|power_assert/ }
  .map {|f| $LOAD_PATH.unshift f }

require_relative '../tool/test/runner'
