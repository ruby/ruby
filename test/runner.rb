require 'rbconfig'
exit if CROSS_COMPILING
require 'test/unit'

rcsid = %w$Id$
Version = rcsid[2].scan(/\d+/).collect!(&method(:Integer)).freeze
Release = rcsid[3].freeze

# this allows minitest and test/unit to run side by side.  test/unit
# tests with fork/signal were triggering minitest multiple times.
require 'minitest/unit'
MiniTest::Unit.disable_autorun

args = ARGV.dup
result = Test::Unit::AutoRunner.run(true, File.dirname($0))
result &&= MiniTest::Unit.new.run(args)

exit result

