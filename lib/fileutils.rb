=begin

= fileutils.rb

  Copyright (c) 2000-2002 Minero Aoki <aamine@loveruby.net>

  This program is free software.
  You can distribute/modify this program under the same terms of ruby.

== module FileUtils

The module which implements basic file operations.

=== Module Functions

--- FileUtils.cd( dir, *options )
--- FileUtils.cd( dir, *options ) {|dir| .... }
  Options: noop verbose

  changes the current directory to the directory DIR.

  If this method is called with block, resumes to the old
  working directory after the block execution finished.

    FileUtils.cd '/', :verbose   # chdir and report it

--- FileUtils.uptodate?( newer, older_list, *options )
  Options: verbose

  returns true if NEWER is newer than all OLDER_LIST.
  Non-exist files are older than any file.

    FileUtils.newest? 'hello.o', 'hello.c', 'hello.h' or system 'make'

--- FileUtils.mkdir( dir, *options )
  Options: noop verbose

  creates directorie(s) DIR.

    FileUtils.mkdir 'test'
    FileUtils.mkdir %w( tmp data )
    FileUtils.mkdir 'notexist', :noop  # does not create really

--- FileUtils.mkdir_p( dir, *options )
  Options: noop verbose

  makes dirctories DIR and all its parent directories.
  For example,

    FileUtils.mkdir_p '/usr/local/bin/ruby'
  
  causes to make following directories (if it does not exist).
      * /usr
      * /usr/local
      * /usr/local/bin
      * /usr/local/bin/ruby

--- FileUtils.rmdir( dir, *options )
  Options: noop, verbose

  removes directory DIR.

    FileUtils.rmdir 'somedir'
    FileUtils.rmdir %w(somedir anydir otherdir)
    # does not remove directory really, outputing message.
    FileUtils.rmdir 'somedir', :verbose, :noop

--- FileUtils.ln( old, new, *options )
  Options: force noop verbose

  creates a hard link NEW which points OLD.
  If NEW already exists and it is a directory, creates a symbolic link NEW/OLD.
  If NEW already exists and it is not a directory, raises Errno::EEXIST.
  But if :force option is set, overwrite NEW.

    FileUtils.ln 'gcc', 'cc', :verbose
    FileUtils.ln '/usr/bin/emacs21', '/usr/bin/emacs'

--- FileUtils.ln( list, destdir, *options )
  Options: force noop verbose

  creates hard links DESTDIR/LIST[0], DESTDIR/LIST[1], DESTDIR/LIST[2], ...
  And each link points LIST[0], LIST[1], LIST[2], ...
  If DESTDIR is not a directory, raises Errno::ENOTDIR.

    include FileUtils
    cd '/bin'
    ln %w(cp mv mkdir), '/usr/bin'

--- FileUtils.ln_s( old, new, *options )
  Options: force noop verbose

  creates a symbolic link NEW which points OLD.
  If NEW already exists and it is a directory, creates a symbolic link NEW/OLD.
  If NEW already exists and it is not a directory, raises Errno::EEXIST.
  But if :force option is set, overwrite NEW.

    FileUtils.ln_s '/usr/bin/ruby', '/usr/local/bin/ruby'
    FileUtils.ln_s 'verylongsourcefilename.c', 'c', :force

--- FileUtils.ln_s( list, destdir, *options )
  Options: force noop verbose

  creates symbolic link dir/file1, dir/file2 ... which point to
  file1, file2 ... If DIR is not a directory, raises Errno::ENOTDIR.
  If last argument is a directory, links DIR/LIST[0] to LIST[0],
  DIR/LIST[1] to LIST[1], ....
  creates symbolic links DESTDIR/LIST[0] which points LIST[0].
  DESTDIR/LIST[1] to LIST[1], ....
  If DESTDIR is not a directory, raises Errno::ENOTDIR.

   FileUtils.ln_s Dir.glob('bin/*.rb'), '/home/aamine/bin'

--- FileUtils.ln_sf( src, dest, *options )
  Options: noop verbose

  same to ln_s(src,dest,:force)

--- FileUtils.cp( src, dest, *options )
  Options: preserve noop verbose

  copies a file SRC to DEST. If DEST is a directory, copies
  SRC to DEST/SRC.

    FileUtils.cp 'eval.c', 'eval.c.org'

--- FileUtils.cp( list, dir, *options )
  Options: preserve noop verbose

  copies FILE1 to DIR/FILE1, FILE2 to DIR/FILE2 ...

    FileUtils.cp 'cgi.rb', 'complex.rb', 'date.rb', '/usr/lib/ruby/1.6'
    FileUtils.cp :verbose, %w(cgi.rb complex.rb date.rb), '/usr/lib/ruby/1.6'

