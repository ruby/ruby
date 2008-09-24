require 'rbconfig'
exit if CROSS_COMPILING
require 'test/unit'

rcsid = %w$Id$
Version = rcsid[2].scan(/\d+/).collect!(&method(:Integer)).freeze
Release = rcsid[3].freeze

class Module
  def tu_deprecation_warning old, new = nil, kaller = nil
    # stfu - for now...
  end
end

test_dir = File.dirname(__FILE__)

# not sure why these are needed now... but whatever
$:.push(*Dir[File.join(test_dir, '*')].find_all { |path| File.directory? path })

test_files = (Dir[File.join(test_dir, "test_*.rb")] +
              Dir[File.join(test_dir, "**/test_*.rb")])

flags, files = ARGV.partition { |arg| arg =~ /^-/ }
test_files = test_files.grep(Regexp.union(*files)) unless files.empty?

ARGV.replace flags

test_files.each do |test|
  require test
end
