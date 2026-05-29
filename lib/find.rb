# frozen_string_literal: true
#
# find.rb: the Find module for processing all files under a given directory.
#

# :markup: markdown
#
# \Module \Find supports the top-down traversal of entries in the file system.
module Find

  # The version string
  VERSION = "0.2.0"

  # :markup: markdown
  #
  # call-seq:
  #   find(*paths, ignore_error: true) {|entry|} -> nil
  #
  # With a block given, performs a depth-first traversal of each given path in `paths`;
  # calls the block with each found path:
  #
  # ```ruby
  # paths = []
  # Find.find('bin', 'jit') {|path| paths << path }
  # paths
  # # =>
  # # ["bin",
  # #  "bin/gem",
  # #  "jit",
  # #  "jit/Cargo.toml",
  # #  "jit/src",
  # #  "jit/src/lib.rs"]
  # ```
  #
  # Raises an exception if a given path cannot be read.
  #
  # When keyword argument `ignore_error` is given as `true` (the default),
  # certain exceptions during traversal are ignored (i.e., silently rescued):
  # Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::ELOOP, Errno::ENAMETOOLONG, Errno::EINVAL;
  # when given as `false`, no exceptions are rescued.
  #
  # With no block given, returns a new Enumerator.
  def find(*paths, ignore_error: true) # :yield: path
    block_given? or return enum_for(__method__, *paths, ignore_error: ignore_error)

    fs_encoding = Encoding.find("filesystem")

    paths.collect!{|d| raise Errno::ENOENT, d unless File.exist?(d); d.dup}.each do |path|
      path = path.to_path if path.respond_to? :to_path
      enc = path.encoding == Encoding::US_ASCII ? fs_encoding : path.encoding
      ps = [path]
      while file = ps.shift
        catch(:prune) do
          yield file.dup
          begin
            s = File.lstat(file)
          rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::ELOOP, Errno::ENAMETOOLONG, Errno::EINVAL
            raise unless ignore_error
            next
          end
          if s.directory? then
            begin
              fs = Dir.children(file, encoding: enc)
            rescue Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::ELOOP, Errno::ENAMETOOLONG, Errno::EINVAL
              raise unless ignore_error
              next
            end
            fs.sort!
            fs.reverse_each {|f|
              f = File.join(file, f)
              ps.unshift f
            }
          end
        end
      end
    end
    nil
  end

  # :markup: markdown
  #
  # call-seq:
  #   Find.prune
  #
  # This method is meaningful only within a block given with Find.find.
  #
  # Inside such a block,
  # "prunes" the traversed file tree by not descending into the current directory:
  #
  # ```ruby
  # files = []
  # Find.find('.') do |path|
  #   Find.prune if File.basename(path) == 'test'
  #   next unless File.file?(path) && File.extname(path) == '.rb'
  #   files << path
  # end
  # files.size    # => 6690
  # files.take(3) # => ["./KNOWNBUGS.rb", "./array.rb", "./ast.rb"]ath
  # end
  # ```
  #
  def prune
    throw :prune
  end

  module_function :find, :prune
end
