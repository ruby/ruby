require 'test/unit'

rcsid = %w$Id: runner.rb,v 1.11.2.1 2005/02/17 02:56:47 ntalbott Exp $
Version = rcsid[2].scan(/\d+/).collect!(&method(:Integer)).freeze
Release = rcsid[3].freeze

exit Test::Unit::AutoRunner.run(true, File.dirname($0))