--- FileUtils.cp_r( src, dest, *options )
  Options: preserve noop verbose

  copies SRC to DEST. If SRC is a directory, this method copies
  its all contents recursively. If DEST is a directory, copies
  SRC to DEST/SRC.

    # installing ruby library "mylib" under the site_ruby
    FileUtils.rm_r site_ruby + '/mylib', :force
    FileUtils.cp_r 'lib/', site_ruby + '/mylib'

--- FileUtils.cp_r( list, dir, *options )
  Options: preserve noop verbose

  copies a file or a directory LIST[0] to DIR/LIST[0], LIST[1] to DIR/LIST[1], ...
  If LIST[n] is a directory, copies its contents recursively.

    FileUtils.cp_r %w(mail.rb field.rb debug/) site_ruby + '/tmail'
    FileUtils.cp_r Dir.glob('*.rb'), '/home/aamine/lib/ruby', :noop, :verbose

--- FileUtils.mv( src, dest, *options )
  Options: noop verbose

  moves a file SRC to DEST.
  If FILE and DEST exist on the different disk partition,
  copies it.

    FileUtils.mv 'badname.rb', 'goodname.rb'
    FileUtils.mv 'stuff.rb', 'lib/ruby', :force

--- FileUtils.mv( list, dir, *options )
  Options: noop verbose

  moves FILE1 to DIR/FILE1, FILE2 to DIR/FILE2 ...
  If FILE and DEST exist on the different disk partition,
  copies it.

    FileUtils.mv 'junk.txt', 'dust.txt', '/home/aamine/.trash/'
    FileUtils.mv Dir.glob('test*.rb'), 'T', :noop, :verbose

--- FileUtils.rm( list, *options )
  Options: force noop verbose

  remove files LIST[0], LIST[1]... This method cannot remove directory.
  This method ignores all errors when :force option is set.

    FileUtils.rm %w( junk.txt dust.txt )
    FileUtils.rm Dir['*.so']
    FileUtils.rm 'NotExistFile', :force    # never raises exception

--- FileUtils.rm_r( list, *options )
  Options: force noop verbose

  remove files LIST[0] LIST[1]... If LIST[n] is a directory,
  removes its all contents recursively. This method ignores
  StandardError when :force option is set.

    FileUtils.rm_r Dir.glob('/tmp/*')
    FileUtils.rm_r '/', :force          #  :-)

--- FileUtils.rm_rf( list, *options )
  Options: noop verbose

  same to rm_r(list,:force)

--- FileUtils.cmp( file_a, file_b, *options )
  Options: verbose

  returns true if contents of a file A and a file B is identical.

    FileUtils.cmp 'somefile', 'somefile'  #=> true
    FileUtils.cmp '/bin/cp', '/bin/mv'    #=> maybe false.

