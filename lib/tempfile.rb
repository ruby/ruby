#
# $Id$
#
# The class for temporary files.
#  o creates a temporary file, which name is "basename.pid.n" with mode "w+".
#  o Tempfile objects can be used like IO object.
#  o the temporary directory is determined by ENV['TMPDIR'], ENV['TMP'],
#    ENV['TEMP'] and /tmp, in the order named.
#  o when $SAFE > 0, you should specify a directory via the second argument
#    of Tempfile::new(), or it will end up finding an ENV value tainted and
#    pick /tmp.  In case you don't have it, an exception will be raised.
#  o tempfile.close(true) gets the temporary file removed immediately.
#  o otherwise, the removal is delayed until the object is finalized.
#  o with Tempfile#open, you can reopen the temporary file.
#  o file mode of the temporary files is 0600.
#  o this library is (considered to be) thread safe.

require 'delegate'

class Tempfile < SimpleDelegator
  Max_try = 10
  @@cleanlist = []

  def Tempfile.callback(data)
    pid = $$
    lambda{
      if pid == $$ 
	path, tmpfile, cleanlist = *data

	print "removing ", path, "..." if $DEBUG

	tmpfile.close if tmpfile

	# keep this order for thread safeness
	File.unlink(path) if File.exist?(path)
	cleanlist.delete(path) if cleanlist

	print "done\n" if $DEBUG
      end
    }
  end

  def initialize(basename, tmpdir=ENV['TMPDIR']||ENV['TMP']||ENV['TEMP']||'/tmp')
    if $SAFE > 0 and tmpdir.tainted?
      tmpdir = '/tmp'
    end

    lock = nil
    n = failure = 0
    
    begin
      Thread.critical = true

      begin
	tmpname = sprintf('%s/%s%d.%d', tmpdir, basename, $$, n)
	lock = tmpname + '.lock'
	n += 1
      end while @@cleanlist.include?(tmpname) or
	File.exist?(lock) or File.exist?(tmpname)

      Dir.mkdir(lock)
    rescue
      failure += 1
      retry if failure < Max_try
      raise "cannot generate tempfile `%s'" % tmpname
    ensure
      Thread.critical = false
    end

    @data = [tmpname]
    @clean_proc = Tempfile.callback(@data)
    ObjectSpace.define_finalizer(self, @clean_proc)

    @tmpfile = File.open(tmpname, File::RDWR|File::CREAT|File::EXCL, 0600)
    @tmpname = tmpname
    @@cleanlist << @tmpname
    @data[1] = @tmpfile
    @data[2] = @@cleanlist

    super(@tmpfile)

    # Now we have all the File/IO methods defined, you must not
    # carelessly put bare puts(), etc. after this.

    Dir.rmdir(lock)
  end

  def Tempfile.open(*args)
    Tempfile.new(*args)
  end

  def open
    @tmpfile.close if @tmpfile
    @tmpfile = File.open(@tmpname, 'r+')
    @data[1] = @tmpfile
    __setobj__(@tmpfile)
  end

  def close(real=false)
    @tmpfile.close if @tmpfile
    @data[1] = @tmpfile = nil
    if real
      @clean_proc.call
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
