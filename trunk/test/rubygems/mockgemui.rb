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

  def terminated?
    @terminated
  end

  def terminate_interaction(status=0)
    @terminated = true

    raise TermError
  end

end

