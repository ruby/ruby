# This file includes the settings for "make test-all" and "make test-tool".
# Note that this file is loaded not only by test/runner.rb but also by tool/lib/test/unit/parallel.rb.

# Prevent test-all from using bundled gems
["GEM_HOME", "GEM_PATH"].each do |gem_env|
  # Preserve the gem environment prepared by tool/runruby.rb for test-tool, which uses bundled gems.
  ENV["BUNDLED_#{gem_env}"] = ENV[gem_env]

  ENV[gem_env] = "".freeze
end
ENV["GEM_SKIP"] = "".freeze

ENV.delete("RUBY_CODESIGN")

Warning[:experimental] = false
# The tests assert the output of the ruby processes they spawn verbatim, so the
# children need this too.  It has to precede the bare "-" that common.mk puts in
# RUBYOPT, which ends the option scan.
ENV["RUBYOPT"] = (["-W:no-experimental"] | ENV["RUBYOPT"].to_s.split).join(" ")

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require 'test/unit'

require "profile_test_all" if ENV.key?('RUBY_TEST_ALL_PROFILE')
require "tracepointchecker"
require "zombie_hunter"
require "iseq_loader_checker"
require "gc_checker"
require_relative "../test-coverage.rb" if ENV.key?('COVERAGE')
