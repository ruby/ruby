require 'rbconfig'
exit if CROSS_COMPILING
require 'test/unit'

rcsid = %w$Id$
Version = rcsid[2].scan(/\d+/).collect!(&method(:Integer)).freeze
Release = rcsid[3].freeze

# not sure why these are needed now... but whatever
$:.push(*Dir["test/*"].find_all { |path| File.directory? path })

class Module
  def tu_deprecation_warning old, new = nil, kaller = nil
    # stfu - for now...
  end
end

(Dir["test/test_*.rb"] + Dir["test/**/test_*.rb"]).each do |test|
  require test
end
