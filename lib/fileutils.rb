# 
# = fileutils.rb
# 
# Copyright (c) 2000-2004 Minero Aoki <aamine@loveruby.net>
# 
# This program is free software.
# You can distribute/modify this program under the same terms of ruby.
# 
# == module FileUtils
# 
# Namespace for several file utility methods for copying, moving, removing, etc.
# 
# === Module Functions
# 
#   cd(dir, options)
#   cd(dir, options) {|dir| .... }
#   pwd()
#   mkdir(dir, options)
#   mkdir_p(dir, options)
#   rmdir(dir, options)
#   ln(old, new, options)
#   ln(list, destdir, options)
#   ln_s(old, new, options)
#   ln_s(list, destdir, options)
#   ln_sf(src, dest, options)
#   cp(src, dest, options)
#   cp(list, dir, options)
#   cp_r(src, dest, options)
#   cp_r(list, dir, options)
#   mv(src, dest, options)
#   mv(list, dir, options)
#   rm(list, options)
#   rm_r(list, options)
#   rm_rf(list, options)
#   install(src, dest, mode = <src's>, options)
#   chmod(mode, list, options)
#   touch(list, options)
#
# The <tt>options</tt> parameter is a hash of options, taken from the list
# <tt>:force</tt>, <tt>:noop</tt>, <tt>:preserve</tt>, and <tt>:verbose</tt>.
# <tt>:noop</tt> means that no changes are made.  The other two are obvious.
# Each method documents the options that it honours.
#
# All methods that have the concept of a "source" file or directory can take
# either one file or a list of files in that argument.  See the method
# documentation for examples.
#
# There are some `low level' methods, which does not accept any option:
#
#   uptodate?(file, cmp_list)
#   copy_entry(src, dest, preserve = false, dereference = false)
#   copy_file(src, dest, preserve = false, dereference = true)
#   copy_stream(srcstream, deststream)
#   compare_file(path_a, path_b)
#   compare_stream(stream_a, stream_b)
#
# == module FileUtils::Verbose
# 
# This module has all methods of FileUtils module, but it outputs messages
# before acting.  This equates to passing the <tt>:verbose</tt> flag to methods
# in FileUtils.
# 
# == module FileUtils::NoWrite
# 
# This module has all methods of FileUtils module, but never changes
# files/directories.  This equates to passing the <tt>:noop</tt> flag to methods
# in FileUtils.
# 
# == module FileUtils::DryRun
# 
# This module has all methods of FileUtils module, but never changes
# files/directories.  This equates to passing the <tt>:noop</tt> and
# <tt>:verbose</tt> flags to methods in FileUtils.
# 

