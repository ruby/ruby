require 'rubygems/indexer'

##
# Construct the master Gem index file.

class Gem::Indexer::MasterIndexBuilder < Gem::Indexer::AbstractIndexBuilder

  def start_index
    super
    @index = Gem::SourceIndex.new
  end

  def end_index
    super

    @file.puts "--- !ruby/object:#{@index.class}"
    @file.puts "gems:"

    gems = @index.sort_by { |name, gemspec| gemspec.sort_obj }
    gems.each do |name, gemspec|
      yaml = gemspec.to_yaml.gsub(/^/, '    ')
      yaml = yaml.sub(/\A    ---/, '') # there's a needed extra ' ' here
      @file.print "  #{gemspec.original_name}:"
      @file.puts yaml
    end
  end

  def cleanup
    super

    index_file_name = File.join @directory, @filename

    compress index_file_name, "Z"
    paranoid index_file_name, "#{index_file_name}.Z"

    @files << "#{@filename}.Z"
  end

  def add(spec)
    @index.add_spec(spec)
  end

  private

  def paranoid(path, compressed_path)
    data = Gem.read_binary path
    compressed_data = Gem.read_binary compressed_path

    if data != unzip(compressed_data) then
      raise "Compressed file #{compressed_path} does not match uncompressed file #{path}"
    end
  end

end
