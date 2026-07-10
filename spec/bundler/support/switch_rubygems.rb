# frozen_string_literal: true

require_relative "rubygems_version_manager"
ENV["RGV"] ||= "."

# RGV=system runs specs against system RubyGems: processes spawned by specs
# boot it untouched (see `Spec::Helpers#sys_exec`). The test harness itself
# still runs on the checked out RubyGems, because the repo's lib/ dir is
# unavoidably on its load path and would get mixed into an older RubyGems.
source = ENV["RGV"]
source = "." if source == "system"

RubygemsVersionManager.new(source).switch
