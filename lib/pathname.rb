# frozen_string_literal: true
#
class Pathname

  # :markup: markdown
  #
  # call-seq:
  #   Pathname.find(ignore_error: true) -> nil
  #
  # With a block given, performs a depth-first traversal of the path in `self`;
  # calls the block with each found path:
  #
  # ```ruby
  # paths = []
  # Pathname('lib').find {|path| paths << path }
  # paths.size  # => 909
  # paths.take(3)
  # # =>
  # # [#<Pathname:lib>,
  # #  #<Pathname:lib/English.gemspec>,
  # #  #<Pathname:lib/English.rb>]
  # ```
  #
  # When `self` contains `'.'`, the found paths omit the leading `'./'`:
  #
  # ```ruby
  # paths = []
  # Dir.chdir('lib') do
  #   Pathname('.').find {|path| paths << path }
  # end
  # paths.take(3)
  # # # =>
  # # [#<Pathname:.>,
  # #  #<Pathname:English.gemspec>,
  # #  #<Pathname:English.rb>]
  # ```
  #
  # This method calls method Find.find;
  # therefore method Find.prune may be used in the block:
  #
  # ```ruby
  # files = []
  # Pathname('.').find do |path|
  #   Find.prune if File.basename(path) == 'test'
  #   next unless File.file?(path) && File.extname(path) == '.rb'
  #   files << path
  # end
  # files.size # => 6690
  # files.take(3)
  # # # =>
  # # [#<Pathname:KNOWNBUGS.rb>,
  # #  #<Pathname:array.rb>,
  # #  #<Pathname:ast.rb>]
  # ```
  #
  # Raises an exception if the path in `self` cannot be read.
  #
  # When keyword argument `ignore_error` is given as `true` (the default),
  # certain exceptions during traversal are ignored (i.e., silently rescued):
  # Errno::ENOENT, Errno::EACCES, Errno::ENOTDIR, Errno::ELOOP, Errno::ENAMETOOLONG, Errno::EINVAL;
  # when given as `false`, no exceptions are rescued.
  #
  # Note that these exceptions may be ignored only in `Pathname#find` traversal code;
  # an exception raised before traversal begins,
  # or raised while in the block is not ignored.
  # Each of the calls below raises an Errno::ENOENT exception that is not ignored:
  #
  # ```ruby
  # Pathname('nosuch').find { }
  # Pathname('lib').find {|entry| raise Errno::ENOENT }
  # ```
  #
  # With no block given, returns a new Enumerator.
  def find(ignore_error: true) # :yield: pathname
    return to_enum(__method__, ignore_error: ignore_error) unless block_given?
    require 'find'
    if @path == '.'
      Find.find(@path, ignore_error: ignore_error) {|f| yield self.class.new(f.delete_prefix('./')) }
    else
      Find.find(@path, ignore_error: ignore_error) {|f| yield self.class.new(f) }
    end
  end
end


