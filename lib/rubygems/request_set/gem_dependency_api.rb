##
# A semi-compatible DSL for the Bundler Gemfile and Isolate formats.

class Gem::RequestSet::GemDependencyAPI

  ##
  # The dependency groups created by #group in the dependency API file.

  attr_reader :dependency_groups

  ##
  # Creates a new GemDependencyAPI that will add dependencies to the
  # Gem::RequestSet +set+ based on the dependency API description in +path+.

  def initialize set, path
    @set = set
    @path = path

    @current_groups    = nil
    @dependency_groups = Hash.new { |h, group| h[group] = [] }
  end

  ##
  # Loads the gem dependency file

  def load
    instance_eval File.read(@path).untaint, @path, 1
  end

  ##
  # :category: Gem Dependencies DSL
  # :call-seq:
  #   gem(name)
  #   gem(name, *requirements)
  #   gem(name, *requirements, options)
  #
  # Specifies a gem dependency with the given +name+ and +requirements+.  You
  # may also supply +options+ following the +requirements+

  def gem name, *requirements
    options = requirements.pop if requirements.last.kind_of?(Hash)
    options ||= {}

    groups =
      (group = options.delete(:group) and Array(group)) ||
      options.delete(:groups) ||
      @current_groups

    if groups then
      groups.each do |group|
        gem_arguments = [name, *requirements]
        gem_arguments << options unless options.empty?
        @dependency_groups[group] << gem_arguments
      end

      return
    end

    @set.gem name, *requirements
  end

  ##
  # Returns the basename of the file the dependencies were loaded from

  def gem_deps_file # :nodoc:
    File.basename @path
  end

  ##
  # :category: Gem Dependencies DSL
  # Block form for placing a dependency in the given +groups+.

  def group *groups
    @current_groups = groups

    yield

  ensure
    @current_groups = nil
  end

  ##
  # :category: Gem Dependencies DSL

  def platform what
    if what == :ruby
      yield
    end
  end

  ##
  # :category: Gem Dependencies DSL

  alias :platforms :platform

  ##
  # :category: Gem Dependencies DSL
  # Restricts this gem dependencies file to the given ruby +version+.  The
  # +:engine+ options from Bundler are currently ignored.

  def ruby version, options = {}
    return true if version == RUBY_VERSION

    message = "Your Ruby version is #{RUBY_VERSION}, " +
              "but your #{gem_deps_file} specified #{version}"

    raise Gem::RubyVersionMismatch, message
  end

  ##
  # :category: Gem Dependencies DSL

  def source url
  end

  # TODO: remove this typo name at RubyGems 3.0

  Gem::RequestSet::DepedencyAPI = self # :nodoc:

end

