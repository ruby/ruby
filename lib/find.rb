# Usage:
#	require "find.rb"
#
#	Find.find('/foo','/bar') {|f| ...}
#  or
#	include Find
#	find('/foo','/bar') {|f| ...}
#

module Find
  extend Find
  
  def findpath(path, ary)
    ary.push(path)
    d = Dir.open(path)
    for f in d
      continue if f =~ /^\.\.?$/
      f = path + "/" + f
      if File.directory? f
	findpath(f, ary)
      else
	ary.push(f)
      end
    end
  end
  private :findpath

  def find(*path)
    ary = []
    for p in path
      findpath(p, ary)
      for f in ary
	yield f
      end
    end
  end
  module_function :find
end
