######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

require "minitest/unit"

##
# Show your testing pride!

class PrideIO
  attr_reader :io

  # stolen from /System/Library/Perl/5.10.0/Term/ANSIColor.pm
  COLORS = (31..36).to_a
  CHARS = ["*"]

  def initialize io
    @io = io
    @colors = COLORS.cycle
    @chars  = CHARS.cycle
  end

  def print o
    case o
    when "." then
      io.print "\e[#{@colors.next}m#{@chars.next}\e[0m"
    when "E", "F" then
      io.print "\e[41m\e[37m#{o}\e[0m"
    else
      io.print o
    end
  end

  def method_missing msg, *args
    io.send(msg, *args)
  end
end

MiniTest::Unit.output = PrideIO.new(MiniTest::Unit.output)
