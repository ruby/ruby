#
# tempfile - manipulates temporary files
#
# $Id$
#

require 'delegate'

# A class for managing temporary files.  This library is written to be
# thread safe.
class Tempfile < SimpleDelegator
  MAX_TRY = 10
  @@cleanlist = []

  # Creates a temporary file of mode 0600 in the temporary directory
  # whose name is basename.pid.n and opens with mode "w+".  A Tempfile
  # object works just like a File object.
  #
  # If tmpdir is omitted, the temporary directory is determined by
  # ENV['TMPDIR'], ENV['TMP'] and and ENV['TEMP'] in the order named.
  # If none of them is available, or when $SAFE > 0 and the given
  # tmpdir is tainted, it uses /tmp. (Note that ENV values are
  # tainted by default)
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

  # Opens or reopens the file with mode "r+".
  def open
    @tmpfile.close if @tmpfile
    @tmpfile = File.open(@tmpname, 'r+')
    @data[1] = @tmpfile
    __setobj__(@tmpfile)
  end

  def _close	# :nodoc:
    @tmpfile.close if @tmpfile
    @data[1] = @tmpfile = nil
  end    
  protected :_close

  # Closes the file.  If the optional flag is true, unlinks the file
  # after closing.
  #
  # If you don't explicitly unlink the temporary file, the removal
  # will be delayed until the object is finalized.
  def close(unlink_now=false)
    if unlink_now
      close!
    else
      _close
    end
  end

  # Closes and unlinks the file.
  def close!
    _close
    @clean_proc.call
    ObjectSpace.undefine_finalizer(self)
  end

  # Unlinks the file.  On UNIX-like systems, it is often a good idea
  # to unlink a temporary file immediately after creating and opening
  # it, because it leaves other programs zero chance to access the
  # file.
  def unlink
    # keep this order for thread safeness
    File.unlink(@tmpname) if File.exist?(@tmpname)
    @@cleanlist.delete(@tmpname) if @@cleanlist
  end
  alias delete unlink

  # Returns the full path name of the temporary file.
  def path
    @tmpname
  end

  # Returns the size of the temporary file.  As a side effect, the IO
  # buffer is flushed before determining the size.
  def size
    if @tmpfile
      @tmpfile.flush
      @tmpfile.stat.size
    else
      0
    end
  end
  alias length size

  class << self
    def callback(data)	# :nodoc:
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

    # Equivalent to new().
    def open(*args)
      new(*args)
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