--- FileUtils.install( src, dest, mode = <src's>, *options )
  Options: noop verbose

  If SRC is not same to DEST, copies it and changes the permittion
  mode to MODE.

    FileUtils.install 'ruby', '/usr/local/bin/ruby', 0755, :verbose
    FileUtils.install 'lib.rb', '/usr/local/lib/ruby/site_ruby', :verbose

--- FileUtils.chmod( mode, list, *options )
  Options: noop verbose

  changes permittion bits on the named FILEs to the bit pattern
  represented by MODE.

    FileUtils.chmod 0644, 'my.rb', 'your.rb'
    FileUtils.chmod 0755, 'somecommand'
    FileUtils.chmod 0755, '/usr/bin/ruby', :verbose

--- FileUtils.touch( list, *options )
  Options: noop verbose

  updates modification time (mtime) and access time (atime) of
  LIST[0], LIST[1]...
  If LIST[n] does not exist, creates an empty file.

    FileUtils.touch 'timestamp'
    FileUtils.touch Dir.glob('*.c');  system 'make'

== module FileUtils::Verbose

This class has all methods of FileUtils module and it works as
same, but outputs messages before action. You can also pass
verbose flag to all methods.

== module FileUtils::NoWrite

This class has all methods of FileUtils module,
but never changes files/directories.

=end


module FileUtils

  # all methods are module_function.

  def cd( dir, *options, &block )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    fu_output_message "cd #{dir}" if verbose
    Dir.chdir dir, &block unless noop
    fu_output_message 'cd -' if verbose and block
  end

  alias chdir cd


  def uptodate?( new, *args )
    verbose, = fu_parseargs(args, :verbose)
    fu_output_message "newest? #{args.join ' '}" if verbose

    return false unless FileTest.exist? new
    new_time = File.ctime(new)
    args.each do |old|
      if FileTest.exist? old then
        return false unless new_time > File.mtime(old)
      end
    end
    true
  end


  def mkdir( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "mkdir #{list.join ' '}" if verbose
    return if noop

    list.each do |dir|
      Dir.mkdir dir
    end
  end

  def mkdir_p( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "mkdir -p #{list.join ' '}" if verbose
    return *list if noop

    list.collect {|n| File.expand_path(n) }.each do |dir|
      stack = []
      until FileTest.directory? dir do
        stack.push dir
        dir = File.dirname(dir)
      end
      stack.reverse_each do |dir|
        Dir.mkdir dir
      end
    end

    return *list
  end

  alias mkpath    mkdir_p
  alias makedirs  mkdir_p


  def rmdir( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message "rmdir #{list.join ' '}" if verbose
    return if noop

    list.each do |dir|
      Dir.rmdir dir
    end
  end


  def ln( src, dest, *options )
    force, noop, verbose, = fu_parseargs(options, :force, :noop, :verbose)
    fu_output_message "ln #{argv.join ' '}" if verbose
    return if noop

    fu_each_src_dest( src, dest ) do |s,d|
      remove_file d, true if force
      File.link s, d
    end
  end

  alias link ln

  def ln_s( src, dest, *options )
    force, noop, verbose, = fu_parseargs(options, :force, :noop, :verbose)
    fu_output_message "ln -s#{force ? 'f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest( src, dest ) do |s,d|
      remove_file d, true if force
      File.symlink s, d
    end
  end

  alias symlink ln_s

  def ln_sf( src, dest, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    ln_s src, dest, :force, *options
  end


  def cp( src, dest, *options )
    preserve, noop, verbose, = fu_parseargs(options, :preserve, :noop, :verbose)
    fu_output_message "cp#{preserve ? ' -p' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest( src, dest ) do |s,d|
      fu_preserve_attr(preserve, s, d) {
          copy_file s, d
      }
    end
  end

  alias copy cp

  def cp_r( src, dest, *options )
    preserve, noop, verbose, = fu_parseargs(options, :preserve, :noop, :verbose)
    fu_output_message "cp -r #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest( src, dest ) do |s,d|
      if FileTest.directory? s then
        fu_copy_dir s, d, '.', preserve
      else
        fu_p_copy s, d, preserve
      end
    end
  end

  def fu_copy_dir( src, dest, rel, preserve )
    fu_preserve_attr( preserve, "#{src}/#{rel}",
                                "#{dest}/#{rel}" ) {|s,d|
        dir = File.expand_path(d)   # to remove '/./'
        Dir.mkdir dir unless FileTest.directory? dir
    }
    Dir.entries( "#{src}/#{rel}" ).each do |fn|
      if FileTest.directory? File.join(src,rel,fn) then
        next if /\A\.\.?\z/ === fn
        fu_copy_dir src, dest, "#{rel}/#{fn}", preserve
      else
        fu_p_copy File.join(src,rel,fn), File.join(dest,rel,fn), preserve
      end
    end
  end
  private :fu_copy_dir

  def fu_p_copy( src, dest, really )
    fu_preserve_attr( really, src, dest ) {
        copy_file src, dest
    }
  end
  private :fu_p_copy

  def fu_preserve_attr( really, src, dest )
    unless really then
      yield src, dest
      return
    end

    st = File.stat(src)
    yield src, dest
    File.utime st.atime, st.mtime, dest
    begin
      File.chown st.uid, st.gid
    rescue Errno::EPERM
      File.chmod st.mode & 01777, dest   # clear setuid/setgid
    else
      File.chmod st.mode, dest
    end
  end
  private :fu_preserve_attr

  def copy_file( src, dest )
    st = r = w = nil

    File.open( src,  'rb' ) {|r|
    File.open( dest, 'wb' ) {|w|
        st = r.stat
        begin
          while true do
            w.write r.sysread(st.blksize)
          end
        rescue EOFError
        end
    } }
  end


  def mv( src, dest, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    fu_output_message "mv #{[src,dest].flatten.join ' '}" if verbose
    return if noop

    fu_each_src_dest( src, dest ) do |s,d|
      if /djgpp|cygwin|mswin32/ === RUBY_PLATFORM and
         FileTest.file? d then
         File.unlink d
      end

      begin
        File.rename s, d
      rescue
        if FileTest.symlink? s then
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

  def rm_f( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    rm list, :force, *options
  end

  alias safe_unlink rm_f

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

  def rm_rf( list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    rm_r list, :force, *options
  end

  def remove_file( fn, force = false )
    first = true
    begin
      File.unlink fn
    rescue Errno::ENOENT
      force or raise
    rescue
      # rescue dos?
      begin
        if first then
          first = false
          File.chmod 0777, fn
          retry
        end
      rescue
      end
    end
  end

  def remove_dir( dir, force = false )
    Dir.foreach( dir ) do |file|
      next if /\A\.\.?\z/ === file
      path = "#{dir}/#{file}"
      if FileTest.directory? path then remove_dir path, force
                                  else remove_file path, force
      end
    end
    begin
      Dir.rmdir dir
    rescue Errno::ENOENT
      force or raise
    end
  end


  def cmp( filea, fileb, *options )
    verbose, = fu_parseargs(options, :verbose)
    fu_output_message "cmp #{filea} #{fileb}" if verbose

    sa = sb = nil
    st = File.stat(filea)
    File.size(fileb) == st.size or return true

    File.open( filea, 'rb' ) {|a|
    File.open( fileb, 'rb' ) {|b|
      begin
        while sa == sb do
          sa = a.read( st.blksize )
          sb = b.read( st.blksize )
          unless sa and sb then
            if sa.nil? and sb.nil? then
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

  def install( src, dest, mode, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    fu_output_message "install #{[src,dest].flatten.join ' '}#{mode ? ' %o'%mode : ''}" if verbose
    return if noop

    fu_each_src_dest( src, dest ) do |s,d|
      unless FileTest.exist? d and cmp(s,d) then
        remove_file d, true
        copy_file s, d
        File.chmod mode, d if mode
      end
    end
  end


  def chmod( mode, list, *options )
    noop, verbose, = fu_parseargs(options, :noop, :verbose)
    list = fu_list(list)
    fu_output_message sprintf('chmod %o %s', mode, list.join(' ')) if verbose
    return if noop
    File.chmod mode, *list
  end

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

  def fu_parseargs( opts, *flagdecl )
    tab = {}
    if opts.last == true or opts.last == false then
      tab[:verbose] = opts.pop
    end
    while Symbol === opts.last do
      tab[opts.pop] = true
    end

    flags = flagdecl.collect {|s| tab.delete(s) }
    tab.empty? or raise ArgumentError, "wrong option :#{tab.keys.join(' :')}"

    flags
  end


  def fu_list( arg )
    Array === arg ? arg : [arg]
  end

  def fu_each_src_dest( src, dest )
    unless Array === src then
      yield src, fu_dest_filename(src, dest)
    else
      dir = dest
      # FileTest.directory? dir or raise ArgumentError, "must be dir: #{dir}"
      dir += (dir[-1,1] == '/') ? '' : '/'
      src.each do |fn|
        yield fn, dir + File.basename(fn)
      end
    end
  end

  def fu_dest_filename( src, dest )
    if FileTest.directory? dest then
      (dest[-1,1] == '/' ? dest : dest + '/') + File.basename(src)
    else
      dest
    end
  end


  @fileutils_output = $stderr
  @fileutils_label  = 'fileutils.'

  def fu_output_message( msg )
    @fileutils_output ||= $stderr
    @fileutils_label  ||= 'fileutils.'
    @fileutils_output.puts @fileutils_label + msg
  end


  extend self


  OPT_TABLE = {
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


  module Verbose

    include FileUtils

    @fileutils_output  = $stderr
    @fileutils_label   = 'fileutils.'
    @fileutils_verbose = true

    FileUtils::OPT_TABLE.each do |name, opts|
      next unless opts.include? 'verbose'
      module_eval <<-End, __FILE__, __LINE__ + 1
          def #{name}( *args )
            unless defined? @fileutils_verbose then
              @fileutils_verbose = true
            end
            args.push :verbose if @fileutils_verbose
            super( *args )
          end
      End
    end

    extend self

  end


  module NoWrite

    include FileUtils

    @fileutils_output  = $stderr
    @fileutils_label   = 'fileutils.'
    @fileutils_nowrite = true

    FileUtils::OPT_TABLE.each do |name, opts|
      next unless opts.include? 'noop'
      module_eval <<-End, __FILE__, __LINE__ + 1
          def #{name}( *args )
            unless defined? @fileutils_nowrite then
              @fileutils_nowrite = true
            end
            args.push :noop if @fileutils_nowrite
            super( *args )
          end
      End
    end

    extend self
  
  end


  class Operator

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
      s = opts.collect {|i| "args.unshift :#{i} if @#{i}" }.join(' '*10+"\n")
      module_eval <<-End, __FILE__, __LINE__ + 1
          def #{name}( *args )
            #{s}
            super( *args )
          end
      End
    end
  
  end

end
