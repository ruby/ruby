require 'rubygems/indexer'

##
# Construct the latest Gem index file.

class Gem::Indexer::LatestIndexBuilder < Gem::Indexer::AbstractIndexBuilder

  def start_index
    super

    @index = Gem::SourceIndex.new
  end

  def end_index
    super

    latest = @index.latest_specs.sort.map { |spec| spec.original_name }

    @file.write latest.join("\n")
  end

  def cleanup
    super

    compress @file.path

    @files.delete 'latest_index' # HACK installed via QuickIndexBuilder :/
  end

  def add(spec)
    @index.add_spec(spec)
  end

end

