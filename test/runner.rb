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

files = []
other = []

until ARGV.empty? do
  arg = ARGV.shift
  case arg
  when /^-x$/ then
    filter = ARGV.shift
    test_files.reject! { |f| f =~ /#{filter}/ }
  when /^--$/ then
    other.push(*ARGV)
    ARGV.clear
    break
  when /^-/ then
    other << arg
  else
    files << arg
  end
end

test_files = test_files.grep(Regexp.union(*files)) unless files.empty?

ARGV.replace other # this passes through to miniunit

test_files.each do |test|
  require test
end
