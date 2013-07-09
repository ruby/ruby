##
# A semi-compatible DSL for Bundler's Gemfile format

class Gem::RequestSet::GemDepedencyAPI

  def initialize set, path
    @set = set
    @path = path
  end

  def load
    instance_eval File.read(@path).untaint, @path, 1
  end

  # :category: Bundler Gemfile DSL

  def gem name, *reqs
    # Ignore the opts for now.
    reqs.pop if reqs.last.kind_of?(Hash)

    @set.gem name, *reqs
  end

  def group *what
  end

  def platform what
    if what == :ruby
      yield
    end
  end

  alias :platforms :platform

  def source url
  end

end

