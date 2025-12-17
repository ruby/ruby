# frozen_string_literal: true

BOX1 = Ruby::Box.new
BOX1.require_relative('a.1_1_0')

def yay
  BOX1::BOX_B::yay
end

yay
