#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/doc_manager'

class TestGemDocManager < RubyGemTestCase

  def setup
    super

    @spec = quick_gem 'a'
    @manager = Gem::DocManager.new(@spec)
  end

  def test_uninstall_doc_unwritable
    orig_mode = File.stat(@spec.installation_path).mode
    File.chmod 0, @spec.installation_path

    assert_raise Gem::FilePermissionError do
      @manager.uninstall_doc
    end
  ensure
    File.chmod orig_mode, @spec.installation_path
  end

end

