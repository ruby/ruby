##
# The global rubygems pool represented via the traditional
# source index.

class Gem::Resolver::IndexSet < Gem::Resolver::Set

  def initialize source = nil # :nodoc:
    super()

    @f =
      if source then
        sources = Gem::SourceList.from [source]

        Gem::SpecFetcher.new sources
      else
        Gem::SpecFetcher.fetcher
      end

    @all = Hash.new { |h,k| h[k] = [] }

    list, = @f.available_specs :released

    list.each do |uri, specs|
      specs.each do |n|
        @all[n.name] << [uri, n]
      end
    end

    @specs = {}
  end

  ##
  # Return an array of IndexSpecification objects matching
  # DependencyRequest +req+.

  def find_all req
    res = []

    return res unless @remote

    name = req.dependency.name

    @all[name].each do |uri, n|
      if req.dependency.match? n then
        res << Gem::Resolver::IndexSpecification.new(
          self, n.name, n.version, uri, n.platform)
      end
    end

    res
  end

  def pretty_print q # :nodoc:
    q.group 2, '[IndexSet', ']' do
      q.breakable
      q.text 'sources:'
      q.breakable
      q.pp @f.sources

      q.breakable
      q.text 'specs:'

      q.breakable

      names = @all.values.map do |tuples|
        tuples.map do |_, tuple|
          tuple.full_name
        end
      end.flatten

      q.seplist names do |name|
        q.text name
      end
    end
  end

end

