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
    path.collect!{|d| d.dup}
    while file = path.shift
      catch(:prune) do
	yield file
	begin
	  if File.lstat(file).directory? then
	    d = Dir.open(file)
	    begin
	      for f in d
		next if f == "." or f == ".."
		if File::ALT_SEPARATOR and file =~ /^(?:[\/\\]|[A-Za-z]:[\/\\]?)$/ then
		  f = file + f
		elsif file == "/" then
		  f = "/" + f
		else
		  f = File.join(file, f)
		end
		path.unshift f
	      end
	    ensure
	      d.close
	    end
	  end
       rescue Errno::ENOENT, Errno::EACCES
	end
      end
    end
  end

  def prune
    throw :prune
  end
  module_function :find, :prune
end
