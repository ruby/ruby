# frozen_string_literal: true
require 'rbconfig'

require_relative "init"

case $0
when __FILE__
  dir = __dir__
when "-e"
  # No default directory
else
  dir = File.realdirpath("..", $0)
end
exit Test::Unit::AutoRunner.run(true, dir)
