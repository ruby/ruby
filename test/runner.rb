exit if defined?(CROSS_COMPILING)
require 'test/unit'

rcsid = %w$Id$
Version = rcsid[2].scan(/\d+/).collect!(&method(:Integer)).freeze
Release = rcsid[3].freeze

exit Test::Unit::AutoRunner.run(false, File.dirname($0))
