# frozen_string_literal: true

begin
  require 'rbconfig'
rescue LoadError
  # for make mjit-headers
end

#
# = fileutils.rb
#
# Copyright (c) 2000-2007 Minero Aoki
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
#   require 'fileutils'
#
#   FileUtils.cd(dir, **options)
#   FileUtils.cd(dir, **options) {|dir| block }
#   FileUtils.pwd()
#   FileUtils.mkdir(dir, **options)
#   FileUtils.mkdir(list, **options)
#   FileUtils.mkdir_p(dir, **options)
#   FileUtils.mkdir_p(list, **options)
#   FileUtils.rmdir(dir, **options)
#   FileUtils.rmdir(list, **options)
#   FileUtils.ln(target, link, **options)
#   FileUtils.ln(targets, dir, **options)
#   FileUtils.ln_s(target, link, **options)
#   FileUtils.ln_s(targets, dir, **options)
#   FileUtils.ln_sf(target, link, **options)
#   FileUtils.cp(src, dest, **options)
#   FileUtils.cp(list, dir, **options)
#   FileUtils.cp_r(src, dest, **options)
#   FileUtils.cp_r(list, dir, **options)
#   FileUtils.mv(src, dest, **options)
#   FileUtils.mv(list, dir, **options)
#   FileUtils.rm(list, **options)
#   FileUtils.rm_r(list, **options)
#   FileUtils.rm_rf(list, **options)
#   FileUtils.install(src, dest, **options)
#   FileUtils.chmod(mode, list, **options)
#   FileUtils.chmod_R(mode, list, **options)
#   FileUtils.chown(user, group, list, **options)
#   FileUtils.chown_R(user, group, list, **options)
#   FileUtils.touch(list, **options)
#
# Possible <tt>options</tt> are:
#
# <tt>:force</tt> :: forced operation (rewrite files if exist, remove
#                    directories if not empty, etc.);
# <tt>:verbose</tt> :: print command to be run, in bash syntax, before
#                      performing it;
# <tt>:preserve</tt> :: preserve object's group, user and modification
#                       time on copying;
# <tt>:noop</tt> :: no changes are made (usable in combination with
#                   <tt>:verbose</tt> which will print the command to run)
#
# Each method documents the options that it honours. See also ::commands,
# ::options and ::options_of methods to introspect which command have which
# options.
#
# All methods that have the concept of a "source" file or directory can take
# either one file or a list of files in that argument.  See the method
# documentation for examples.
#
# There are some `low level' methods, which do not accept keyword arguments:
#
#   FileUtils.copy_entry(src, dest, preserve = false, dereference_root = false, remove_destination = false)
#   FileUtils.copy_file(src, dest, preserve = false, dereference = true)
#   FileUtils.copy_stream(srcstream, deststream)
#   FileUtils.remove_entry(path, force = false)
#   FileUtils.remove_entry_secure(path, force = false)
#   FileUtils.remove_file(path, force = false)
#   FileUtils.compare_file(path_a, path_b)
#   FileUtils.compare_stream(stream_a, stream_b)
#   FileUtils.uptodate?(file, cmp_list)
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
  VERSION = "1.6.0"

  def self.private_module_function(name)   #:nodoc:
    module_function name
    private_class_method name
  end

  #
  # Returns a string containing the path to the current directory:
  #
  #   FileUtils.pwd # => "/rdoc/fileutils"
  #
  # FileUtils.getwd is an alias for FileUtils.pwd.
  #
  def pwd
    Dir.pwd
  end
  module_function :pwd

  alias getwd pwd
  module_function :getwd

  #
  # With no block given,
  # changes the current directory to the directory
  # at the path given by +dir+; returns zero:
  #
  #   FileUtils.pwd # => "/rdoc/fileutils"
  #   FileUtils.cd('..')
  #   FileUtils.pwd # => "/rdoc"
  #   FileUtils.cd('fileutils')
  #
  # With a block given, changes the current directory to the directory
  # at the path given by +dir+, calls the block with argument +dir+,
  # and restores the original current directory; returns the block's value:
  #
  #   FileUtils.pwd                                     # => "/rdoc/fileutils"
  #   FileUtils.cd('..') { |arg| [arg, FileUtils.pwd] } # => ["..", "/rdoc"]
  #   FileUtils.pwd                                     # => "/rdoc/fileutils"
  #
  # Keyword arguments:
  #
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cd('..')
  #     FileUtils.cd('fileutils')
  #
  #   Output:
  #
  #     cd ..
  #     cd fileutils
  #
  # FileUtils.chdir is an alias for FileUtils.cd.
  #
  def cd(dir, verbose: nil, &block) # :yield: dir
    fu_output_message "cd #{dir}" if verbose
    result = Dir.chdir(dir, &block)
    fu_output_message 'cd -' if verbose and block
    result
  end
  module_function :cd

  alias chdir cd
  module_function :chdir

  #
  # Returns +true+ if the file at path +new+
  # is newer than all the files at paths in array +old_list+;
  # +false+ otherwise:
  #
  #   FileUtils.uptodate?('Rakefile', ['Gemfile', 'README.md']) # => true
  #   FileUtils.uptodate?('Gemfile', ['Rakefile', 'README.md']) # => false
  #
  # A non-existent file is considered to be infinitely old.
  #
  def uptodate?(new, old_list)
    return false unless File.exist?(new)
    new_time = File.mtime(new)
    old_list.each do |old|
      if File.exist?(old)
        return false unless new_time > File.mtime(old)
      end
    end
    true
  end
  module_function :uptodate?

  def remove_trailing_slash(dir)   #:nodoc:
    dir == '/' ? dir : dir.chomp(?/)
  end
  private_module_function :remove_trailing_slash

  #
  # Creates directories at the paths in the given +list+
  # (an array of strings or a single string);
  # returns +list+.
  #
  # With no keyword arguments, creates a directory at each +path+ in +list+
  # by calling: <tt>Dir.mkdir(path, mode)</tt>;
  # see {Dir.mkdir}[https://docs.ruby-lang.org/en/master/Dir.html#method-c-mkdir]:
  #
  #   FileUtils.mkdir(%w[tmp0 tmp1]) # => ["tmp0", "tmp1"]
  #   FileUtils.mkdir('tmp4')        # => ["tmp4"]
  #
  # Keyword arguments:
  #
  # - <tt>mode: <i>integer</i></tt> - also calls <tt>File.chmod(mode, path)</tt>;
  #   see {File.chmod}[https://docs.ruby-lang.org/en/master/File.html#method-c-chmod].
  # - <tt>noop: true</tt> - does not create directories.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.mkdir(%w[tmp0 tmp1], verbose: true)
  #     FileUtils.mkdir(%w[tmp2 tmp3], mode: 0700, verbose: true)
  #
  #   Output:
  #
  #     mkdir tmp0 tmp1
  #     mkdir -m 700 tmp2 tmp3
  #
  # Raises an exception if any path in +list+ points to an existing
  # file or directory, or if for any reason a directory cannot be created.
  #
  def mkdir(list, mode: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "mkdir #{mode ? ('-m %03o ' % mode) : ''}#{list.join ' '}" if verbose
    return if noop

    list.each do |dir|
      fu_mkdir dir, mode
    end
  end
  module_function :mkdir

  #
  # Creates directories at the paths in the given +list+
  # (an array of strings or a single string),
  # also creating ancestor directories as needed;
  # returns +list+.
  #
  # With no keyword arguments, creates a directory at each +path+ in +list+,
  # along with any needed ancestor directories,
  # by calling: <tt>Dir.mkdir(path, mode)</tt>;
  # see {Dir.mkdir}[https://docs.ruby-lang.org/en/master/Dir.html#method-c-mkdir]:
  #
  #   FileUtils.mkdir_p(%w[tmp0/tmp1 tmp2/tmp3]) # => ["tmp0/tmp1", "tmp2/tmp3"]
  #   FileUtils.mkdir_p('tmp4/tmp5')             # => ["tmp4/tmp5"]
  #
  # Keyword arguments:
  #
  # - <tt>mode: <i>integer</i></tt> - also calls <tt>File.chmod(mode, path)</tt>;
  #   see {File.chmod}[https://docs.ruby-lang.org/en/master/File.html#method-c-chmod].
  # - <tt>noop: true</tt> - does not create directories.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.mkdir_p(%w[tmp0 tmp1], verbose: true)
  #     FileUtils.mkdir_p(%w[tmp2 tmp3], mode: 0700, verbose: true)
  #
  #   Output:
  #
  #     mkdir -p tmp0 tmp1
  #     mkdir -p -m 700 tmp2 tmp3
  #
  # Raises an exception if for any reason a directory cannot be created.
  #
  def mkdir_p(list, mode: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "mkdir -p #{mode ? ('-m %03o ' % mode) : ''}#{list.join ' '}" if verbose
    return *list if noop

    list.each do |item|
      path = remove_trailing_slash(item)

      stack = []
      until File.directory?(path)
        stack.push path
        path = File.dirname(path)
      end
      stack.reverse_each do |dir|
        begin
          fu_mkdir dir, mode
        rescue SystemCallError
          raise unless File.directory?(dir)
        end
      end
    end

    return *list
  end
  module_function :mkdir_p

  alias mkpath    mkdir_p
  alias makedirs  mkdir_p
  module_function :mkpath
  module_function :makedirs

  def fu_mkdir(path, mode)   #:nodoc:
    path = remove_trailing_slash(path)
    if mode
      Dir.mkdir path, mode
      File.chmod mode, path
    else
      Dir.mkdir path
    end
  end
  private_module_function :fu_mkdir

  #
  # Removes directories at the paths in the given +list+
  # (an array of strings or a single string);
  # returns +list+.
  #
  # With no keyword arguments, removes the directory at each +path+ in +list+,
  # by calling: <tt>Dir.rmdir(path)</tt>;
  # see {Dir.rmdir}[https://docs.ruby-lang.org/en/master/Dir.html#method-c-rmdir]:
  #
  #   FileUtils.rmdir(%w[tmp0/tmp1 tmp2/tmp3]) # => ["tmp0/tmp1", "tmp2/tmp3"]
  #   FileUtils.rmdir('tmp4/tmp5')             # => ["tmp4/tmp5"]
  #
  # Keyword arguments:
  #
  # - <tt>parents: true</tt> - removes successive ancestor directories
  #   if empty.
  # - <tt>noop: true</tt> - does not remove directories.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.rmdir(%w[tmp0/tmp1 tmp2/tmp3], parents: true, verbose: true)
  #     FileUtils.rmdir('tmp4/tmp5', parents: true, verbose: true)
  #
  #   Output:
  #
  #     rmdir -p tmp0/tmp1 tmp2/tmp3
  #     rmdir -p tmp4/tmp5
  #
  # Raises an exception if a directory does not exist
  # or if for any reason a directory cannot be removed.
  #
  def rmdir(list, parents: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "rmdir #{parents ? '-p ' : ''}#{list.join ' '}" if verbose
    return if noop
    list.each do |dir|
      Dir.rmdir(dir = remove_trailing_slash(dir))
      if parents
        begin
          until (parent = File.dirname(dir)) == '.' or parent == dir
            dir = parent
            Dir.rmdir(dir)
          end
        rescue Errno::ENOTEMPTY, Errno::EEXIST, Errno::ENOENT
        end
      end
    end
  end
  module_function :rmdir

  # Creates {hard links}[https://en.wikipedia.org/wiki/Hard_link].
  #
  # When +src+ is the path to an existing file
  # and +dest+ is the path to a non-existent file,
  # creates a hard link at +dest+ pointing to +src+; returns zero:
  #
  #   Dir.children('tmp0/')                    # => ["t.txt"]
  #   Dir.children('tmp1/')                    # => []
  #   FileUtils.ln('tmp0/t.txt', 'tmp1/t.lnk') # => 0
  #   Dir.children('tmp1/')                    # => ["t.lnk"]
  #
  # When +src+ is the path to an existing file
  # and +dest+ is the path to an existing directory,
  # creates a hard link at <tt>dest/src</tt> pointing to +src+; returns zero:
  #
  #   Dir.children('tmp2')               # => ["t.dat"]
  #   Dir.children('tmp3')               # => []
  #   FileUtils.ln('tmp2/t.dat', 'tmp3') # => 0
  #   Dir.children('tmp3')               # => ["t.dat"]
  #
  # When +src+ is an array of paths to existing files
  # and +dest+ is the path to an existing directory,
  # then for each path +target+ in +src+,
  # creates a hard link at <tt>dest/target</tt> pointing to +target+;
  # returns +src+:
  #
  #   Dir.children('tmp4/')                               # => []
  #   FileUtils.ln(['tmp0/t.txt', 'tmp2/t.dat'], 'tmp4/') # => ["tmp0/t.txt", "tmp2/t.dat"]
  #   Dir.children('tmp4/')                               # => ["t.dat", "t.txt"]
  #
  # Keyword arguments:
  #
  # - <tt>force: true</tt> - overwrites +dest+ if it exists.
  # - <tt>noop: true</tt> - does not create links.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.ln('tmp0/t.txt', 'tmp1/t.lnk', verbose: true)
  #     FileUtils.ln('tmp2/t.dat', 'tmp3', verbose: true)
  #     FileUtils.ln(['tmp0/t.txt', 'tmp2/t.dat'], 'tmp4/', verbose: true)
  #
  #   Output:
  #
  #     ln tmp0/t.txt tmp1/t.lnk
  #     ln tmp2/t.dat tmp3
  #     ln tmp0/t.txt tmp2/t.dat tmp4/
  #
  # Raises an exception if +dest+ is the path to an existing file
  # and keyword argument +force+ is not +true+.
  #
  # FileUtils#link is an alias for FileUtils#ln.
  #
  def ln(src, dest, force: nil, noop: nil, verbose: nil)
    fu_output_message "ln#{force ? ' -f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest0(src, dest) do |s,d|
      remove_file d, true if force
      File.link s, d
    end
  end
  module_function :ln

  alias link ln
  module_function :link

  # Creates {hard links}[https://en.wikipedia.org/wiki/Hard_link].
  #
  # If +src+ is the path to a directory and +dest+ does not exist,
  # creates links +dest+ and descendents pointing to +src+ and its descendents:
  #
  #   Dir.glob('**/*.txt')
  #   # => ["tmp0/tmp2/t0.txt",
  #         "tmp0/tmp2/t1.txt",
  #         "tmp0/tmp3/t2.txt",
  #         "tmp0/tmp3/t3.txt"]
  #   FileUtils.cp_lr('tmp0', 'tmp1')
  #   Dir.glob('**/*.txt')
  #   # => ["tmp0/tmp2/t0.txt",
  #         "tmp0/tmp2/t1.txt",
  #         "tmp0/tmp3/t2.txt",
  #         "tmp0/tmp3/t3.txt",
  #         "tmp1/tmp2/t0.txt",
  #         "tmp1/tmp2/t1.txt",
  #         "tmp1/tmp3/t2.txt",
  #         "tmp1/tmp3/t3.txt"]
  #
  # If +src+ is an array of paths to files and +dest+ is the path to a directory,
  # for each path +filepath+ in +src+, creates a link at <tt>dest/filepath</tt>
  # pointing to that path:
  #
  #   FileUtils.rm_r('tmp1')
  #   Dir.mkdir('tmp1')
  #   FileUtils.cp_lr(['tmp0/tmp3/t2.txt', 'tmp0/tmp3/t3.txt'], 'tmp1')
  #   Dir.glob('**/*.txt')
  #   # => ["tmp0/tmp2/t0.txt",
  #        "tmp0/tmp2/t1.txt",
  #        "tmp0/tmp3/t2.txt",
  #        "tmp0/tmp3/t3.txt",
  #        "tmp1/t2.txt",
  #        "tmp1/t3.txt"]
  #
  # If +src+ and +dest+ are both paths to directories,
  # creates links <tt>dest/src</tt> and descendents
  # pointing to +src+ and its descendents:
  #
  #   FileUtils.rm_r('tmp1')
  #   Dir.mkdir('tmp1')
  #   FileUtils.cp_lr('tmp0', 'tmp1')
  #   # => ["tmp0/tmp2/t0.txt",
  #        "tmp0/tmp2/t1.txt",
  #        "tmp0/tmp3/t2.txt",
  #        "tmp0/tmp3/t3.txt",
  #        "tmp1/tmp0/tmp2/t0.txt",
  #        "tmp1/tmp0/tmp2/t1.txt",
  #        "tmp1/tmp0/tmp3/t2.txt",
  #        "tmp1/tmp0/tmp3/t3.txt"]
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: false</tt> - if +src+ is a symbolic link,
  #   does not dereference it.
  # - <tt>noop: true</tt> - does not create links.
  # - <tt>remove_destination: true</tt> - removes +dest+ before creating links.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cp_lr('tmp0', 'tmp1', verbose: true, noop: true)
  #     FileUtils.cp_lr(['tmp0/tmp3/t2.txt', 'tmp0/tmp3/t3.txt'], 'tmp1', verbose: true, noop: true)
  #
  #   Output:
  #
  #     cp -lr tmp0 tmp1
  #     cp -lr tmp0/tmp3/t2.txt tmp0/tmp3/t3.txt tmp1
  #
  # Raises an exception if +dest+ is the path to an existing file or directory
  # and keyword argument <tt>remove_destination: true</tt> is not given.
  #
  def cp_lr(src, dest, noop: nil, verbose: nil,
            dereference_root: true, remove_destination: false)
    fu_output_message "cp -lr#{remove_destination ? ' --remove-destination' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      link_entry s, d, dereference_root, remove_destination
    end
  end
  module_function :cp_lr

  # Creates {symbolic links}[https://en.wikipedia.org/wiki/Symbolic_link].
  #
  # When +src+ is the path to an existing file:
  #
  # - When +dest+ is the path to a non-existent file,
  #   creates a symbolic link at +dest+ pointing to +src+:
  #
  #     FileUtils.touch('src0.txt')
  #     File.exist?('dest0.txt')   # => false
  #     FileUtils.ln_s('src0.txt', 'dest0.txt')
  #     File.symlink?('dest0.txt') # => true
  #
  # - When +dest+ is the path to an existing file,
  #   creates a symbolic link at +dest+ pointing to +src+
  #   if and only if keyword argument <tt>force: true</tt> is given
  #   (raises an exception otherwise):
  #
  #     FileUtils.touch('src1.txt')
  #     FileUtils.touch('dest1.txt')
  #     FileUtils.ln_s('src1.txt', 'dest1.txt', force: true)
  #     FileTest.symlink?('dest1.txt') # => true
  #
  #     FileUtils.ln_s('src1.txt', 'dest1.txt') # Raises Errno::EEXIST.
  #
  # When +dest+ is the path to a directory,
  # creates a symbolic link at <tt>dest/src</tt> pointing to +src+:
  #
  #   FileUtils.touch('src2.txt')
  #   FileUtils.mkdir('destdir2')
  #   FileUtils.ln_s('src2.txt', 'destdir2')
  #   File.symlink?('destdir2/src2.txt') # => true
  #
  # When +src+ is an array of paths to existing files and +dest+ is a directory,
  # for each child +child+ in +src+ creates a symbolic link <tt>dest/child</tt>
  # pointing to +child+:
  #
  #   FileUtils.mkdir('srcdir3')
  #   FileUtils.touch('srcdir3/src0.txt')
  #   FileUtils.touch('srcdir3/src1.txt')
  #   FileUtils.mkdir('destdir3')
  #   FileUtils.ln_s(['srcdir3/src0.txt', 'srcdir3/src1.txt'], 'destdir3')
  #   File.symlink?('destdir3/src0.txt') # => true
  #   File.symlink?('destdir3/src1.txt') # => true
  #
  # Keyword arguments:
  #
  # - <tt>force: true</tt> - overwrites +dest+ if it exists.
  # - <tt>noop: true</tt> - does not create links.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.ln_s('src0.txt', 'dest0.txt', noop: true, verbose: true)
  #     FileUtils.ln_s('src1.txt', 'destdir1', noop: true, verbose: true)
  #     FileUtils.ln_s('src2.txt', 'dest2.txt', force: true, noop: true, verbose: true)
  #     FileUtils.ln_s(['srcdir3/src0.txt', 'srcdir3/src1.txt'], 'destdir3', noop: true, verbose: true)
  #
  #   Output:
  #
  #     ln -s src0.txt dest0.txt
  #     ln -s src1.txt destdir1
  #     ln -sf src2.txt dest2.txt
  #     ln -s srcdir3/src0.txt srcdir3/src1.txt destdir3
  #
  # FileUtils.symlink is an alias for FileUtils.ln_s.
  #
  def ln_s(src, dest, force: nil, noop: nil, verbose: nil)
    fu_output_message "ln -s#{force ? 'f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest0(src, dest) do |s,d|
      remove_file d, true if force
      File.symlink s, d
    end
  end
  module_function :ln_s

  alias symlink ln_s
  module_function :symlink

  # Like FileUtils.ln_s, but always with keyword argument <tt>force: true</tt> given.
  #
  def ln_sf(src, dest, noop: nil, verbose: nil)
    ln_s src, dest, force: true, noop: noop, verbose: verbose
  end
  module_function :ln_sf

  # Creates {hard links}[https://en.wikipedia.org/wiki/Hard_link]; returns +nil+.
  #
  # If +src+ is the path to a file and +dest+ does not exist,
  # creates a hard link at +dest+ pointing to +src+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt')   # => false
  #   FileUtils.link_entry('src0.txt', 'dest0.txt')
  #   File.exist?('dest0.txt') # => true
  #
  # If +src+ is the path to a directory and +dest+ does not exist,
  # recursively creates hard links at +dest+ pointing to paths in +src+:
  #
  #   FileUtils.mkdir_p(['src1/dir0', 'src1/dir1'])
  #   src_file_paths = [
  #     'src1/dir0/t0.txt',
  #     'src1/dir0/t1.txt',
  #     'src1/dir1/t2.txt',
  #     'src1/dir1/t3.txt',
  #     ]
  #   FileUtils.touch(src_file_paths)
  #   File.exist?('dest1')             # => true
  #   FileUtils.link_entry('src1', 'dest1')
  #   File.exist?('dest1/dir0/t0.txt') # => true
  #   File.exist?('dest1/dir0/t1.txt') # => true
  #   File.exist?('dest1/dir1/t2.txt') # => true
  #   File.exist?('dest1/dir1/t3.txt') # => true
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: true</tt> - dereferences +src+ if it is a symbolic link.
  # - <tt>remove_destination: true</tt> - removes +dest+ before creating links.
  #
  # Raises an exception if +dest+ is the path to an existing file or directory
  # and keyword argument <tt>remove_destination: true</tt> is not given.
  #
  def link_entry(src, dest, dereference_root = false, remove_destination = false)
    Entry_.new(src, nil, dereference_root).traverse do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      File.unlink destent.path if remove_destination && File.file?(destent.path)
      ent.link destent.path
    end
  end
  module_function :link_entry

  # Copies files from +src+ to +dest+.
  #
  # If +src+ is the path to a file and +dest+ is not the path to a directory,
  # copies +src+ to +dest+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.cp('src0.txt', 'dest0.txt')
  #   File.exist?('dest0.txt') # => true
  #
  # If +src+ is the path to a file and +dest+ is the path to a directory,
  # copies +src+ to <tt>dest/src</tt>:
  #
  #   FileUtils.touch('src1.txt')
  #   FileUtils.mkdir('dest1')
  #   FileUtils.cp('src1.txt', 'dest1')
  #   File.exist?('dest1/src1.txt') # => true
  #
  # If +src+ is an array of paths to files and +dest+ is the path to a directory,
  # copies from each +src+ to +dest+:
  #
  #   src_file_paths = ['src2.txt', 'src2.dat']
  #   FileUtils.touch(src_file_paths)
  #   FileUtils.mkdir('dest2')
  #   FileUtils.cp(src_file_paths, 'dest2')
  #   File.exist?('dest2/src2.txt') # => true
  #   File.exist?('dest2/src2.dat') # => true
  #
  # Keyword arguments:
  #
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>noop: true</tt> - does not copy files.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cp('src0.txt', 'dest0.txt', noop: true, verbose: true)
  #     FileUtils.cp('src1.txt', 'dest1', noop: true, verbose: true)
  #     FileUtils.cp(src_file_paths, 'dest2', noop: true, verbose: true)
  #
  #   Output:
  #
  #     cp src0.txt dest0.txt
  #     cp src1.txt dest1
  #     cp src2.txt src2.dat dest2
  #
  # Raises an exception if +src+ is a directory.
  #
  # Related: FileUtils.cp_r (recursive).
  #
  # FileUtils.copy is an alias for FileUtils.cp.
  #
  def cp(src, dest, preserve: nil, noop: nil, verbose: nil)
    fu_output_message "cp#{preserve ? ' -p' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      copy_file s, d, preserve
    end
  end
  module_function :cp

  alias copy cp
  module_function :copy

  # Recursively copies files from +src+ to +dest+.
  #
  #
  # If +src+ is the path to a file and +dest+ is not the path to a directory,
  # copies +src+ to +dest+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.cp_r('src0.txt', 'dest0.txt')
  #   File.exist?('dest0.txt') # => true
  #
  # If +src+ is the path to a file and +dest+ is the path to a directory,
  # copies +src+ to <tt>dest/src</tt>:
  #
  #   FileUtils.touch('src1.txt')
  #   FileUtils.mkdir('dest1')
  #   FileUtils.cp_r('src1.txt', 'dest1')
  #   File.exist?('dest1/src1.txt') # => true
  #
  # If +src+ is the path to a directory and +dest+ does not exist,
  # recursively copies +src+ to +dest+:
  #
  #   FileUtils.mkdir_p(['src2/dir0', 'src2/dir1'])
  #   FileUtils.touch('src2/dir0/src0.txt')
  #   FileUtils.touch('src2/dir0/src1.txt')
  #   FileUtils.touch('src2/dir1/src2.txt')
  #   FileUtils.touch('src2/dir1/src3.txt')
  #   FileUtils.cp_r('src2', 'dest2')
  #   File.exist?('dest2/dir0/src0.txt') # => true
  #   File.exist?('dest2/dir0/src1.txt') # => true
  #   File.exist?('dest2/dir1/src2.txt') # => true
  #   File.exist?('dest2/dir1/src3.txt') # => true
  #
  # If +src+ and +dest+ are paths to directories,
  # recursively copies +src+ to <tt>dest/src</tt>:
  #
  #   FileUtils.mkdir_p(['src3/dir0', 'src3/dir1'])
  #   FileUtils.touch('src3/dir0/src0.txt')
  #   FileUtils.touch('src3/dir0/src1.txt')
  #   FileUtils.touch('src3/dir1/src2.txt')
  #   FileUtils.touch('src3/dir1/src3.txt')
  #   FileUtils.mkdir('dest3')
  #   FileUtils.cp_r('src3', 'dest3')
  #   File.exist?('dest3/src3/dir0/src0.txt') # => true
  #   File.exist?('dest3/src3/dir0/src1.txt') # => true
  #   File.exist?('dest3/src3/dir1/src2.txt') # => true
  #   File.exist?('dest3/src3/dir1/src3.txt') # => true
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: false</tt> - if +src+ is a symbolic link,
  #   does not dereference it.
  # - <tt>noop: true</tt> - does not copy files.
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>remove_destination: true</tt> - removes +dest+ before copying files.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cp_r('src0.txt', 'dest0.txt', noop: true, verbose: true)
  #     FileUtils.cp_r('src1.txt', 'dest1', noop: true, verbose: true)
  #     FileUtils.cp_r('src2', 'dest2', noop: true, verbose: true)
  #     FileUtils.cp_r('src3', 'dest3', noop: true, verbose: true)
  #
  #   Output:
  #
  #     cp -r src0.txt dest0.txt
  #     cp -r src1.txt dest1
  #     cp -r src2 dest2
  #     cp -r src3 dest3
  #
  # Raises an exception of +src+ is the path to a directory
  # and +dest+ is the path to a file.
  #
  # Related: FileUtils.cp (not recursive).
  #
  def cp_r(src, dest, preserve: nil, noop: nil, verbose: nil,
           dereference_root: true, remove_destination: nil)
    fu_output_message "cp -r#{preserve ? 'p' : ''}#{remove_destination ? ' --remove-destination' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      copy_entry s, d, preserve, dereference_root, remove_destination
    end
  end
  module_function :cp_r

  # Recursively copies files from +src+ to +dest+.
  #
  # If +src+ is the path to a file, copies +src+ to +dest+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.copy_entry('src0.txt', 'dest0.txt')
  #   File.file?('dest0.txt')  # => true
  #
  # If +src+ is a directory, recursively copies +src+ to +dest+:
  #
  #   system('tree --charset=ascii src1')
  #   src1
  #   |-- dir0
  #   |   |-- src0.txt
  #   |   `-- src1.txt
  #   `-- dir1
  #       |-- src2.txt
  #       `-- src3.txt
  #   FileUtils.copy_entry('src1', 'dest1')
  #   system('tree --charset=ascii dest1')
  #   dest1
  #   |-- dir0
  #   |   |-- src0.txt
  #   |   `-- src1.txt
  #   `-- dir1
  #       |-- src2.txt
  #       `-- src3.txt
  #
  # The recursive copying preserves file types for regular files,
  # directories, and symbolic links;
  # other file types (FIFO streams, device files, etc.) are not supported.
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: true</tt> - if +src+ is a symbolic link,
  #   follows the link.
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>remove_destination: true</tt> - removes +dest+ before copying files.
  #
  def copy_entry(src, dest, preserve = false, dereference_root = false, remove_destination = false)
    if dereference_root
      src = File.realpath(src)
    end

    Entry_.new(src, nil, false).wrap_traverse(proc do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      File.unlink destent.path if remove_destination && (File.file?(destent.path) || File.symlink?(destent.path))
      ent.copy destent.path
    end, proc do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      ent.copy_metadata destent.path if preserve
    end)
  end
  module_function :copy_entry

  # Copies file from +src+ to +dest+, which should not be directories:
  #
  #   FileUtils.touch('src0.txt')
  #   FileUtils.copy_file('src0.txt', 'dest0.txt')
  #   File.file?('dest0.txt') # => true
  #
  # Keyword arguments:
  #
  # - <tt>dereference: false</tt> - if +src+ is a symbolic link,
  #   does not follow the link.
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>remove_destination: true</tt> - removes +dest+ before copying files.
  #
  def copy_file(src, dest, preserve = false, dereference = true)
    ent = Entry_.new(src, nil, dereference)
    ent.copy_file dest
    ent.copy_metadata dest if preserve
  end
  module_function :copy_file

  # Copies \IO stream +src+ to \IO stream +dest+ via
  # {IO.copy_stream}[https://docs.ruby-lang.org/en/master/IO.html#method-c-copy_stream].
  #
  def copy_stream(src, dest)
    IO.copy_stream(src, dest)
  end
  module_function :copy_stream

  # Moves files from +src+ to +dest+.
  # If +src+ and +dest+ are on different devices,
  # first copies, then removes +src+.
  #
  # If +src+ is the path to a single file or directory and +dest+ does not exist,
  # moves +src+ to +dest+:
  #
  #   system('tree --charset=ascii src0')
  #   src0
  #   |-- src0.txt
  #   `-- src1.txt
  #   File.exist?('dest0') # => false
  #   FileUtils.mv('src0', 'dest0')
  #   File.exist?('src0')  # => false
  #   system('tree --charset=ascii dest0')
  #   dest0
  #   |-- src0.txt
  #   `-- src1.txt
  #
  # If +src+ is an array of paths to files and directories
  # and +dest+ is the path to a directory,
  # copies from each path in the array to +dest+:
  #
  #   File.file?('src1.txt') # => true
  #   system('tree --charset=ascii src1')
  #   src1
  #   |-- src.dat
  #   `-- src.txt
  #   Dir.empty?('dest1') # => true
  #   FileUtils.mv(['src1.txt', 'src1'], 'dest1')
  #   system('tree --charset=ascii dest1')
  #   dest1
  #   |-- src1
  #   |   |-- src.dat
  #   |   `-- src.txt
  #   `-- src1.txt
  #
  # - <tt>force: true</tt> - attempts to force the move;
  #   if the move includes removing +src+
  #   (that is, if +src+ and +dest+ are on different devices),
  #   ignores raised exceptions of StandardError and its descendants.
  # - <tt>noop: true</tt> - does not move files.
  # - <tt>secure: true</tt> - removes +src+ securely
  #   by calling FileUtils.remove_entry_secure.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.mv('src0', 'dest0', noop: true, verbose: true)
  #     FileUtils.mv(['src1.txt', 'src1'], 'dest1', noop: true, verbose: true)
  #
  #   Output:
  #
  #     mv src0 dest0
  #     mv src1.txt src1 dest1
  #
  # FileUtils.move is an alias for FileUtils.mv.
  #
  def mv(src, dest, force: nil, noop: nil, verbose: nil, secure: nil)
    fu_output_message "mv#{force ? ' -f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      destent = Entry_.new(d, nil, true)
      begin
        if destent.exist?
          if destent.directory?
            raise Errno::EEXIST, d
          end
        end
        begin
          File.rename s, d
        rescue Errno::EXDEV,
               Errno::EPERM # move from unencrypted to encrypted dir (ext4)
          copy_entry s, d, true
          if secure
            remove_entry_secure s, force
          else
            remove_entry s, force
          end
        end
      rescue SystemCallError
        raise unless force
      end
    end
  end
  module_function :mv

  alias move mv
  module_function :move

  #
  # Remove file(s) specified in +list+.  This method cannot remove directories.
  # All StandardErrors are ignored when the :force option is set.
  #
  #   FileUtils.rm %w( junk.txt dust.txt )
  #   FileUtils.rm Dir.glob('*.so')
  #   FileUtils.rm 'NotExistFile', force: true   # never raises exception
  #
  def rm(list, force: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "rm#{force ? ' -f' : ''} #{list.join ' '}" if verbose
    return if noop

    list.each do |path|
      remove_file path, force
    end
  end
  module_function :rm

  alias remove rm
  module_function :remove

  #
  # Equivalent to
  #
  #   FileUtils.rm(list, force: true)
  #
  def rm_f(list, noop: nil, verbose: nil)
    rm list, force: true, noop: noop, verbose: verbose
  end
  module_function :rm_f

  alias safe_unlink rm_f
  module_function :safe_unlink

  #
  # remove files +list+[0] +list+[1]... If +list+[n] is a directory,
  # removes its all contents recursively. This method ignores
  # StandardError when :force option is set.
  #
  #   FileUtils.rm_r Dir.glob('/tmp/*')
  #   FileUtils.rm_r 'some_dir', force: true
  #
  # WARNING: This method causes local vulnerability
  # if one of parent directories or removing directory tree are world
  # writable (including /tmp, whose permission is 1777), and the current
  # process has strong privilege such as Unix super user (root), and the
  # system has symbolic link.  For secure removing, read the documentation
  # of remove_entry_secure carefully, and set :secure option to true.
  # Default is <tt>secure: false</tt>.
  #
  # NOTE: This method calls remove_entry_secure if :secure option is set.
  # See also remove_entry_secure.
  #
  def rm_r(list, force: nil, noop: nil, verbose: nil, secure: nil)
    list = fu_list(list)
    fu_output_message "rm -r#{force ? 'f' : ''} #{list.join ' '}" if verbose
    return if noop
    list.each do |path|
      if secure
        remove_entry_secure path, force
      else
        remove_entry path, force
      end
    end
  end
  module_function :rm_r

  #
  # Equivalent to
  #
  #   FileUtils.rm_r(list, force: true)
  #
  # WARNING: This method causes local vulnerability.
  # Read the documentation of rm_r first.
  #
  def rm_rf(list, noop: nil, verbose: nil, secure: nil)
    rm_r list, force: true, noop: noop, verbose: verbose, secure: secure
  end
  module_function :rm_rf

  alias rmtree rm_rf
  module_function :rmtree

  #
  # This method removes a file system entry +path+.  +path+ shall be a
  # regular file, a directory, or something.  If +path+ is a directory,
  # remove it recursively.  This method is required to avoid TOCTTOU
  # (time-of-check-to-time-of-use) local security vulnerability of rm_r.
  # #rm_r causes security hole when:
  #
  # * Parent directory is world writable (including /tmp).
  # * Removing directory tree includes world writable directory.
  # * The system has symbolic link.
  #
  # To avoid this security hole, this method applies special preprocess.
  # If +path+ is a directory, this method chown(2) and chmod(2) all
  # removing directories.  This requires the current process is the
  # owner of the removing whole directory tree, or is the super user (root).
  #
  # WARNING: You must ensure that *ALL* parent directories cannot be
  # moved by other untrusted users.  For example, parent directories
  # should not be owned by untrusted users, and should not be world
  # writable except when the sticky bit set.
  #
  # WARNING: Only the owner of the removing directory tree, or Unix super
  # user (root) should invoke this method.  Otherwise this method does not
  # work.
  #
  # For details of this security vulnerability, see Perl's case:
  #
  # * https://cve.mitre.org/cgi-bin/cvename.cgi?name=CAN-2005-0448
  # * https://cve.mitre.org/cgi-bin/cvename.cgi?name=CAN-2004-0452
  #
  # For fileutils.rb, this vulnerability is reported in [ruby-dev:26100].
  #
  def remove_entry_secure(path, force = false)
    unless fu_have_symlink?
      remove_entry path, force
      return
    end
    fullpath = File.expand_path(path)
    st = File.lstat(fullpath)
    unless st.directory?
      File.unlink fullpath
      return
    end
    # is a directory.
    parent_st = File.stat(File.dirname(fullpath))
    unless parent_st.world_writable?
      remove_entry path, force
      return
    end
    unless parent_st.sticky?
      raise ArgumentError, "parent directory is world writable, FileUtils#remove_entry_secure does not work; abort: #{path.inspect} (parent directory mode #{'%o' % parent_st.mode})"
    end

    # freeze tree root
    euid = Process.euid
    dot_file = fullpath + "/."
    begin
      File.open(dot_file) {|f|
        unless fu_stat_identical_entry?(st, f.stat)
          # symlink (TOC-to-TOU attack?)
          File.unlink fullpath
          return
        end
        f.chown euid, -1
        f.chmod 0700
      }
    rescue Errno::EISDIR # JRuby in non-native mode can't open files as dirs
      File.lstat(dot_file).tap {|fstat|
        unless fu_stat_identical_entry?(st, fstat)
          # symlink (TOC-to-TOU attack?)
          File.unlink fullpath
          return
        end
        File.chown euid, -1, dot_file
        File.chmod 0700, dot_file
      }
    end

    unless fu_stat_identical_entry?(st, File.lstat(fullpath))
      # TOC-to-TOU attack?
      File.unlink fullpath
      return
    end

    # ---- tree root is frozen ----
    root = Entry_.new(path)
    root.preorder_traverse do |ent|
      if ent.directory?
        ent.chown euid, -1
        ent.chmod 0700
      end
    end
    root.postorder_traverse do |ent|
      begin
        ent.remove
      rescue
        raise unless force
      end
    end
  rescue
    raise unless force
  end
  module_function :remove_entry_secure

  def fu_have_symlink?   #:nodoc:
    File.symlink nil, nil
  rescue NotImplementedError
    return false
  rescue TypeError
    return true
  end
  private_module_function :fu_have_symlink?

  def fu_stat_identical_entry?(a, b)   #:nodoc:
    a.dev == b.dev and a.ino == b.ino
  end
  private_module_function :fu_stat_identical_entry?

  #
  # This method removes a file system entry +path+.
  # +path+ might be a regular file, a directory, or something.
  # If +path+ is a directory, remove it recursively.
  #
  # See also remove_entry_secure.
  #
  def remove_entry(path, force = false)
    Entry_.new(path).postorder_traverse do |ent|
      begin
        ent.remove
      rescue
        raise unless force
      end
    end
  rescue
    raise unless force
  end
  module_function :remove_entry

  #
  # Removes a file +path+.
  # This method ignores StandardError if +force+ is true.
  #
  def remove_file(path, force = false)
    Entry_.new(path).remove_file
  rescue
    raise unless force
  end
  module_function :remove_file

  #
  # Removes a directory +dir+ and its contents recursively.
  # This method ignores StandardError if +force+ is true.
  #
  def remove_dir(path, force = false)
    remove_entry path, force   # FIXME?? check if it is a directory
  end
  module_function :remove_dir

  #
  # Returns true if the contents of a file +a+ and a file +b+ are identical.
  #
  #   FileUtils.compare_file('somefile', 'somefile')       #=> true
  #   FileUtils.compare_file('/dev/null', '/dev/urandom')  #=> false
  #
  def compare_file(a, b)
    return false unless File.size(a) == File.size(b)
    File.open(a, 'rb') {|fa|
      File.open(b, 'rb') {|fb|
        return compare_stream(fa, fb)
      }
    }
  end
  module_function :compare_file

  alias identical? compare_file
  alias cmp compare_file
  module_function :identical?
  module_function :cmp

  #
  # Returns true if the contents of a stream +a+ and +b+ are identical.
  #
  def compare_stream(a, b)
    bsize = fu_stream_blksize(a, b)

    sa = String.new(capacity: bsize)
    sb = String.new(capacity: bsize)

    begin
      a.read(bsize, sa)
      b.read(bsize, sb)
      return true if sa.empty? && sb.empty?
    end while sa == sb
    false
  end
  module_function :compare_stream

  #
  # If +src+ is not same as +dest+, copies it and changes the permission
  # mode to +mode+.  If +dest+ is a directory, destination is +dest+/+src+.
  # This method removes destination before copy.
  #
  #   FileUtils.install 'ruby', '/usr/local/bin/ruby', mode: 0755, verbose: true
  #   FileUtils.install 'lib.rb', '/usr/local/lib/ruby/site_ruby', verbose: true
  #
  def install(src, dest, mode: nil, owner: nil, group: nil, preserve: nil,
              noop: nil, verbose: nil)
    if verbose
      msg = +"install -c"
      msg << ' -p' if preserve
      msg << ' -m ' << mode_to_s(mode) if mode
      msg << " -o #{owner}" if owner
      msg << " -g #{group}" if group
      msg << ' ' << [src,dest].flatten.join(' ')
      fu_output_message msg
    end
    return if noop
    uid = fu_get_uid(owner)
    gid = fu_get_gid(group)
    fu_each_src_dest(src, dest) do |s, d|
      st = File.stat(s)
      unless File.exist?(d) and compare_file(s, d)
        remove_file d, true
        copy_file s, d
        File.utime st.atime, st.mtime, d if preserve
        File.chmod fu_mode(mode, st), d if mode
        File.chown uid, gid, d if uid or gid
      end
    end
  end
  module_function :install

  def user_mask(target)  #:nodoc:
    target.each_char.inject(0) do |mask, chr|
      case chr
      when "u"
        mask | 04700
      when "g"
        mask | 02070
      when "o"
        mask | 01007
      when "a"
        mask | 07777
      else
        raise ArgumentError, "invalid `who' symbol in file mode: #{chr}"
      end
    end
  end
  private_module_function :user_mask

  def apply_mask(mode, user_mask, op, mode_mask)   #:nodoc:
    case op
    when '='
      (mode & ~user_mask) | (user_mask & mode_mask)
    when '+'
      mode | (user_mask & mode_mask)
    when '-'
      mode & ~(user_mask & mode_mask)
    end
  end
  private_module_function :apply_mask

  def symbolic_modes_to_i(mode_sym, path)  #:nodoc:
    path = File.stat(path) unless File::Stat === path
    mode = path.mode
    mode_sym.split(/,/).inject(mode & 07777) do |current_mode, clause|
      target, *actions = clause.split(/([=+-])/)
      raise ArgumentError, "invalid file mode: #{mode_sym}" if actions.empty?
      target = 'a' if target.empty?
      user_mask = user_mask(target)
      actions.each_slice(2) do |op, perm|
        need_apply = op == '='
        mode_mask = (perm || '').each_char.inject(0) do |mask, chr|
          case chr
          when "r"
            mask | 0444
          when "w"
            mask | 0222
          when "x"
            mask | 0111
          when "X"
            if path.directory?
              mask | 0111
            else
              mask
            end
          when "s"
            mask | 06000
          when "t"
            mask | 01000
          when "u", "g", "o"
            if mask.nonzero?
              current_mode = apply_mask(current_mode, user_mask, op, mask)
            end
            need_apply = false
            copy_mask = user_mask(chr)
            (current_mode & copy_mask) / (copy_mask & 0111) * (user_mask & 0111)
          else
            raise ArgumentError, "invalid `perm' symbol in file mode: #{chr}"
          end
        end

        if mode_mask.nonzero? || need_apply
          current_mode = apply_mask(current_mode, user_mask, op, mode_mask)
        end
      end
      current_mode
    end
  end
  private_module_function :symbolic_modes_to_i

  def fu_mode(mode, path)  #:nodoc:
    mode.is_a?(String) ? symbolic_modes_to_i(mode, path) : mode
  end
  private_module_function :fu_mode

  def mode_to_s(mode)  #:nodoc:
    mode.is_a?(String) ? mode : "%o" % mode
  end
  private_module_function :mode_to_s

  #
  # Changes permission bits on the named files (in +list+) to the bit pattern
  # represented by +mode+.
  #
  # +mode+ is the symbolic and absolute mode can be used.
  #
  # Absolute mode is
  #   FileUtils.chmod 0755, 'somecommand'
  #   FileUtils.chmod 0644, %w(my.rb your.rb his.rb her.rb)
  #   FileUtils.chmod 0755, '/usr/bin/ruby', verbose: true
  #
  # Symbolic mode is
  #   FileUtils.chmod "u=wrx,go=rx", 'somecommand'
  #   FileUtils.chmod "u=wr,go=rr", %w(my.rb your.rb his.rb her.rb)
  #   FileUtils.chmod "u=wrx,go=rx", '/usr/bin/ruby', verbose: true
  #
  # "a" :: is user, group, other mask.
  # "u" :: is user's mask.
  # "g" :: is group's mask.
  # "o" :: is other's mask.
  # "w" :: is write permission.
  # "r" :: is read permission.
  # "x" :: is execute permission.
  # "X" ::
  #   is execute permission for directories only, must be used in conjunction with "+"
  # "s" :: is uid, gid.
  # "t" :: is sticky bit.
  # "+" :: is added to a class given the specified mode.
  # "-" :: Is removed from a given class given mode.
  # "=" :: Is the exact nature of the class will be given a specified mode.

  def chmod(mode, list, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message sprintf('chmod %s %s', mode_to_s(mode), list.join(' ')) if verbose
    return if noop
    list.each do |path|
      Entry_.new(path).chmod(fu_mode(mode, path))
    end
  end
  module_function :chmod

  #
  # Changes permission bits on the named files (in +list+)
  # to the bit pattern represented by +mode+.
  #
  #   FileUtils.chmod_R 0700, "/tmp/app.#{$$}"
  #   FileUtils.chmod_R "u=wrx", "/tmp/app.#{$$}"
  #
  def chmod_R(mode, list, noop: nil, verbose: nil, force: nil)
    list = fu_list(list)
    fu_output_message sprintf('chmod -R%s %s %s',
                              (force ? 'f' : ''),
                              mode_to_s(mode), list.join(' ')) if verbose
    return if noop
    list.each do |root|
      Entry_.new(root).traverse do |ent|
        begin
          ent.chmod(fu_mode(mode, ent.path))
        rescue
          raise unless force
        end
      end
    end
  end
  module_function :chmod_R

  #
  # Changes owner and group on the named files (in +list+)
  # to the user +user+ and the group +group+.  +user+ and +group+
  # may be an ID (Integer/String) or a name (String).
  # If +user+ or +group+ is nil, this method does not change
  # the attribute.
  #
  #   FileUtils.chown 'root', 'staff', '/usr/local/bin/ruby'
  #   FileUtils.chown nil, 'bin', Dir.glob('/usr/bin/*'), verbose: true
  #
  def chown(user, group, list, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message sprintf('chown %s %s',
                              (group ? "#{user}:#{group}" : user || ':'),
                              list.join(' ')) if verbose
    return if noop
    uid = fu_get_uid(user)
    gid = fu_get_gid(group)
    list.each do |path|
      Entry_.new(path).chown uid, gid
    end
  end
  module_function :chown

  #
  # Changes owner and group on the named files (in +list+)
  # to the user +user+ and the group +group+ recursively.
  # +user+ and +group+ may be an ID (Integer/String) or
  # a name (String).  If +user+ or +group+ is nil, this
  # method does not change the attribute.
  #
  #   FileUtils.chown_R 'www', 'www', '/var/www/htdocs'
  #   FileUtils.chown_R 'cvs', 'cvs', '/var/cvs', verbose: true
  #
  def chown_R(user, group, list, noop: nil, verbose: nil, force: nil)
    list = fu_list(list)
    fu_output_message sprintf('chown -R%s %s %s',
                              (force ? 'f' : ''),
                              (group ? "#{user}:#{group}" : user || ':'),
                              list.join(' ')) if verbose
    return if noop
    uid = fu_get_uid(user)
    gid = fu_get_gid(group)
    list.each do |root|
      Entry_.new(root).traverse do |ent|
        begin
          ent.chown uid, gid
        rescue
          raise unless force
        end
      end
    end
  end
  module_function :chown_R

  def fu_get_uid(user)   #:nodoc:
    return nil unless user
    case user
    when Integer
      user
    when /\A\d+\z/
      user.to_i
    else
      require 'etc'
      Etc.getpwnam(user) ? Etc.getpwnam(user).uid : nil
    end
  end
  private_module_function :fu_get_uid

  def fu_get_gid(group)   #:nodoc:
    return nil unless group
    case group
    when Integer
      group
    when /\A\d+\z/
      group.to_i
    else
      require 'etc'
      Etc.getgrnam(group) ? Etc.getgrnam(group).gid : nil
    end
  end
  private_module_function :fu_get_gid

  #
  # Updates modification time (mtime) and access time (atime) of file(s) in
  # +list+.  Files are created if they don't exist.
  #
  #   FileUtils.touch 'timestamp'
  #   FileUtils.touch Dir.glob('*.c');  system 'make'
  #
  def touch(list, noop: nil, verbose: nil, mtime: nil, nocreate: nil)
    list = fu_list(list)
    t = mtime
    if verbose
      fu_output_message "touch #{nocreate ? '-c ' : ''}#{t ? t.strftime('-t %Y%m%d%H%M.%S ') : ''}#{list.join ' '}"
    end
    return if noop
    list.each do |path|
      created = nocreate
      begin
        File.utime(t, t, path)
      rescue Errno::ENOENT
        raise if created
        File.open(path, 'a') {
          ;
        }
        created = true
        retry if t
      end
    end
  end
  module_function :touch

  private

  module StreamUtils_
    private

    case (defined?(::RbConfig) ? ::RbConfig::CONFIG['host_os'] : ::RUBY_PLATFORM)
    when /mswin|mingw/
      def fu_windows?; true end
    else
      def fu_windows?; false end
    end

    def fu_copy_stream0(src, dest, blksize = nil)   #:nodoc:
      IO.copy_stream(src, dest)
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
  end

  include StreamUtils_
  extend StreamUtils_

  class Entry_   #:nodoc: internal use only
    include StreamUtils_

    def initialize(a, b = nil, deref = false)
      @prefix = @rel = @path = nil
      if b
        @prefix = a
        @rel = b
      else
        @path = a
      end
      @deref = deref
      @stat = nil
      @lstat = nil
    end

    def inspect
      "\#<#{self.class} #{path()}>"
    end

    def path
      if @path
        File.path(@path)
      else
        join(@prefix, @rel)
      end
    end

    def prefix
      @prefix || @path
    end

    def rel
      @rel
    end

    def dereference?
      @deref
    end

    def exist?
      begin
        lstat
        true
      rescue Errno::ENOENT
        false
      end
    end

    def file?
      s = lstat!
      s and s.file?
    end

    def directory?
      s = lstat!
      s and s.directory?
    end

    def symlink?
      s = lstat!
      s and s.symlink?
    end

    def chardev?
      s = lstat!
      s and s.chardev?
    end

    def blockdev?
      s = lstat!
      s and s.blockdev?
    end

    def socket?
      s = lstat!
      s and s.socket?
    end

    def pipe?
      s = lstat!
      s and s.pipe?
    end

    S_IF_DOOR = 0xD000

    def door?
      s = lstat!
      s and (s.mode & 0xF000 == S_IF_DOOR)
    end

    def entries
      opts = {}
      opts[:encoding] = fu_windows? ? ::Encoding::UTF_8 : path.encoding

      files = Dir.children(path, **opts)

      untaint = RUBY_VERSION < '2.7'
      files.map {|n| Entry_.new(prefix(), join(rel(), untaint ? n.untaint : n)) }
    end

    def stat
      return @stat if @stat
      if lstat() and lstat().symlink?
        @stat = File.stat(path())
      else
        @stat = lstat()
      end
      @stat
    end

    def stat!
      return @stat if @stat
      if lstat! and lstat!.symlink?
        @stat = File.stat(path())
      else
        @stat = lstat!
      end
      @stat
    rescue SystemCallError
      nil
    end

    def lstat
      if dereference?
        @lstat ||= File.stat(path())
      else
        @lstat ||= File.lstat(path())
      end
    end

    def lstat!
      lstat()
    rescue SystemCallError
      nil
    end

    def chmod(mode)
      if symlink?
        File.lchmod mode, path() if have_lchmod?
      else
        File.chmod mode, path()
      end
    rescue Errno::EOPNOTSUPP
    end

    def chown(uid, gid)
      if symlink?
        File.lchown uid, gid, path() if have_lchown?
      else
        File.chown uid, gid, path()
      end
    end

    def link(dest)
      case
      when directory?
        if !File.exist?(dest) and descendant_directory?(dest, path)
          raise ArgumentError, "cannot link directory %s to itself %s" % [path, dest]
        end
        begin
          Dir.mkdir dest
        rescue
          raise unless File.directory?(dest)
        end
      else
        File.link path(), dest
      end
    end

    def copy(dest)
      lstat
      case
      when file?
        copy_file dest
      when directory?
        if !File.exist?(dest) and descendant_directory?(dest, path)
          raise ArgumentError, "cannot copy directory %s to itself %s" % [path, dest]
        end
        begin
          Dir.mkdir dest
        rescue
          raise unless File.directory?(dest)
        end
      when symlink?
        File.symlink File.readlink(path()), dest
      when chardev?, blockdev?
        raise "cannot handle device file"
      when socket?
        begin
          require 'socket'
        rescue LoadError
          raise "cannot handle socket"
        else
          raise "cannot handle socket" unless defined?(UNIXServer)
        end
        UNIXServer.new(dest).close
        File.chmod lstat().mode, dest
      when pipe?
        raise "cannot handle FIFO" unless File.respond_to?(:mkfifo)
        File.mkfifo dest, lstat().mode
      when door?
        raise "cannot handle door: #{path()}"
      else
        raise "unknown file type: #{path()}"
      end
    end

    def copy_file(dest)
      File.open(path()) do |s|
        File.open(dest, 'wb', s.stat.mode) do |f|
          IO.copy_stream(s, f)
        end
      end
    end

    def copy_metadata(path)
      st = lstat()
      if !st.symlink?
        File.utime st.atime, st.mtime, path
      end
      mode = st.mode
      begin
        if st.symlink?
          begin
            File.lchown st.uid, st.gid, path
          rescue NotImplementedError
          end
        else
          File.chown st.uid, st.gid, path
        end
      rescue Errno::EPERM, Errno::EACCES
        # clear setuid/setgid
        mode &= 01777
      end
      if st.symlink?
        begin
          File.lchmod mode, path
        rescue NotImplementedError, Errno::EOPNOTSUPP
        end
      else
        File.chmod mode, path
      end
    end

    def remove
      if directory?
        remove_dir1
      else
        remove_file
      end
    end

    def remove_dir1
      platform_support {
        Dir.rmdir path().chomp(?/)
      }
    end

    def remove_file
      platform_support {
        File.unlink path
      }
    end

    def platform_support
      return yield unless fu_windows?
      first_time_p = true
      begin
        yield
      rescue Errno::ENOENT
        raise
      rescue => err
        if first_time_p
          first_time_p = false
          begin
            File.chmod 0700, path()   # Windows does not have symlink
            retry
          rescue SystemCallError
          end
        end
        raise err
      end
    end

    def preorder_traverse
      stack = [self]
      while ent = stack.pop
        yield ent
        stack.concat ent.entries.reverse if ent.directory?
      end
    end

    alias traverse preorder_traverse

    def postorder_traverse
      if directory?
        entries().each do |ent|
          ent.postorder_traverse do |e|
            yield e
          end
        end
      end
    ensure
      yield self
    end

    def wrap_traverse(pre, post)
      pre.call self
      if directory?
        entries.each do |ent|
          ent.wrap_traverse pre, post
        end
      end
      post.call self
    end

    private

    @@fileutils_rb_have_lchmod = nil

    def have_lchmod?
      # This is not MT-safe, but it does not matter.
      if @@fileutils_rb_have_lchmod == nil
        @@fileutils_rb_have_lchmod = check_have_lchmod?
      end
      @@fileutils_rb_have_lchmod
    end

    def check_have_lchmod?
      return false unless File.respond_to?(:lchmod)
      File.lchmod 0
      return true
    rescue NotImplementedError
      return false
    end

    @@fileutils_rb_have_lchown = nil

    def have_lchown?
      # This is not MT-safe, but it does not matter.
      if @@fileutils_rb_have_lchown == nil
        @@fileutils_rb_have_lchown = check_have_lchown?
      end
      @@fileutils_rb_have_lchown
    end

    def check_have_lchown?
      return false unless File.respond_to?(:lchown)
      File.lchown nil, nil
      return true
    rescue NotImplementedError
      return false
    end

    def join(dir, base)
      return File.path(dir) if not base or base == '.'
      return File.path(base) if not dir or dir == '.'
      begin
        File.join(dir, base)
      rescue EncodingError
        if fu_windows?
          File.join(dir.encode(::Encoding::UTF_8), base.encode(::Encoding::UTF_8))
        else
          raise
        end
      end
    end

    if File::ALT_SEPARATOR
      DIRECTORY_TERM = "(?=[/#{Regexp.quote(File::ALT_SEPARATOR)}]|\\z)"
    else
      DIRECTORY_TERM = "(?=/|\\z)"
    end

    def descendant_directory?(descendant, ascendant)
      if File::FNM_SYSCASE.nonzero?
        File.expand_path(File.dirname(descendant)).casecmp(File.expand_path(ascendant)) == 0
      else
        File.expand_path(File.dirname(descendant)) == File.expand_path(ascendant)
      end
    end
  end   # class Entry_

  def fu_list(arg)   #:nodoc:
    [arg].flatten.map {|path| File.path(path) }
  end
  private_module_function :fu_list

  def fu_each_src_dest(src, dest)   #:nodoc:
    fu_each_src_dest0(src, dest) do |s, d|
      raise ArgumentError, "same file: #{s} and #{d}" if fu_same?(s, d)
      yield s, d
    end
  end
  private_module_function :fu_each_src_dest

  def fu_each_src_dest0(src, dest)   #:nodoc:
    if tmp = Array.try_convert(src)
      tmp.each do |s|
        s = File.path(s)
        yield s, File.join(dest, File.basename(s))
      end
    else
      src = File.path(src)
      if File.directory?(dest)
        yield src, File.join(dest, File.basename(src))
      else
        yield src, File.path(dest)
      end
    end
  end
  private_module_function :fu_each_src_dest0

  def fu_same?(a, b)   #:nodoc:
    File.identical?(a, b)
  end
  private_module_function :fu_same?

  def fu_output_message(msg)   #:nodoc:
    output = @fileutils_output if defined?(@fileutils_output)
    output ||= $stdout
    if defined?(@fileutils_label)
      msg = @fileutils_label + msg
    end
    output.puts msg
  end
  private_module_function :fu_output_message

  # This hash table holds command options.
  OPT_TABLE = {}    #:nodoc: internal use only
  (private_instance_methods & methods(false)).inject(OPT_TABLE) {|tbl, name|
    (tbl[name.to_s] = instance_method(name).parameters).map! {|t, n| n if t == :key}.compact!
    tbl
  }

  public

  #
  # Returns an Array of names of high-level methods that accept any keyword
  # arguments.
  #
  #   p FileUtils.commands  #=> ["chmod", "cp", "cp_r", "install", ...]
  #
  def self.commands
    OPT_TABLE.keys
  end

  #
  # Returns an Array of option names.
  #
  #   p FileUtils.options  #=> ["noop", "force", "verbose", "preserve", "mode"]
  #
  def self.options
    OPT_TABLE.values.flatten.uniq.map {|sym| sym.to_s }
  end

  #
  # Returns true if the method +mid+ have an option +opt+.
  #
  #   p FileUtils.have_option?(:cp, :noop)     #=> true
  #   p FileUtils.have_option?(:rm, :force)    #=> true
  #   p FileUtils.have_option?(:rm, :preserve) #=> false
  #
  def self.have_option?(mid, opt)
    li = OPT_TABLE[mid.to_s] or raise ArgumentError, "no such method: #{mid}"
    li.include?(opt)
  end

  #
  # Returns an Array of option names of the method +mid+.
  #
  #   p FileUtils.options_of(:rm)  #=> ["noop", "verbose", "force"]
  #
  def self.options_of(mid)
    OPT_TABLE[mid.to_s].map {|sym| sym.to_s }
  end

  #
  # Returns an Array of methods names which have the option +opt+.
  #
  #   p FileUtils.collect_method(:preserve) #=> ["cp", "cp_r", "copy", "install"]
  #
  def self.collect_method(opt)
    OPT_TABLE.keys.select {|m| OPT_TABLE[m].include?(opt) }
  end

  private

  LOW_METHODS = singleton_methods(false) - collect_method(:noop).map(&:intern) # :nodoc:
  module LowMethods # :nodoc: internal use only
    private
    def _do_nothing(*)end
    ::FileUtils::LOW_METHODS.map {|name| alias_method name, :_do_nothing}
  end

  METHODS = singleton_methods() - [:private_module_function,                  # :nodoc:
      :commands, :options, :have_option?, :options_of, :collect_method]

  #
  # This module has all methods of FileUtils module, but it outputs messages
  # before acting.  This equates to passing the <tt>:verbose</tt> flag to
  # methods in FileUtils.
  #
  module Verbose
    include FileUtils
    names = ::FileUtils.collect_method(:verbose)
    names.each do |name|
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args, **options)
          super(*args, **options, verbose: true)
        end
      EOS
    end
    private(*names)
    extend self
    class << self
      public(*::FileUtils::METHODS)
    end
  end

  #
  # This module has all methods of FileUtils module, but never changes
  # files/directories.  This equates to passing the <tt>:noop</tt> flag
  # to methods in FileUtils.
  #
  module NoWrite
    include FileUtils
    include LowMethods
    names = ::FileUtils.collect_method(:noop)
    names.each do |name|
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args, **options)
          super(*args, **options, noop: true)
        end
      EOS
    end
    private(*names)
    extend self
    class << self
      public(*::FileUtils::METHODS)
    end
  end

  #
  # This module has all methods of FileUtils module, but never changes
  # files/directories, with printing message before acting.
  # This equates to passing the <tt>:noop</tt> and <tt>:verbose</tt> flag
  # to methods in FileUtils.
  #
  module DryRun
    include FileUtils
    include LowMethods
    names = ::FileUtils.collect_method(:noop)
    names.each do |name|
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args, **options)
          super(*args, **options, noop: true, verbose: true)
        end
      EOS
    end
    private(*names)
    extend self
    class << self
      public(*::FileUtils::METHODS)
    end
  end

end
