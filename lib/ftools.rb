class << File

  TOO_BIG = 1024 * 1024 * 2 # 2MB

  def catname from, to
    if FileTest.directory? to
      File.join to.sub(%r([/\\]$), ''), basename(from)
    else
      to
    end
  end

# copy file

  def syscopy from, to
    to = catname(from, to)

    fsize = size(from)
    fsize = 1024 if fsize < 512
    fsize = TOO_BIG if fsize > TOO_BIG

    fmode = stat(from).mode
    tpath = to
    not_exist = !exist?(tpath)

    from = open(from, "r")
    from.binmode
    to = open(to, "w")
    to.binmode

    begin
      while true
	r = from.sysread(fsize)
	rsize = r.size
        w = 0
	while w < rsize
	  t = to.syswrite(r[w, rsize - w])
	  w += t
	end
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

  def copy from, to, verbose = false
    $stderr.print from, " -> ", catname(from, to), "\n" if verbose
    syscopy from, to
  end

  alias cp copy

# move file

  def move from, to, verbose = false
    to = catname(from, to)
    $stderr.print from, " -> ", to, "\n" if verbose

    if RUBY_PLATFORM =~ /djgpp|cygwin|mswin32/ and FileTest.file? to
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

#  compare two files
#   true:  identical
#   false: not identical

  def compare from, to, verbose = false
    $stderr.print from, " <=> ", to, "\n" if verbose
    fsize = size(from)
    fsize = 1024 if fsize < 512
    fsize = TOO_BIG if fsize > TOO_BIG

    from = open(from, "r")
    from.binmode
    to = open(to, "r")
    to.binmode

    ret = false
    fr = tr = ''

    begin
      while fr == tr
	fr = from.read(fsize)
	if fr
	  tr = to.read(fr.size)
	else
	  ret = to.read(fsize)
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

#  unlink files safely

  def safe_unlink(*files)
    verbose = if files[-1].is_a? String then false else files.pop end
    begin
      $stderr.print files.join(" "), "\n" if verbose
      chmod 0777, *files
      unlink(*files)
    rescue
#      STDERR.print "warning: Couldn't unlink #{files.join ' '}\n"
    end
  end

  alias rm_f safe_unlink

  def makedirs(*dirs)
    verbose = if dirs[-1].is_a? String then false else dirs.pop end
#    mode = if dirs[-1].is_a? Fixnum then dirs.pop else 0755 end
    mode = 0755
    for dir in dirs
      next if FileTest.directory? dir
      parent = dirname(dir)
      makedirs parent unless FileTest.directory? parent
      $stderr.print "mkdir ", dir, "\n" if verbose
      if basename(dir) != ""
	Dir.mkdir dir, mode
      end
    end
  end

  alias mkpath makedirs

  alias o_chmod chmod

  vsave, $VERBOSE = $VERBOSE, false
  def chmod(mode, *files)
    verbose = if files[-1].is_a? String then false else files.pop end
    $stderr.printf "chmod %04o %s\n", mode, files.join(" ") if verbose
    o_chmod mode, *files
  end
  $VERBOSE = vsave

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