module FileUtils

  # All methods are module_function.

  #
  # Options: (none)
  #
  # Returns the name of the current directory.
  #
  def pwd
    Dir.pwd
  end

  alias getwd pwd

  #
  # Options: noop verbose
  # 
  # Changes the current directory to the directory +dir+.
  # 
  # If this method is called with block, resumes to the old
  # working directory after the block execution finished.
  # 
  #   FileUtils.cd('/', :verbose => true)   # chdir and report it
  # 
  def cd(dir, options = {}, &block) # :yield: dir
    fu_check_options options, :noop, :verbose
    fu_output_message "cd #{dir}" if options[:verbose]
    Dir.chdir(dir, &block) unless options[:noop]
    fu_output_message 'cd -' if options[:verbose] and block
  end

  alias chdir cd


  #
  # Options: (none)
  # 
  # Returns true if +newer+ is newer than all +old_list+.
  # Non-existent files are older than any file.
  # 
  #   FileUtils.uptodate?('hello.o', %w(hello.c hello.h)) or \
  #       system 'make hello.o'
  # 
  def uptodate?(new, old_list, options = nil)
    raise ArgumentError, 'uptodate? does not accept any option' if options

    return false unless File.exist?(new)
    new_time = File.mtime(new)
    old_list.each do |old|
      if File.exist?(old)
        return false unless new_time > File.mtime(old)
      end
    end
    true
  end


  #
  # Options: mode noop verbose
  # 
  # Creates one or more directories.
  # 
  #   FileUtils.mkdir 'test'
  #   FileUtils.mkdir %w( tmp data )
  #   FileUtils.mkdir 'notexist', :noop => true  # Does not really create.
  #   FileUtils.mkdir 'tmp', :mode => 0700
  # 
  def mkdir(list, options = {})
    fu_check_options options, :mode, :noop, :verbose
    list = fu_list(list)
    fu_output_message "mkdir #{options[:mode] ? ('-m %03o ' % options[:mode]) : ''}#{list.join ' '}" if options[:verbose]
    return if options[:noop]

    list.each do |dir|
      fu_mkdir dir, options[:mode]
    end
  end

  #
  # Options: mode noop verbose
  # 
  # Creates a directory and all its parent directories.
  # For example,
  # 
  #   FileUtils.mkdir_p '/usr/local/lib/ruby'
  # 
  # causes to make following directories, if it does not exist.
  #     * /usr
  #     * /usr/local
  #     * /usr/local/lib
  #     * /usr/local/lib/ruby
  #
  # You can pass several directories at a time in a list.
  # 
  def mkdir_p(list, options = {})
    fu_check_options options, :mode, :noop, :verbose
    list = fu_list(list)
    fu_output_message "mkdir -p #{options[:mode] ? ('-m %03o ' % options[:mode]) : ''}#{list.join ' '}" if options[:verbose]
    return *list if options[:noop]

    list.map {|path| path.sub(%r</\z>, '') }.each do |path|
      # optimize for the most common case
      begin
        fu_mkdir path, options[:mode]
        next
      rescue SystemCallError
        next if File.directory?(path)
      end

      stack = []
      until path == stack.last   # dirname("/")=="/", dirname("C:/")=="C:/"
        stack.push path
        path = File.dirname(path)
      end
      stack.reverse_each do |path|
        begin
          fu_mkdir path, options[:mode]
        rescue SystemCallError => err
          raise unless File.directory?(path)
        end
      end
    end

    return *list
  end

  alias mkpath    mkdir_p
  alias makedirs  mkdir_p

  def fu_mkdir(path, mode)
    path = path.sub(%r</\z>, '')
    if mode
      Dir.mkdir path, mode
      File.chmod mode, path
    else
      Dir.mkdir path
    end
  end
  private :fu_mkdir


  #
  # Options: noop, verbose
  # 
  # Removes one or more directories.
  # 
  #   FileUtils.rmdir 'somedir'
  #   FileUtils.rmdir %w(somedir anydir otherdir)
  #   # Does not really remove directory; outputs message.
  #   FileUtils.rmdir 'somedir', :verbose => true, :noop => true
  # 
  def rmdir(list, options = {})
    fu_check_options options, :noop, :verbose
    list = fu_list(list)
    fu_output_message "rmdir #{list.join ' '}" if options[:verbose]
    return if options[:noop]

    list.each do |dir|
      Dir.rmdir dir.sub(%r</\z>, '')
    end
  end


  #
  # Options: force noop verbose
  #
  # <b><tt>ln( old, new, options = {} )</tt></b>
  #
  # Creates a hard link +new+ which points to +old+.
  # If +new+ already exists and it is a directory, creates a symbolic link +new/old+.
  # If +new+ already exists and it is not a directory, raises Errno::EEXIST.
  # But if :force option is set, overwrite +new+.
  # 
  #   FileUtils.ln 'gcc', 'cc', :verbose => true
  #   FileUtils.ln '/usr/bin/emacs21', '/usr/bin/emacs'
  # 
  # <b><tt>ln( list, destdir, options = {} )</tt></b>
  # 
  # Creates several hard links in a directory, with each one pointing to the
  # item in +list+.  If +destdir+ is not a directory, raises Errno::ENOTDIR.
  # 
  #   include FileUtils
  #   cd '/bin'
  #   ln %w(cp mv mkdir), '/usr/bin'   # Now /usr/bin/cp and /bin/cp are linked.
  # 
  def ln(src, dest, options = {})
    fu_check_options options, :force, :noop, :verbose
    fu_output_message "ln#{options[:force] ? ' -f' : ''} #{[src,dest].flatten.join ' '}" if options[:verbose]
    return if options[:noop]

    fu_each_src_dest0(src, dest) do |s,d|
      remove_file d, true if options[:force]
      File.link s, d
    end
  end

  alias link ln

  #
  # Options: force noop verbose
  #
  # <b><tt>ln_s( old, new, options = {} )</tt></b>
  # 
  # Creates a symbolic link +new+ which points to +old+.  If +new+ already
  # exists and it is a directory, creates a symbolic link +new/old+.  If +new+
  # already exists and it is not a directory, raises Errno::EEXIST.  But if
  # :force option is set, overwrite +new+.
  # 
  #   FileUtils.ln_s '/usr/bin/ruby', '/usr/local/bin/ruby'
  #   FileUtils.ln_s 'verylongsourcefilename.c', 'c', :force => true
  # 
  # <b><tt>ln_s( list, destdir, options = {} )</tt></b>
  # 
  # Creates several symbolic links in a directory, with each one pointing to the
  # item in +list+.  If +destdir+ is not a directory, raises Errno::ENOTDIR.
  #
  # If +destdir+ is not a directory, raises Errno::ENOTDIR.
  # 
  #   FileUtils.ln_s Dir.glob('bin/*.rb'), '/home/aamine/bin'
  # 
  def ln_s(src, dest, options = {})
    fu_check_options options, :force, :noop, :verbose
    fu_output_message "ln -s#{options[:force] ? 'f' : ''} #{[src,dest].flatten.join ' '}" if options[:verbose]
    return if options[:noop]

    fu_each_src_dest0(src, dest) do |s,d|
      remove_file d, true if options[:force]
      File.symlink s, d
    end
  end

  alias symlink ln_s

  #
  # Options: noop verbose
  # 
  # Same as
  #   #ln_s(src, dest, :force)
  # 
  def ln_sf(src, dest, options = {})
    fu_check_options options, :noop, :verbose
    options = options.dup
    options[:force] = true
    ln_s src, dest, options
  end


  #
  # Options: preserve noop verbose
  #
  # Copies a file +src+ to +dest+. If +dest+ is a directory, copies
  # +src+ to +dest/src+.
  #
  # If +src+ is a list of files, then +dest+ must be a directory.
  #
  #   FileUtils.cp 'eval.c', 'eval.c.org'
  #   FileUtils.cp %w(cgi.rb complex.rb date.rb), '/usr/lib/ruby/1.6'
  #   FileUtils.cp %w(cgi.rb complex.rb date.rb), '/usr/lib/ruby/1.6', :verbose => true
  # 
  def cp(src, dest, options = {})
    fu_check_options options, :preserve, :noop, :verbose
    fu_output_message "cp#{options[:preserve] ? ' -p' : ''} #{[src,dest].flatten.join ' '}" if options[:verbose]
    return if options[:noop]

    fu_each_src_dest(src, dest) do |s,d|
      copy_file s, d, options[:preserve]
    end
  end

  alias copy cp

  #
  # Options: preserve noop verbose
  # 
  # Copies +src+ to +dest+. If +src+ is a directory, this method copies
  # all its contents recursively. If +dest+ is a directory, copies
  # +src+ to +dest/src+.
  #
  # +src+ can be a list of files.
  # 
  #   # Installing ruby library "mylib" under the site_ruby
  #   FileUtils.rm_r site_ruby + '/mylib', :force
  #   FileUtils.cp_r 'lib/', site_ruby + '/mylib'
  # 
  #   # Examples of copying several files to target directory.
  #   FileUtils.cp_r %w(mail.rb field.rb debug/), site_ruby + '/tmail'
  #   FileUtils.cp_r Dir.glob('*.rb'), '/home/aamine/lib/ruby', :noop, :verbose
  #
  #   # If you want to copy all contents of a directory instead of the
  #   # directory itself, c.f. src/x -> dest/x, src/y -> dest/y,
  #   # use following code.
  #   FileUtils.cp_r 'src/.', 'dest'     # cp_r('src', 'dest') makes src/dest,
  #                                      # but this doesn't.
  # 
  def cp_r(src, dest, options = {})
    fu_check_options options, :preserve, :noop, :verbose
    fu_output_message "cp -r#{options[:preserve] ? 'p' : ''} #{[src,dest].flatten.join ' '}" if options[:verbose]
    return if options[:noop]

    fu_each_src_dest(src, dest) do |s,d|
      if File.directory?(s)
        fu_traverse(s) {|rel, deref, st|
          ctx = CopyContext_.new(options[:preserve], deref, st)
          ctx.copy_entry "#{s}/#{rel}", "#{d}/#{rel}"
        }
      else
        copy_file s, d, options[:preserve]
      end
    end
  end

  def fu_traverse(prefix, dereference_root = true)   #:nodoc:
    stack = ['.']
    deref = dereference_root
    while rel = stack.pop
      st = File.lstat("#{prefix}/#{rel}")
      if st.directory? and (deref or not st.symlink?)
        stack.concat Dir.entries("#{prefix}/#{rel}")\
                         .reject {|ent| ent == '.' or ent == '..' }\
                         .map {|ent| "#{rel}/#{ent.untaint}" }.reverse
      end
      yield rel, deref, st
      deref = false
    end
  end
  private :fu_traverse

  #
  # Copies a file system entry +src+ to +dest+.
  # This method preserves file types, c.f. FIFO, device files, directory....
  #
  # Both of +src+ and +dest+ must be a path name.
  # +src+ must exist, +dest+ must not exist.
  #
  # If +preserve+ is true, this method preserves owner, group and permissions.
  # If +dereference+ is true, this method copies a target of symbolic link
  # instead of a symbolic link itself.
  #
  def copy_entry(src, dest, preserve = false, dereference = false)
    CopyContext_.new(preserve, dereference).copy_entry src, dest
  end

  #
  # Copies file contents of +src+ to +dest+.
  # Both of +src+ and +dest+ must be a path name.
  #
  def copy_file(src, dest, preserve = false, dereference = true)
    CopyContext_.new(preserve, dereference).copy_content src, dest
  end

  #
  # Copies stream +src+ to +dest+.
  # Both of +src+ and +dest+ must be a IO.
  #
  def copy_stream(src, dest)
    fu_copy_stream0 src, dest, fu_stream_blksize(src, dest)
  end

  def fu_copy_stream0(src, dest, blksize)   #:nodoc:
    begin
      while true
        dest.syswrite src.sysread(blksize)
      end
    rescue EOFError
    end
  end
  private :fu_copy_stream0

  class CopyContext_
    include ::FileUtils

    def initialize(preserve = false, dereference = false, stat = nil)
      @preserve = preserve
      @dereference = dereference
      @stat = stat
    end

    def copy_entry(src, dest)
      preserve(src, dest) {
        _copy_entry src, dest
      }
    end

    def copy_content(src, dest)
      preserve(src, dest) {
        _copy_content src, dest
      }
    end

    private

    def _copy_entry(src, dest)
      st = stat(src)
      case
      when st.file?
        _copy_content src, dest
      when st.directory?
        begin
          Dir.mkdir File.expand_path(dest)
        rescue => err
          raise unless File.directory?(dest)
        end
      when st.symlink?
        File.symlink File.readlink(src), dest
      when st.chardev?
        raise "cannot handle device file" unless File.respond_to?(:mknod)
        mknod dest, ?c, 0666, st.rdev
      when st.blockdev?
        raise "cannot handle device file" unless File.respond_to?(:mknod)
        mknod dest, ?b, 0666, st.rdev
      when st.socket?
        raise "cannot handle socket" unless File.respond_to?(:mknod)
        mknod dest, nil, st.mode, 0
      when st.pipe?
        raise "cannot handle FIFO" unless File.respond_to?(:mkfifo)
        mkfifo dest, 0666
      when (st.mode & 0xF000) == (_S_IF_DOOR = 0xD000)   # door
        raise "cannot handle door: #{src}"
      else
        raise "unknown file type: #{src}"
      end
    end

    def _copy_content(src, dest)
      st = stat(src)
      File.open(src,  'rb') {|r|
        File.open(dest, 'wb', st.mode) {|w|
          fu_copy_stream0 r, w, (fu_blksize(st) || fu_default_blksize())
        }
      }
    end

    def preserve(src, dest)
      return yield unless @preserve
      st = stat(src)
      yield
      File.utime st.atime, st.mtime, dest
      begin
        chown st.uid, st.gid, dest
      rescue Errno::EPERM
        # clear setuid/setgid
        chmod st.mode & 01777, dest
      else
        chmod st.mode, dest
      end
    end

    def stat(path)
      @stat ||= ::File.stat(path)
    end

    def chmod(mode, path)
      if @dereference
        ::File.chmod mode, path
      else
        begin
          ::File.lchmod mode, path
        rescue NotImplementedError
          # just ignore this because chmod(symlink) changes attributes of
          # symlink target, which is not our intent.
        end
      end
    end

    def chown(uid, gid, path)
      if @dereference
        ::File.chown uid, gid, path
      else
        begin
          ::File.lchown uid, gid, path
        rescue NotImplementedError
          # just ignore this because chown(symlink) changes attributes of
          # symlink target, which is not our intent.
        end
      end
    end
  end

  #
  # Options: force noop verbose
  # 
  # Moves file(s) +src+ to +dest+.  If +file+ and +dest+ exist on the different
  # disk partition, the file is copied instead.
  # 
  #   FileUtils.mv 'badname.rb', 'goodname.rb'
  #   FileUtils.mv 'stuff.rb', '/notexist/lib/ruby', :force => true  # no error
  # 
  #   FileUtils.mv %w(junk.txt dust.txt), '/home/aamine/.trash/'
  #   FileUtils.mv Dir.glob('test*.rb'), 'test', :noop => true, :verbose => true
  # 
  def mv(src, dest, options = {})
    fu_check_options options, :force, :noop, :verbose
    fu_output_message "mv#{options[:force] ? ' -f' : ''} #{[src,dest].flatten.join ' '}" if options[:verbose]
    return if options[:noop]

    fu_each_src_dest(src, dest) do |s,d|
      if rename_cannot_overwrite_file? and File.file?(d)
        begin
          File.unlink d
        rescue SystemCallError
          raise unless options[:force]
        end
      end
      begin
        File.rename s, d
      rescue SystemCallError
        begin
          copy_entry s, d, true
          File.unlink s
        rescue SystemCallError
          raise unless options[:force]
        end
      end
    end
  end

  alias move mv

  def rename_cannot_overwrite_file?   #:nodoc:
    /djgpp|cygwin|mswin|mingw|bccwin|wince|emx/ !~ RUBY_PLATFORM
  end
  private :rename_cannot_overwrite_file?


  #
  # Options: force noop verbose
  # 
  # Remove file(s) specified in +list+.  This method cannot remove directories.
  # All StandardErrors are ignored when the :force option is set.
  # 
  #   FileUtils.rm %w( junk.txt dust.txt )
  #   FileUtils.rm Dir.glob('*.so')
  #   FileUtils.rm 'NotExistFile', :force => true   # never raises exception
  # 
  def rm(list, options = {})
    fu_check_options options, :force, :noop, :verbose
    list = fu_list(list)
    fu_output_message "rm#{options[:force] ? ' -f' : ''} #{list.join ' '}" if options[:verbose]
    return if options[:noop]

    list.each do |fname|
      remove_file fname, options[:force]
    end
  end

  alias remove rm

  #
  # Options: noop verbose
  # 
  # Same as
  #   #rm(list, :force)
  #
  def rm_f(list, options = {})
    fu_check_options options, :noop, :verbose
    options = options.dup
    options[:force] = true
    rm list, options
  end

  alias safe_unlink rm_f

  #
  # Options: force noop verbose
  # 
  # remove files +list+[0] +list+[1]... If +list+[n] is a directory,
  # removes its all contents recursively. This method ignores
  # StandardError when :force option is set.
  # 
  #   FileUtils.rm_r Dir.glob('/tmp/*')
  #   FileUtils.rm_r '/', :force => true          #  :-)
  # 
  def rm_r(list, options = {})
    fu_check_options options, :force, :noop, :verbose
    list = fu_list(list)
    fu_output_message "rm -r#{options[:force] ? 'f' : ''} #{list.join ' '}" if options[:verbose]
    return if options[:noop]

    list.each do |fname|
      begin
        st = File.lstat(fname)
      rescue
        next if options[:force]
        raise
      end
      if    st.symlink?   then remove_file fname, options[:force]
      elsif st.directory? then remove_dir fname, options[:force]
      else                     remove_file fname, options[:force]
      end
    end
  end

  #
  # Options: noop verbose
  # 
  # Same as 
  #   #rm_r(list, :force => true)
  # 
  def rm_rf(list, options = {})
    fu_check_options options, :noop, :verbose
    options = options.dup
    options[:force] = true
    rm_r list, options
  end

  alias rmtree rm_rf

  def remove_file(fname, force = false) #:nodoc:
    first_time_p = true
    begin
      File.unlink fname
    rescue Errno::ENOENT
      raise unless force
    rescue
      if first_time_p
        # try once more for Windows
        first_time_p = false
        File.chmod 0777, fname
        retry
      end
      raise
    end
  end

  def remove_dir(dir, force = false) #:nodoc:
    Dir.foreach(dir) do |file|
      next if /\A\.\.?\z/ =~ file
      path = "#{dir}/#{file.untaint}"
      if File.symlink?(path)
        remove_file path, force
      elsif File.directory?(path)
        remove_dir path, force
      else
        remove_file path, force
      end
    end
    begin
      Dir.rmdir dir.sub(%r</\z>, '')
    rescue Errno::ENOENT
      raise unless force
    end
  end


  #
  # Returns true if the contents of a file A and a file B are identical.
  # 
  #   FileUtils.compare_file('somefile', 'somefile')  #=> true
  #   FileUtils.compare_file('/bin/cp', '/bin/mv')    #=> maybe false
  #
  def compare_file(a, b)
    return false unless File.size(a) == File.size(b)
    File.open(a, 'rb') {|fa|
      File.open(b, 'rb') {|fb|
        return compare_stream(fa, fb)
      }
    }
  end

  alias identical? compare_file
  alias cmp compare_file

  #
  # Returns true if the contents of a stream +a+ and +b+ are identical.
  #
  def compare_stream(a, b)
    bsize = fu_stream_blksize(a, b)
    sa = sb = nil
    while sa == sb
      sa = a.read(bsize)
      sb = b.read(bsize)
      unless sa and sb
        if sa.nil? and sb.nil?
          return true
        end
      end
    end
    false
  end


  #
  # Options: mode noop verbose
  # 
  # If +src+ is not same as +dest+, copies it and changes the permission
  # mode to +mode+.  If +dest+ is a directory, destination is +dest+/+src+.
  # 
  #   FileUtils.install 'ruby', '/usr/local/bin/ruby', :mode => 0755, :verbose => true
  #   FileUtils.install 'lib.rb', '/usr/local/lib/ruby/site_ruby', :verbose => true
  # 
  def install(src, dest, options = {})
    fu_check_options options, :mode, :preserve, :noop, :verbose
    fu_output_message "install -c#{options[:preserve] && ' -p'}#{options[:mode] ? (' -m 0%o' % options[:mode]) : ''} #{[src,dest].flatten.join ' '}" if options[:verbose]
    return if options[:noop]

    fu_each_src_dest(src, dest) do |s,d|
      unless File.exist?(d) and compare_file(s,d)
        remove_file d, true
        st = File.stat(s) if options[:preserve]
        copy_file s, d
        File.utime st.atime, st.mtime, d if options[:preserve]
        File.chmod options[:mode], d if options[:mode]
      end
    end
  end


  #
  # Options: noop verbose
  # 
  # Changes permission bits on the named files (in +list+) to the bit pattern
  # represented by +mode+.
  # 
  #   FileUtils.chmod 0755, 'somecommand'
  #   FileUtils.chmod 0644, %w(my.rb your.rb his.rb her.rb)
  #   FileUtils.chmod 0755, '/usr/bin/ruby', :verbose => true
  # 
  def chmod(mode, list, options = {})
    fu_check_options options, :noop, :verbose
    list = fu_list(list)
    fu_output_message sprintf('chmod %o %s', mode, list.join(' ')) if options[:verbose]
    return if options[:noop]
    File.chmod mode, *list
  end


  #
  # Options: noop verbose
  # 
  # Updates modification time (mtime) and access time (atime) of file(s) in
  # +list+.  Files are created if they don't exist.
  # 
  #   FileUtils.touch 'timestamp'
  #   FileUtils.touch Dir.glob('*.c');  system 'make'
  # 
  def touch(list, options = {})
    fu_check_options options, :noop, :verbose
    list = fu_list(list)
    fu_output_message "touch #{list.join ' '}" if options[:verbose]
    return if options[:noop]

    t = Time.now
    list.each do |fname|
      begin
        File.utime(t, t, fname)
      rescue Errno::ENOENT
        File.open(fname, 'a') {
          ;
        }
      end
    end
  end

  private

  def fu_check_options(options, *optdecl)
    h = options.dup
    optdecl.each do |name|
      h.delete name
    end
    raise ArgumentError, "no such option: #{h.keys.join(' ')}" unless h.empty?
  end

  def fu_list(arg)
    [arg].flatten.map {|path| path.to_str }
  end

  def fu_each_src_dest(src, dest)
    fu_each_src_dest0(src, dest) do |s, d|
      raise ArgumentError, "same file: #{s} and #{d}" if fu_same?(s, d)
      yield s, d
    end
  end

  def fu_each_src_dest0(src, dest)
    if src.is_a?(Array)
      src.each do |s|
        yield s.to_str, File.join(dest, File.basename(s))
      end
    else
      if File.directory?(dest)
        yield src.to_str, File.join(dest, File.basename(src))
      else
        yield src.to_str, dest.to_str
      end
    end
  end

  def fu_same?(a, b)
    if have_st_ino?
      st1 = File.stat(a)
      st2 = File.stat(b)
      st1.dev == st2.dev and st1.ino == st2.ino
    else
      File.expand_path(a) == File.expand_path(b)
    end
  rescue Errno::ENOENT
    return false
  end

  def have_st_ino?
    /mswin|mingw|bccwin|wince|emx/ !~ RUBY_PLATFORM
  end

  def fu_stream_blksize(*streams)
    streams.each do |s|
      next unless s.respond_to?(:stat)
      size = fu_blksize(s.stat)
      return size if size
    end
    fu_default_blksize()
  end

  def fu_blksize(st)
    s = st.blksize
    return nil unless s
    return nil if s == 0
    s
  end

  def fu_default_blksize
    1024
  end

  @fileutils_output = $stderr
  @fileutils_label  = ''

  def fu_output_message(msg)
    @fileutils_output ||= $stderr
    @fileutils_label  ||= ''
    @fileutils_output.puts @fileutils_label + msg
  end

  def fu_update_option(args, new)
    if args.last.is_a?(Hash)
      args.last.update new
    else
      args.push new
    end
    args
  end


  extend self


  OPT_TABLE = {
    'cd'           => %w( noop verbose ),
    'chdir'        => %w( noop verbose ),
    'chmod'        => %w( noop verbose ),
    'copy'         => %w( noop verbose preserve ),
    'cp'           => %w( noop verbose preserve ),
    'cp_r'         => %w( noop verbose preserve ),
    'install'      => %w( noop verbose preserve mode ),
    'link'         => %w( noop verbose force ),
    'ln'           => %w( noop verbose force ),
    'ln_s'         => %w( noop verbose force ),
    'ln_sf'        => %w( noop verbose ),
    'makedirs'     => %w( noop verbose ),
    'mkdir'        => %w( noop verbose mode ),
    'mkdir_p'      => %w( noop verbose mode ),
    'mkpath'       => %w( noop verbose ),
    'move'         => %w( noop verbose force ),
    'mv'           => %w( noop verbose force ),
    'remove'       => %w( noop verbose force ),
    'rm'           => %w( noop verbose force ),
    'rm_f'         => %w( noop verbose ),
    'rm_r'         => %w( noop verbose force ),
    'rm_rf'        => %w( noop verbose ),
    'rmtree'       => %w( noop verbose ),
    'rmdir'        => %w( noop verbose ),
    'safe_unlink'  => %w( noop verbose ),
    'symlink'      => %w( noop verbose force ),
    'touch'        => %w( noop verbose )
  }


  # 
  # This module has all methods of FileUtils module, but it outputs messages
  # before acting.  This equates to passing the <tt>:verbose</tt> flag to
  # methods in FileUtils.
  # 
  module Verbose
    include FileUtils
    @fileutils_output  = $stderr
    @fileutils_label   = ''
    FileUtils::OPT_TABLE.each do |name, opts|
      next unless opts.include?('verbose')
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args)
          super(*fu_update_option(args, :verbose => true))
        end
      EOS
    end
    extend self
  end

  # 
  # This module has all methods of FileUtils module, but never changes
  # files/directories.  This equates to passing the <tt>:noop</tt> flag
  # to methods in FileUtils.
  # 
  module NoWrite
    include FileUtils
    @fileutils_output  = $stderr
    @fileutils_label   = ''
    FileUtils::OPT_TABLE.each do |name, opts|
      next unless opts.include?('noop')
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args)
          super(*fu_update_option(args, :noop => true))
        end
      EOS
    end
    extend self
  end

  # 
  # This module has all methods of FileUtils module, but never changes
  # files/directories, with printing message before acting.
  # This equates to passing the <tt>:noop</tt> and <tt>:verbose</tt> flag
  # to methods in FileUtils.
  # 
  module DryRun
    include FileUtils
    @fileutils_output  = $stderr
    @fileutils_label   = ''
    FileUtils::OPT_TABLE.each do |name, opts|
      next unless opts.include?('noop')
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args)
          super(*fu_update_option(args, :noop => true, :verbose => true))
        end
      EOS
    end
    extend self
  end

end
