require 'stringio'
require 'rubygems/user_interaction'

class MockGemUi < Gem::StreamUI
  class TermError < RuntimeError; end

  module TTY

    attr_accessor :tty

    def tty?()
      @tty = true unless defined?(@tty)
      @tty
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

