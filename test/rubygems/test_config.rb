#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rbconfig'
require 'rubygems'

class TestConfig < RubyGemTestCase

  def test_datadir
    datadir = Config::CONFIG['datadir']
    assert_equal "#{datadir}/xyz", Config.datadir('xyz')
  end

end

