# Usage:
#	require "find"
#
#	Find.find('/foo','/bar') {|f| ...}
#  or
#	include Find
#	find('/foo','/bar') {|f| ...}
#

module Find
  def find(*path)
    while file = path.shift
      catch(:prune) {
	yield file
	if File.directory? file then
	  d = Dir.open(file)
	  begin
	    for f in d
	      next if f =~ /^\.\.?$/
	      if File::ALT_SEPARATOR and file =~ /^([\/\\]|[A-Za-z]:[\/\\]?)$/ then
		f = file + f
	      elsif file == "/" then
		f = "/" + f
	      else
		f = file + "/" + f
	      end
	      path.unshift f
	    end
	  ensure
	    d.close
	  end
	end
      }
    end
  end

  def prune
    throw :prune
  end
  module_function :find, :prune
end
