# $Id$
#
# scanf for Ruby
#
# Ad hoc tests of IO#scanf (needs to be expanded)


$:.unshift("..")
require "scanf.rb"

fh = File.new("data.txt", "r")
p fh.pos
p fh.scanf("%s%s")
p fh.scanf("%da fun%s")
p fh.pos
