require 'zlib'

require 'rubygems/indexer'

# Abstract base class for building gem indicies.  Uses the template pattern
# with subclass specialization in the +begin_index+, +end_index+ and +cleanup+
# methods.
class Gem::Indexer::AbstractIndexBuilder

  # Directory to put index files in
  attr_reader :directory

  # File name of the generated index
  attr_reader :filename

  # List of written files/directories to move into production
  attr_reader :files

  def initialize(filename, directory)
    @filename = filename
    @directory = directory
    @files = []
  end

  ##
  # Build a Gem index.  Yields to block to handle the details of the
  # actual building.  Calls +begin_index+, +end_index+ and +cleanup+ at
  # appropriate times to customize basic operations.

  def build
    FileUtils.mkdir_p @directory unless File.exist? @directory
    raise "not a directory: #{@directory}" unless File.directory? @directory

    file_path = File.join @directory, @filename

    @files << @filename

    File.open file_path, "wb" do |file|
      @file = file
      start_index
      yield
      end_index
    end

    cleanup
  ensure
    @file = nil
  end

  ##
  # Compress the given file.

  def compress(filename, ext="rz")
    data = open filename, 'rb' do |fp| fp.read end

    zipped = zip data

    File.open "#{filename}.#{ext}", "wb" do |file|
      file.write zipped
    end
  end

  # Called immediately before the yield in build.  The index file is open and
  # available as @file.
  def start_index
  end

  # Called immediately after the yield in build.  The index file is still open
  # and available as @file.
  def end_index
  end

  # Called from within builder after the index file has been closed.
  def cleanup
  end

  # Return an uncompressed version of a compressed string.
  def unzip(string)
    Zlib::Inflate.inflate(string)
  end

  # Return a compressed version of the given string.
  def zip(string)
    Zlib::Deflate.deflate(string)
  end

end

