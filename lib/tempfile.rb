#
# $Id$
#
# The class for temporary files.
#  o creates a temporary file, which name is "basename.pid.n" with mode "w+".
#  o Tempfile objects can be used like IO object.
#  o with tempfile.close(true) created temporary files are removed.
#  o created files are also removed on script termination.
#  o with Tempfile#open, you can reopen the temporary file.
#  o file mode of the temporary files are 0600.

require 'delegate'

class Tempfile < SimpleDelegator
  Max_try = 10

  def Tempfile.callback(path, data)
    pid = $$
    lambda{
      if pid == $$ 
	print "removing ", path, "..." if $DEBUG
	data[0].close if data[0]
	if File.exist?(path)
	  File.unlink(path) 
	end
	if File.exist?(path + '.lock')
	  Dir.rmdir(path + '.lock')
	end
	print "done\n" if $DEBUG
      end
    }
  end

  def initialize(basename, tmpdir=ENV['TMPDIR']||ENV['TMP']||ENV['TEMP']||'/tmp')
    if $SAFE > 0 and tmpdir.tainted?
      tmpdir = '/tmp'
    end
    n = 0
    while true
      begin
	tmpname = sprintf('%s/%s%d.%d', tmpdir, basename, $$, n)
	lock = tmpname + '.lock'
	unless File.exist?(tmpname) or File.exist?(lock)
	  Dir.mkdir(lock)
	  break
	end
      rescue
	raise "cannot generate tempfile `%s'" % tmpname if n >= Max_try
	#sleep(1)
      end
      n += 1
    end

    @protect = []
    @clean_files = Tempfile.callback(tmpname, @protect)
    ObjectSpace.define_finalizer(self, @clean_files)

    @tmpfile = File.open(tmpname, File::RDWR|File::CREAT|File::EXCL, 0600)
    @protect[0] = @tmpfile
    @tmpname = tmpname
    super(@tmpfile)
    Dir.rmdir(lock)
  end

  def Tempfile.open(*args)
    Tempfile.new(*args)
  end

  def open
    @tmpfile.close if @tmpfile
    @tmpfile = File.open(@tmpname, 'r+')
    @protect[0] = @tmpfile
    __setobj__(@tmpfile)
  end

  def close(real=false)
    @tmpfile.close if @tmpfile
    @protect[0] = @tmpfile = nil
    if real
      @clean_files.call
      ObjectSpace.undefine_finalizer(self)
    end
  end

  def path
    @tmpname
  end

  def size
    if @tmpfile
      @tmpfile.flush
      @tmpfile.stat.size
    else
      0
    end
  end
end

if __FILE__ == $0
#  $DEBUG = true
  f = Tempfile.new("foo")
  f.print("foo\n")
  f.close
  f.open
  p f.gets # => "foo\n"
  f.close(true)
end
