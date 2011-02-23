require 'rbconfig'
require 'test/unit'
require_relative 'misc'

src_testdir = File.dirname(File.expand_path(__FILE__))

exit Test::Unit::AutoRunner.run(true, src_testdir)
