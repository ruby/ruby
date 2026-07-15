# frozen_string_literal: true

require_relative "rubygems_version_manager"
ENV["RGV"] ||= "."

# RGV=system runs specs against system RubyGems: processes spawned by specs
# boot it untouched (see `Spec::Helpers#sys_exec`). The test harness itself
# still runs on the checked out RubyGems, because the repo's lib/ dir is
# unavoidably on its load path and would get mixed into an older RubyGems.
# The system RubyGems version is captured here, while it's still the one
# loaded, so version-gated specs can check the version actually under test.
source = ENV["RGV"]
if source == "system"
  ENV["BUNDLER_SPEC_SYSTEM_RUBYGEMS_VERSION"] ||= Gem::VERSION
  source = "."
end

RubygemsVersionManager.new(source).switch
