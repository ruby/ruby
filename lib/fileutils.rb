# 
# = fileutils.rb
# 
# Copyright (c) 2000-2002 Minero Aoki <aamine@loveruby.net>
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
#   cd( dir, *options )
#   cd( dir, *options ) {|dir| .... }
#   uptodate?( newer, older_list, *options )
#   mkdir( dir, *options )
#   mkdir_p( dir, *options )
#   rmdir( dir, *options )
#   ln( old, new, *options )
#   ln( list, destdir, *options )
#   ln_s( old, new, *options )
#   ln_s( list, destdir, *options )
#   ln_sf( src, dest, *options )
#   cp( src, dest, *options )
#   cp( list, dir, *options )
#   cp_r( src, dest, *options )
#   cp_r( list, dir, *options )
#   mv( src, dest, *options )
#   mv( list, dir, *options )
#   rm( list, *options )
#   rm_r( list, *options )
#   rm_rf( list, *options )
#   cmp( file_a, file_b, *options )
#   install( src, dest, mode = <src's>, *options )
#   chmod( mode, list, *options )
#   touch( list, *options )
#
# The <tt>*options</tt> parameter is a list of 0-3 options, taken from the list
# +:force+, +:noop+, +:preserve+, and +:verbose+.  +:noop+ means that no changes
# are made.  The other two are obvious.  Each method documents the options that
# it honours.
#
# All methods that have the concept of a "source" file or directory can take
# either one file or a list of files in that argument.  See the method
# documentation for examples.
#
# == module FileUtils::Verbose
# 
# This module has all methods of FileUtils module, but it outputs messages
# before acting.  This equates to passing the +:verbose+ flag to methods in
# FileUtils.
# 
# == module FileUtils::NoWrite
# 
# This module has all methods of FileUtils module, but never changes
# files/directories.  This equates to passing the +:noop+ flag to methods in
# FileUtils.
# 


