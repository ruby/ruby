require 'rubygems/indexer'

##
# Construct a quick index file and all of the individual specs to support
# incremental loading.

class Gem::Indexer::QuickIndexBuilder < Gem::Indexer::AbstractIndexBuilder

  def initialize(filename, directory)
    directory = File.join directory, 'quick'

    super filename, directory
  end

  def cleanup
    super

    quick_index_file = File.join @directory, @filename
    compress quick_index_file

    # the complete quick index is in a directory, so move it as a whole
    @files.delete 'index'
    @files << 'quick'
  end

  def add(spec)
    @file.puts spec.original_name
    add_yaml(spec)
    add_marshal(spec)
  end

  def add_yaml(spec)
    fn = File.join @directory, "#{spec.original_name}.gemspec.rz"
    zipped = zip spec.to_yaml
    File.open fn, "wb" do |gsfile| gsfile.write zipped end
  end

  def add_marshal(spec)
    # HACK why does this not work in #initialize?
    FileUtils.mkdir_p File.join(@directory, "Marshal.#{Gem.marshal_version}")

    fn = File.join @directory, "Marshal.#{Gem.marshal_version}",
                   "#{spec.original_name}.gemspec.rz"

    zipped = zip Marshal.dump(spec)
    File.open fn, "wb" do |gsfile| gsfile.write zipped end
  end

end

