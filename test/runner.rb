require 'test/unit'

rcsid = %w$Id$
Version = rcsid[2].scan(/\d+/).collect!(&method(:Integer)).freeze rescue nil
Release = rcsid[3].freeze rescue nil

exit Test::Unit::AutoRunner.run(true, File.dirname($0))
