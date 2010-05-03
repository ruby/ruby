#
# tempfile - manipulates temporary files
#
# $Id$
#

require 'delegate'
require 'tmpdir'
require 'thread'

# A class for managing temporary files.  This library is written to be
# thread safe.
class Tempfile < DelegateClass(File)
  MAX_TRY = 10
  @@cleanlist = []
  @@lock = Mutex.new

  # Creates a temporary file of mode 0600 in the temporary directory,
  # opens it with mode "w+", and returns a Tempfile object which
  # represents the created temporary file.  A Tempfile object can be
  # treated just like a normal File object.
  #
  # The basename parameter is used to determine the name of a
  # temporary file.  If an Array is given, the first element is used
  # as prefix string and the second as suffix string, respectively.
  # Otherwise it is treated as prefix string.
  #
  # If tmpdir is omitted, the temporary directory is determined by
  # Dir::tmpdir provided by 'tmpdir.rb'.
  # When $SAFE > 0 and the given tmpdir is tainted, it uses
  # /tmp. (Note that ENV values are tainted by default)
  def initialize(basename, *rest)
    # I wish keyword argument settled soon.
    if opts = Hash.try_convert(rest[-1])
      rest.pop
    end
    tmpdir = rest[0] || Dir::tmpdir
    if $SAFE > 0 and tmpdir.tainted?
      tmpdir = '/tmp'
    end

    lock = tmpname = nil
    n = failure = 0
    @@lock.synchronize {
      begin
        begin
          tmpname = File.join(tmpdir, make_tmpname(basename, n))
          lock = tmpname + '.lock'
          n += 1
        end while @@cleanlist.include?(tmpname) or
            File.exist?(lock) or File.exist?(tmpname)
        Dir.mkdir(lock)
      rescue
        failure += 1
        retry if failure < MAX_TRY
        raise "cannot generate tempfile `%s'" % tmpname
      end
    }

    @data = [tmpname]
    @clean_proc = Tempfile.callback(@data)
    ObjectSpace.define_finalizer(self, @clean_proc)

    if opts.nil?
      opts = []
    else
      opts = [opts]
    end
    @tmpfile = File.open(tmpname, File::RDWR|File::CREAT|File::EXCL, 0600, *opts)
    @tmpname = tmpname
    @@cleanlist << @tmpname
    @data[1] = @tmpfile
    @data[2] = @@cleanlist

    super(@tmpfile)

    # Now we have all the File/IO methods defined, you must not
    # carelessly put bare puts(), etc. after this.

    Dir.rmdir(lock)
  end

  def make_tmpname(basename, n)
    case basename
    when Array
      prefix, suffix = *basename
    else
      prefix, suffix = basename, ''
    end
 
    t = Time.now.strftime("%Y%m%d")
    path = "#{prefix}#{t}-#{$$}-#{rand(0x100000000).to_s(36)}-#{n}#{suffix}"
  end
  private :make_tmpname

  # Opens or reopens the file with mode "r+".
  def open
    @tmpfile.close if @tmpfile
    @tmpfile = File.open(@tmpname, 'r+')
    @data[1] = @tmpfile
    __setobj__(@tmpfile)
  end

  def _close	# :nodoc:
    @tmpfile.close if @tmpfile
    @tmpfile = nil
    @data[1] = nil if @data
  end
  protected :_close

  #Closes the file.  If the optional flag is true, unlinks the file
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
    @data = @tmpname = nil
  end

  # Unlinks the file.  On UNIX-like systems, it is often a good idea
  # to unlink a temporary file immediately after creating and opening
  # it, because it leaves other programs zero chance to access the
  # file.
  def unlink
    # keep this order for thread safeness
    begin
      if File.exist?(@tmpname)
        File.unlink(@tmpname)
      end
      @@cleanlist.delete(@tmpname)
      @data = @tmpname = nil
      ObjectSpace.undefine_finalizer(self)
    rescue Errno::EACCES
      # may not be able to unlink on Windows; just ignore
    end
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
      Proc.new {
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

    # If no block is given, this is a synonym for new().
    #
    # If a block is given, it will be passed tempfile as an argument,
    # and the tempfile will automatically be closed when the block
    # terminates.  The call returns the value of the block.
    def open(*args)
      tempfile = new(*args)

      if block_given?
	begin
	  yield(tempfile)
	ensure
	  tempfile.close
	end
      else
	tempfile
      end
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
