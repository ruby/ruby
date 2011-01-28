######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'stringio'
require 'rubygems/user_interaction'

##
# This Gem::StreamUI subclass records input and output to StringIO for
# retrieval during tests.

class Gem::MockGemUi < Gem::StreamUI
  class TermError < RuntimeError; end

  module TTY

    attr_accessor :tty

    def tty?()
      @tty = true unless defined?(@tty)
      @tty
    end

    def noecho
      yield self
    end
  end

  def initialize(input = "")
    ins = StringIO.new input
    outs = StringIO.new
    errs = StringIO.new

    ins.extend TTY
    outs.extend TTY
    errs.extend TTY

    super ins, outs, errs

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

    raise TermError unless status == 0
    raise Gem::SystemExitException, status
  end

end