#
# See exp.rb for a summary of methods.
#
module FileUtils

  # All methods are module_function.

  #
  # Options: noop verbose
  # 
  # Changes the current directory to the directory +dir+.
  # 
  # If this method is called with block, resumes to the old
  # working directory after the block execution finished.
  # 
  #   FileUtils.cd '/', :verbose   # chdir and report it
  # 
  def cd( dir, *options, &block ) # :yield: dir
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    fu_output_message "cd #{dir}" if verbose
    Dir.chdir dir, &block unless noop
    fu_output_message 'cd -' if verbose and block
  end

  alias chdir cd


  #
  # Options: verbose
  # 
  # Returns true if +newer+ is newer than all +old_list+.
  # Non-existent files are older than any file.
  # 
  #   FileUtils.uptodate? 'hello.o', 'hello.c', 'hello.h' or system 'make'
  # 
  def uptodate?( new, old_list, *options )
    verbose, = fu_parseargs(options, :verbose)
    fu_output_message "uptodate? #{new} #{old_list.join ' '}" if verbose

    return false unless FileTest.exist? new
    new_time = File.ctime(new)
    old_list.each do |old|
      if FileTest.exist? old
        return false unless new_time > File.mtime(old)
      end
    end
    true
  end


  #
  # Options: noop verbose
  # 
  # Creates one or more directories.
  # 
  #   FileUtils.mkdir 'test'
  #   FileUtils.mkdir %w( tmp data )
  #   FileUtils.mkdir 'notexist', :noop  # Does not really create.
  # 
  def mkdir( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "mkdir #{list.join ' '}" if verbose
    return if noop

    list.each do |dir|
      Dir.mkdir dir
    end
  end

  #
  # Options: noop verbose
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
  def mkdir_p( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "mkdir -p #{list.join ' '}" if verbose
    return *list if noop

    list.map {|n| File.expand_path(n) }.each do |dir|
      stack = []
      until FileTest.directory? dir
        stack.push dir
        dir = File.dirname(dir)
      end
      stack.reverse_each do |n|
        Dir.mkdir n
      end
    end

    return *list
  end

  alias mkpath    mkdir_p
  alias makedirs  mkdir_p


  #
  # Options: noop, verbose
  # 
  # Removes one or more directories.
  # 
  #   FileUtils.rmdir 'somedir'
  #   FileUtils.rmdir %w(somedir anydir otherdir)
  #   # Does not really remove directory; outputs message.
  #   FileUtils.rmdir 'somedir', :verbose, :noop
  # 
  def rmdir( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "rmdir #{list.join ' '}" if verbose
    return if noop

    list.each do |dir|
      Dir.rmdir dir
    end
  end


  #
  # Options: force noop verbose
  #
  # <b><tt>ln( old, new, *options )</tt></b>
  #
  # Creates a hard link +new+ which points to +old+.
  # If +new+ already exists and it is a directory, creates a symbolic link +new/old+.
  # If +new+ already exists and it is not a directory, raises Errno::EEXIST.
  # But if :force option is set, overwrite +new+.
  # 
  #   FileUtils.ln 'gcc', 'cc', :verbose
  #   FileUtils.ln '/usr/bin/emacs21', '/usr/bin/emacs'
  # 
  # <b><tt>ln( list, destdir, *options )</tt></b>
  # 
  # Creates several hard links in a directory, with each one pointing to the
  # item in +list+.  If +destdir+ is not a directory, raises Errno::ENOTDIR.
  # 
  #   include FileUtils
  #   cd '/bin'
  #   ln %w(cp mv mkdir), '/usr/bin'   # Now /usr/bin/cp and /bin/cp are linked.
  # 
  def ln( src, dest, *options )
    force, noop, verbose, = fu_parseargs(options, :force, :noop, :verbose)
    fu_output_message "ln#{force ? ' -f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest(src, dest) do |s,d|
      remove_file d, true if force
      File.link s, d
    end
  end

  alias link ln

  #
  # Options: force noop verbose
  #
  # <b><tt>ln_s( old, new, *options )</tt></b>
  # 
  # Creates a symbolic link +new+ which points to +old+.  If +new+ already
  # exists and it is a directory, creates a symbolic link +new/old+.  If +new+
  # already exists and it is not a directory, raises Errno::EEXIST.  But if
  # :force option is set, overwrite +new+.
  # 
  #   FileUtils.ln_s '/usr/bin/ruby', '/usr/local/bin/ruby'
  #   FileUtils.ln_s 'verylongsourcefilename.c', 'c', :force
  # 
  # <b><tt>ln_s( list, destdir, *options )</tt></b>
  # 
  # Creates several symbolic links in a directory, with each one pointing to the
  # item in +list+.  If +destdir+ is not a directory, raises Errno::ENOTDIR.
  #
  # If +destdir+ is not a directory, raises Errno::ENOTDIR.
  # 
  #   FileUtils.ln_s Dir.glob('bin/*.rb'), '/home/aamine/bin'
  # 
  def ln_s( src, dest, *options )
    force, noop, verbose, = fu_parseargs(options, :force, :noop, :verbose)
    fu_output_message "ln -s#{force ? 'f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest(src, dest) do |s,d|
      remove_file d, true if force
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
  def ln_sf( src, dest, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    ln_s src, dest, :force, *options
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
  #   FileUtils.cp %w(cgi.rb complex.rb date.rb), '/usr/lib/ruby/1.6', :verbose
  # 
  def cp( src, dest, *options )
    preserve, noop, verbose, = fu_parseargs(options, :preserve, :noop, :verbose)
    fu_output_message "cp#{preserve ? ' -p' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest(src, dest) do |s,d|
      fu_preserve_attr(preserve, s, d) {
          copy_file s, d
      }
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
  def cp_r( src, dest, *options )
    preserve, noop, verbose, = fu_parseargs(options, :preserve, :noop, :verbose)
    fu_output_message "cp -r#{preserve ? 'p' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest(src, dest) do |s,d|
      if FileTest.directory? s
        fu_copy_dir s, d, '.', preserve
      else
        fu_p_copy s, d, preserve
      end
    end
  end

  def fu_copy_dir( src, dest, rel, preserve ) #:nodoc:
    fu_preserve_attr(preserve, "#{src}/#{rel}", "#{dest}/#{rel}") {|s,d|
        dir = File.expand_path(d)   # to remove '/./'
        Dir.mkdir dir unless FileTest.directory? dir
    }
    Dir.entries("#{src}/#{rel}").each do |fname|
      if FileTest.directory? File.join(src,rel,fname)
        next if /\A\.\.?\z/ === fname
        fu_copy_dir src, dest, "#{rel}/#{fname}", preserve
      else
        fu_p_copy File.join(src,rel,fname), File.join(dest,rel,fname), preserve
      end
    end
  end
  private :fu_copy_dir

  def fu_p_copy( src, dest, really ) #:nodoc:
    fu_preserve_attr(really, src, dest) {
        copy_file src, dest
    }
  end
  private :fu_p_copy

  def fu_preserve_attr( really, src, dest ) #:nodoc:
    unless really
      yield src, dest
      return
    end

    st = File.stat(src)
    yield src, dest
    File.utime st.atime, st.mtime, dest
    begin
      File.chown st.uid, st.gid, dest
    rescue Errno::EPERM
      File.chmod st.mode & 01777, dest   # clear setuid/setgid
    else
      File.chmod st.mode, dest
    end
  end
  private :fu_preserve_attr

  def copy_file( src, dest ) #:nodoc:
    bsize = fu_blksize(File.stat(src).blksize)
    File.open(src,  'rb') {|r|
    File.open(dest, 'wb') {|w|
        begin
          while true
            w.syswrite r.sysread(bsize)
          end
        rescue EOFError
        end
    } }
  end


  #
  # Options: noop verbose
  # 
  # Moves file(s) +src+ to +dest+.  If +file+ and +dest+ exist on the different
  # disk partition, the file is copied instead.
  # 
  #   FileUtils.mv 'badname.rb', 'goodname.rb'
  #   FileUtils.mv 'stuff.rb', 'lib/ruby', :force
  # 
  #   FileUtils.mv %w(junk.txt dust.txt), '/home/aamine/.trash/'
  #   FileUtils.mv Dir.glob('test*.rb'), 'test', :noop, :verbose
  # 
  def mv( src, dest, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    fu_output_message "mv #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest(src, dest) do |s,d|
      if cannot_overwrite_file? and FileTest.file? d
        File.unlink d
      end

      begin
        File.rename s, d
      rescue
        if FileTest.symlink? s
          File.symlink File.readlink(s), dest
          File.unlink s
        else
          st = File.stat(s)
          copy_file s, d
          File.unlink s
          File.utime st.atime, st.mtime, d
          begin
            File.chown st.uid, st.gid, d
          rescue
            # ignore
          end
        end
      end
    end
  end

  alias move mv

  def cannot_overwrite_file? #:nodoc:
    /djgpp|cygwin|mswin32/ === RUBY_PLATFORM
  end
  private :cannot_overwrite_file?


  #
  # Options: force noop verbose
  # 
  # Remove file(s) specified in +list+.  This method cannot remove directories.
  # All errors are ignored when the :force option is set.
  # 
  #   FileUtils.rm %w( junk.txt dust.txt )
  #   FileUtils.rm Dir.glob('*.so')
  #   FileUtils.rm 'NotExistFile', :force    # never raises exception
  # 
  def rm( list, *options )
    force, noop, verbose, = fu_parseargs(options, :force, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "rm#{force ? ' -f' : ''} #{list.join ' '}" if verbose
    return if noop

    list.each do |fname|
      remove_file fname, force
    end
  end

  alias remove rm

  #
  # Options: noop verbose
  # 
  # Same as
  #   #rm(list, :force)
  #
  def rm_f( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    rm list, :force, *options
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
  #   FileUtils.rm_r '/', :force          #  :-)
  # 
  def rm_r( list, *options )
    force, noop, verbose, = fu_parseargs(options, :force, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "rm -r#{force ? 'f' : ''} #{list.join ' '}" if verbose
    return if noop

    list.each do |fname|
      begin
        st = File.lstat(fname)
      rescue
        next if force
      end
      if    st.symlink?   then remove_file fname, force
      elsif st.directory? then remove_dir fname, force
      else                     remove_file fname, force
      end
    end
  end

  #
  # Options: noop verbose
  # 
  # Same as 
  #   #rm_r(list, :force)
  # 
  def rm_rf( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    rm_r list, :force, *options
  end

  def remove_file( fname, force = false ) #:nodoc:
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

  def remove_dir( dir, force = false ) #:nodoc:
    Dir.foreach(dir) do |file|
      next if /\A\.\.?\z/ === file
      path = "#{dir}/#{file}"
      if FileTest.directory? path
        remove_dir path, force
      else
        remove_file path, force
      end
    end
    begin
      Dir.rmdir dir
    rescue Errno::ENOENT
      raise unless force
    end
  end


  #
  # Options: verbose
  # 
  # Returns true if the contents of a file A and a file B are identical.
  # 
  #   FileUtils.cmp 'somefile', 'somefile'  #=> true
  #   FileUtils.cmp '/bin/cp', '/bin/mv'    #=> maybe false
  #
  def cmp( filea, fileb, *options )
    verbose, = fu_parseargs(options, :verbose)
    fu_output_message "cmp #{filea} #{fileb}" if verbose

    sa = sb = nil
    st = File.stat(filea)
    bsize = fu_blksize(st.blksize)
    return false unless File.size(fileb) == st.size

    File.open(filea, 'rb') {|a|
    File.open(fileb, 'rb') {|b|
      begin
        while sa == sb
          sa = a.read(bsize)
          sb = b.read(bsize)
          unless sa and sb
            if sa.nil? and sb.nil?
              return true
            end
          end
        end
      rescue EOFError
        ;
      end
    } }

    false
  end

  alias identical? cmp

  #
  # Options: noop verbose
  # 
  # If +src+ is not same as +dest+, copies it and changes the permission
  # mode to +mode+.  If +dest+ is a directory, destination is +dest+/+src+.
  # 
  #   FileUtils.install 'ruby', '/usr/local/bin/ruby', 0755, :verbose
  #   FileUtils.install 'lib.rb', '/usr/local/lib/ruby/site_ruby', :verbose
  # 
  def install( src, dest, mode, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    fu_output_message "install -c#{mode ? ' -m 0%o'%mode : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest(src, dest) do |s,d|
      unless FileTest.exist? d and cmp(s,d)
        remove_file d, true
        copy_file s, d
        File.chmod mode, d if mode
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
  #   FileUtils.chmod 0644, %w(my.rb your.rb)
  #   FileUtils.chmod 0755, '/usr/bin/ruby', :verbose
  # 
  def chmod( mode, list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message sprintf('chmod %o %s', mode, list.join(' ')) if verbose
    return if noop
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
  def touch( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "touch #{list.join ' '}" if verbose
    return if noop

    t = Time.now
    list.each do |fname|
      begin
        File.utime(t, t, fname)
      rescue Errno::ENOENT
        File.open(fname, 'a') { }
      end
    end
  end


  private

  def fu_parseargs( optargs, *optdecl )
    table = Hash.new(false)
    optargs.each do |opt|
      table[opt] = true
    end

    option_list = optdecl.map {|s| table.delete(s) }
    raise ArgumentError, "wrong option #{table.keys.map {|o|o.inspect}.join(' ')}" unless table.empty?

    option_list
  end


  def fu_list( arg )
    Array === arg ? arg : [arg]
  end

  def fu_each_src_dest( src, dest )
    unless Array === src
      yield src, fu_dest_filename(src, dest)
    else
      dir = dest
      # FileTest.directory? dir or raise ArgumentError, "must be dir: #{dir}"
      dir += (dir[-1,1] == '/') ? '' : '/'
      src.each do |fname|
        yield fname, dir + File.basename(fname)
      end
    end
  end

  def fu_dest_filename( src, dest )
    if FileTest.directory? dest
      (dest[-1,1] == '/' ? dest : dest + '/') + File.basename(src)
    else
      dest
    end
  end

  def fu_blksize( size )
    if size.nil? or size.zero?
      2048
    else
      size
    end
  end


  @fileutils_output = $stderr
  @fileutils_label  = ''

  def fu_output_message( msg )
    @fileutils_output ||= $stderr
    @fileutils_label  ||= ''
    @fileutils_output.puts @fileutils_label + msg
  end


  extend self


  OPT_TABLE = {
    'pwd'          => %w( verbose ),
    'cd'           => %w( noop verbose ),
    'chdir'        => %w( noop verbose ),
    'chmod'        => %w( noop verbose ),
    'cmp'          => %w( verbose ),
    'copy'         => %w( preserve noop verbose ),
    'cp'           => %w( preserve noop verbose ),
    'cp_r'         => %w( preserve noop verbose ),
    'identical?'   => %w( verbose ),
    'install'      => %w( noop verbose ),
    'link'         => %w( force noop verbose ),
    'ln'           => %w( force noop verbose ),
    'ln_s'         => %w( force noop verbose ),
    'ln_sf'        => %w( noop verbose ),
    'makedirs'     => %w( noop verbose ),
    'mkdir'        => %w( noop verbose ),
    'mkdir_p'      => %w( noop verbose ),
    'mkpath'       => %w( noop verbose ),
    'move'         => %w( noop verbose ),
    'mv'           => %w( noop verbose ),
    'remove'       => %w( force noop verbose ),
    'rm'           => %w( force noop verbose ),
    'rm_f'         => %w( noop verbose ),
    'rm_r'         => %w( force noop verbose ),
    'rm_rf'        => %w( noop verbose ),
    'rmdir'        => %w( noop verbose ),
    'safe_unlink'  => %w( noop verbose ),
    'symlink'      => %w( force noop verbose ),
    'touch'        => %w( noop verbose ),
    'uptodate?'    => %w( verbose )
  }


  # 
  # This module has all methods of FileUtils module, but it outputs messages
  # before acting.  This equates to passing the +:verbose+ flag to methods in
  # FileUtils.
  # 
  module Verbose

    include FileUtils

    @fileutils_output  = $stderr
    @fileutils_label   = ''
    @fileutils_verbose = true

    FileUtils::OPT_TABLE.each do |name, opts|
      next unless opts.include? 'verbose'
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}( *args )
          unless defined? @fileutils_verbose
            @fileutils_verbose = true
          end
          args.push :verbose if @fileutils_verbose
          super(*args)
        end
      EOS
    end

    extend self

  end


  # 
  # This module has all methods of FileUtils module, but never changes
  # files/directories.  This equates to passing the +:noop+ flag to methods in
  # FileUtils.
  # 
  module NoWrite

    include FileUtils

    @fileutils_output  = $stderr
    @fileutils_label   = ''
    @fileutils_nowrite = true

    FileUtils::OPT_TABLE.each do |name, opts|
      next unless opts.include? 'noop'
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}( *args )
          unless defined? @fileutils_nowrite
            @fileutils_nowrite ||= true
          end
          args.push :noop if @fileutils_nowrite
          super(*args)
        end
      EOS
    end

    extend self
  
  end


  class Operator #:nodoc:

    include FileUtils

    def initialize( v = false )
      @verbose = v
      @noop = false
      @force = false
      @preserve = false
    end

    attr_accessor :verbose
    attr_accessor :noop
    attr_accessor :force
    attr_accessor :preserve

    FileUtils::OPT_TABLE.each do |name, opts|
      s = opts.map {|i| "args.unshift :#{i} if @#{i}" }.join(' '*10+"\n")
      module_eval(<<-End, __FILE__, __LINE__ + 1)
          def #{name}( *args )
            #{s}
            super(*args)
          end
      End
    end
  
  end

end


# Documentation comments:
#  - Some RDoc markup used here doesn't work (namely, +file1+, +:noop+,
#    +dir/file+).  I consider this a bug and expect that these will be valid in
#    the near future.
