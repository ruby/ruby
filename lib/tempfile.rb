#
# $Id$
# Copyright (C) 1998 akira yamada. All rights reserved. 
# This file can be distributed under the terms of the Ruby.

# The class for temporary files.
#  o creates a temporary file, which name is "basename.pid.n" with mode "w+".
#  o Tempfile objects can be used like IO object.
#  o created temporary files are removed on closing or script termination.
#  o file mode of the temporary files are 0600.

require 'delegate'
require 'final'

class Tempfile < SimpleDelegater
  Max_try = 10

  def initialize(basename, tmpdir = '/tmp')
    @tmpdir = tmpdir

    umask = File.umask(0177)
    cwd = Dir.getwd
    Dir.chdir(@tmpdir)
    begin
      n = 0
      while true
	begin
	  @tmpname = sprintf('%s.%d.%d', basename, $$, n)
	  unless File.exist?(@tmpname)
	    File.symlink('.', @tmpname + '.lock')
	    break
	  end
	rescue
	  raise "cannot generate tmpfile `%s'" % @tmpname if n >= Max_try
	  #sleep(1)
	end
	n += 1
      end

      @clean_files = proc {|id| 
	if File.exist?(@tmpdir + '/' + @tmpname)
	  File.unlink(@tmpdir + '/' + @tmpname) 
	end
	if File.exist?(@tmpdir + '/' + @tmpname + '.lock')
	  File.unlink(@tmpdir + '/' + @tmpname + '.lock')
	end
      }
      ObjectSpace.define_finalizer(self, @clean_files)

      @tmpfile = open(@tmpname, 'w+')
      super(@tmpfile)
      File.unlink(@tmpname + '.lock')
    ensure
      File.umask(umask)
      Dir.chdir(cwd)
    end
  end

  def Tempfile.open(*args)
    Tempfile.new(*args)
  end

  def close
    @tmpfile.close
    @clean_files.call
    ObjectSpace.undefine_finalizer(self)
  end
end
