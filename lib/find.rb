#
# find.rb: the Find module for processing all files under a given directory.
#

#
# The +Find+ module supports the top-down traversal of a set of file paths.
#
# For example, to total the size of all files under your home directory,
# ignoring anything in a "dot" directory (e.g. $HOME/.ssh):
#
#   require 'find'
#
#   total_size = 0
#
#   Find.find(ENV["HOME"]) do |path|
#     if FileTest.directory?(path)
#       if File.basename(path)[0] == ?.
#         Find.prune       # Don't look any further into this directory.
#       else
#         next
#       end
#     else
#       total_size += FileTest.size(path)
#     end
#   end
#
module Find

  #
  # Calls the associated block with the name of every file and directory listed
  # as arguments, then recursively on their subdirectories, and so on.
  #
  # See the +Find+ module documentation for an example.
  #
  def find(*paths) # :yield: path
    paths.collect!{|d| d.dup}
    while file = paths.shift
      catch(:prune) do
        next unless File.exist? file
	yield file.dup.taint
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
		paths.unshift f.untaint
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

  #
  # Skips the current file or directory, restarting the loop with the next
  # entry. If the current file is a directory, that directory will not be
  # recursively entered. Meaningful only within the block associated with
  # Find::find.
  #
  # See the +Find+ module documentation for an example.
  #
  def prune
    throw :prune
  end

  module_function :find, :prune
end
