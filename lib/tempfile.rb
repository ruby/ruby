#
# $Id$
#
# This is a class for managing temporary files.
#
#  o Tempfile::new("basename") creates a temporary file whose name is
#    "basename.pid.n" and opens with mode "w+".
#  o A Tempfile object can be treated as an IO object.
#  o The temporary directory is determined by ENV['TMPDIR'],
#    ENV['TMP'], and ENV['TEMP'] in the order named, and if none of
#    them is available, it is set to /tmp.
#  o When $SAFE > 0, you should specify a directory via the second argument
#    of Tempfile::new(), or it will end up finding an ENV value tainted and
#    pick /tmp.  In case you don't have it, an exception will be raised.
#  o Tempfile#close! gets the temporary file removed immediately.
#  o Otherwise, the removal is delayed until the object is finalized.
#  o With Tempfile#open, you can reopen the temporary file.
#  o The file mode for the temporary files is 0600.
#  o This library is (considered to be) thread safe.

require 'delegate'

class Tempfile < SimpleDelegator
  MAX_TRY = 10
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
      retry if failure < MAX_TRY
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

  def _close
    @tmpfile.close if @tmpfile
    @data[1] = @tmpfile = nil
  end    
  protected :_close

  def close(real=false)
    if real
      close!
    else
      _close
    end
  end

  def close!
    _close
    @clean_proc.call
    ObjectSpace.undefine_finalizer(self)
  end

  def unlink
    # keep this order for thread safeness
    File.unlink(@tmpname) if File.exist?(@tmpname)
    @@cleanlist.delete(@tmpname) if @@cleanlist
  end
  alias delete unlink

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
  f.close!
end
