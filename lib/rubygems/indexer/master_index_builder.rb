require 'rubygems/indexer'

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
    compressed_file_name = "#{index_file_name}.Z"

    paranoid index_file_name, compressed_file_name

    @files << compressed_file_name
  end

  def add(spec)
    @index.add_spec(spec)
  end

  private

  def paranoid(fn, compressed_fn)
    data = File.open(fn, 'rb') do |fp| fp.read end
    compressed_data = File.open(compressed_fn, 'rb') do |fp| fp.read end

    if data != unzip(compressed_data) then
      fail "Compressed file #{compressed_fn} does not match uncompressed file #{fn}"
    end
  end

end
