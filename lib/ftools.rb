# 
# = ftools.rb: Extra tools for the File class
#
# Author:: WANTANABE, Hirofumi
# Documentation:: Zachary Landau
#
# This library can be distributed under the terms of the Ruby license.
# You can freely distribute/modify this library.
#
# It is included in the Ruby standard library.
#
# == Description
#
# +ftools+ adds several (class, not instance) methods to the File class, for copying, moving,
# deleting, installing, and comparing files, as well as creating a directory path.  See the
# File class for details.
#
# +fileutils+ contains all or nearly all the same functionality and more, and is a recommended
# option over +ftools+. 
#


#
# When you
#
#   require 'ftools'
#
# then the File class aquires some utility methods for copying, moving, and deleting files, and
# more.
#
# See the method descriptions below, and consider using +fileutils+ as it is more
# comprehensive.
#
class File
end

class << File

  BUFSIZE = 8 * 1024

  #
  # If +to+ is a valid directory, +from+ will be appended to +to+, adding
  # and escaping backslashes as necessary. Otherwise, +to+ will be returned.
  # Useful for appending +from+ to +to+ only if the filename was not specified
  # in +to+. 
  #
  def catname(from, to)
    if FileTest.directory? to
      File.join to.sub(%r([/\\]$), ''), basename(from)
    else
      to
    end
  end

  #
  # Copies a file +from+ to +to+. If +to+ is a directory, copies +from+
  # to <tt>to/from</tt>.
  #
  def syscopy(from, to)
    to = catname(from, to)

    fmode = stat(from).mode
    tpath = to
    not_exist = !exist?(tpath)

    from = open(from, "rb")
    to = open(to, "wb")

    begin
      while true
	to.syswrite from.sysread(BUFSIZE)
      end
    rescue EOFError
      ret = true
    rescue
      ret = false
    ensure
      to.close
      from.close
    end
    chmod(fmode, tpath) if not_exist
    ret
  end

  #
  # Copies a file +from+ to +to+ using #syscopy. If +to+ is a directory,
  # copies +from+ to <tt>to/from</tt>. If +verbose+ is true, <tt>from -> to</tt>
  # is printed.
  #
  def copy(from, to, verbose = false)
    $deferr.print from, " -> ", catname(from, to), "\n" if verbose
    syscopy from, to
  end

  alias cp copy

  #
  # Moves a file +from+ to +to+ using #syscopy. If +to+ is a directory,
  # copies from +from+ to <tt>to/from</tt>. If +verbose+ is true, <tt>from -> to</tt>
  # is printed.
  #
  def move(from, to, verbose = false)
    to = catname(from, to)
    $deferr.print from, " -> ", to, "\n" if verbose

    if RUBY_PLATFORM =~ /djgpp|(cyg|ms|bcc)win|mingw/ and FileTest.file? to
      unlink to
    end
    fstat = stat(from)
    begin
      rename from, to
    rescue
      begin
        symlink File.readlink(from), to and unlink from
      rescue
	from_stat = stat(from)
	syscopy from, to and unlink from
	utime(from_stat.atime, from_stat.mtime, to)
	begin
	  chown(fstat.uid, fstat.gid, to)
	rescue
	end
      end
    end
  end

  alias mv move

  #
  # Returns +true+ iff the contents of files +from+ and +to+ are
  # identical. If +verbose+ is +true+, <tt>from <=> to</tt> is printed.
  #
  def compare(from, to, verbose = false)
    $deferr.print from, " <=> ", to, "\n" if verbose

    return false if stat(from).size != stat(to).size

    from = open(from, "rb")
    to = open(to, "rb")

    ret = false
    fr = tr = ''

    begin
      while fr == tr
	fr = from.read(BUFSIZE)
	if fr
	  tr = to.read(fr.size)
	else
	  ret = to.read(BUFSIZE)
	  ret = !ret || ret.length == 0
	  break
	end
      end
    rescue
      ret = false
    ensure
      to.close
      from.close
    end
    ret
  end

  alias cmp compare

  #
  # Removes a list of files. Each parameter should be the name of the file to
  # delete. If the last parameter isn't a String, verbose mode will be enabled.
  # Returns the number of files deleted.
  #
  def safe_unlink(*files)
    verbose = if files[-1].is_a? String then false else files.pop end
    begin
      $deferr.print files.join(" "), "\n" if verbose
      chmod 0777, *files
      unlink(*files)
    rescue
#      $deferr.print "warning: Couldn't unlink #{files.join ' '}\n"
    end
  end

  alias rm_f safe_unlink

  #
  # Creates a directory and all its parent directories.
  # For example,
  #
  #	File.makedirs '/usr/lib/ruby'
  #
  # causes the following directories to be made, if they do not exist.
  #	* /usr
  #	* /usr/lib
  #	* /usr/lib/ruby
  #
  # You can pass several directories, each as a parameter. If the last
  # parameter isn't a String, verbose mode will be enabled.
  #
  def makedirs(*dirs)
    verbose = if dirs[-1].is_a? String then false else dirs.pop end
#    mode = if dirs[-1].is_a? Fixnum then dirs.pop else 0755 end
    mode = 0755
    for dir in dirs
      parent = dirname(dir)
      next if parent == dir or FileTest.directory? dir
      makedirs parent unless FileTest.directory? parent
      $deferr.print "mkdir ", dir, "\n" if verbose
      if basename(dir) != ""
        begin
          Dir.mkdir dir, mode
        rescue SystemCallError
          raise unless File.directory? dir
        end
      end
    end
  end

  alias mkpath makedirs

  alias o_chmod chmod

  vsave, $VERBOSE = $VERBOSE, false

  #
  # Changes permission bits on +files+ to the bit pattern represented
  # by +mode+. If the last parameter isn't a String, verbose mode will
  # be enabled.
  #
  #   File.chmod 0755, 'somecommand'
  #   File.chmod 0644, 'my.rb', 'your.rb', true
  #
  def chmod(mode, *files)
    verbose = if files[-1].is_a? String then false else files.pop end
    $deferr.printf "chmod %04o %s\n", mode, files.join(" ") if verbose
    o_chmod mode, *files
  end
  $VERBOSE = vsave

  #
  # If +src+ is not the same as +dest+, copies it and changes the permission
  # mode to +mode+. If +dest+ is a directory, destination is <tt>dest/src</tt>.
  # If +mode+ is not set, default is used. If +verbose+ is set to true, the
  # name of each file copied will be printed.
  #
  def install(from, to, mode = nil, verbose = false)
    to = catname(from, to)
    unless FileTest.exist? to and cmp from, to
      safe_unlink to if FileTest.exist? to
      cp from, to, verbose
      chmod mode, to, verbose if mode
    end
  end

end

# vi:set sw=2:
