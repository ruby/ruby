#!/usr/bin/env ruby
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++


require 'stringio'
require 'rubygems/user_interaction'

class MockGemUi < Gem::StreamUI
  class TermError < RuntimeError; end

  def initialize(input="")
    super(StringIO.new(input), StringIO.new, StringIO.new)
    @terminated = false
    @banged = false
  end
  
  def input
    @ins.string
  end

  def output
    @outs.string
  end

  def error
    @errs.string
  end

  def banged?
    @banged
  end

  def terminated?
    @terminated
  end

  def terminate_interaction!(status=1)
    @terminated = true 
    @banged = true
    fail TermError
  end

  def terminate_interaction(status=0)
    @terminated = true
    fail TermError
  end
end
