class Gem::RequestSet::Lockfile::Parser
  ###
  # Parses lockfiles

  def initialize tokenizer, set, platforms, filename = nil
    @tokens    = tokenizer
    @filename  = filename
    @set       = set
    @platforms = platforms
  end

  def parse
    until @tokens.empty? do
      type, data, column, line = get

      case type
      when :section then
        @tokens.skip :newline

        case data
        when 'DEPENDENCIES' then
          parse_DEPENDENCIES
        when 'GIT' then
          parse_GIT
        when 'GEM' then
          parse_GEM
        when 'PATH' then
          parse_PATH
        when 'PLATFORMS' then
          parse_PLATFORMS
        else
          type, = get until @tokens.empty? or peek.first == :section
        end
      else
        raise "BUG: unhandled token #{type} (#{data.inspect}) at line #{line} column #{column}"
      end
    end
  end

  ##
  # Gets the next token for a Lockfile

  def get expected_types = nil, expected_value = nil # :nodoc:
    current_token = @tokens.shift

    type, value, column, line = current_token

    if expected_types and not Array(expected_types).include? type then
      unget current_token

      message = "unexpected token [#{type.inspect}, #{value.inspect}], " +
                "expected #{expected_types.inspect}"

      raise Gem::RequestSet::Lockfile::ParseError.new message, column, line, @filename
    end

    if expected_value and expected_value != value then
      unget current_token

      message = "unexpected token [#{type.inspect}, #{value.inspect}], " +
                "expected [#{expected_types.inspect}, " +
                "#{expected_value.inspect}]"

      raise Gem::RequestSet::Lockfile::ParseError.new message, column, line, @filename
    end

    current_token
  end

  def parse_DEPENDENCIES # :nodoc:
    while not @tokens.empty? and :text == peek.first do
      _, name, = get :text

      requirements = []

      case peek[0]
      when :bang then
        get :bang

        requirements << pinned_requirement(name)
      when :l_paren then
        get :l_paren

        loop do
          _, op,      = get :requirement
          _, version, = get :text

          requirements << "#{op} #{version}"

          break unless peek[0] == :comma

          get :comma
        end

        get :r_paren

        if peek[0] == :bang then
          requirements.clear
          requirements << pinned_requirement(name)

          get :bang
        end
      end

      @set.gem name, *requirements

      skip :newline
    end
  end

  def parse_GEM # :nodoc:
    sources = []

    while [:entry, 'remote'] == peek.first(2) do
      get :entry, 'remote'
      _, data, = get :text
      skip :newline

      sources << Gem::Source.new(data)
    end

    sources << Gem::Source.new(Gem::DEFAULT_HOST) if sources.empty?

    get :entry, 'specs'

    skip :newline

    set = Gem::Resolver::LockSet.new sources
    last_specs = nil

    while not @tokens.empty? and :text == peek.first do
      _, name, column, = get :text

      case peek[0]
      when :newline then
        last_specs.each do |spec|
          spec.add_dependency Gem::Dependency.new name if column == 6
        end
      when :l_paren then
        get :l_paren

        type, data, = get [:text, :requirement]

        if type == :text and column == 4 then
          version, platform = data.split '-', 2

          platform =
            platform ? Gem::Platform.new(platform) : Gem::Platform::RUBY

          last_specs = set.add name, version, platform
        else
          dependency = parse_dependency name, data

          last_specs.each do |spec|
            spec.add_dependency dependency
          end
        end

        get :r_paren
      else
        raise "BUG: unknown token #{peek}"
      end

      skip :newline
    end

    @set.sets << set
  end

  def parse_GIT # :nodoc:
    get :entry, 'remote'
    _, repository, = get :text

    skip :newline

    get :entry, 'revision'
    _, revision, = get :text

    skip :newline

    type, value = peek.first 2
    if type == :entry and %w[branch ref tag].include? value then
      get
      get :text

      skip :newline
    end

    get :entry, 'specs'

    skip :newline

    set = Gem::Resolver::GitSet.new
    set.root_dir = @set.install_dir

    last_spec = nil

    while not @tokens.empty? and :text == peek.first do
      _, name, column, = get :text

      case peek[0]
      when :newline then
        last_spec.add_dependency Gem::Dependency.new name if column == 6
      when :l_paren then
        get :l_paren

        type, data, = get [:text, :requirement]

        if type == :text and column == 4 then
          last_spec = set.add_git_spec name, data, repository, revision, true
        else
          dependency = parse_dependency name, data

          last_spec.add_dependency dependency
        end

        get :r_paren
      else
        raise "BUG: unknown token #{peek}"
      end

      skip :newline
    end

    @set.sets << set
  end

  def parse_PATH # :nodoc:
    get :entry, 'remote'
    _, directory, = get :text

    skip :newline

    get :entry, 'specs'

    skip :newline

    set = Gem::Resolver::VendorSet.new
    last_spec = nil

    while not @tokens.empty? and :text == peek.first do
      _, name, column, = get :text

      case peek[0]
      when :newline then
        last_spec.add_dependency Gem::Dependency.new name if column == 6
      when :l_paren then
        get :l_paren

        type, data, = get [:text, :requirement]

        if type == :text and column == 4 then
          last_spec = set.add_vendor_gem name, directory
        else
          dependency = parse_dependency name, data

          last_spec.dependencies << dependency
        end

        get :r_paren
      else
        raise "BUG: unknown token #{peek}"
      end

      skip :newline
    end

    @set.sets << set
  end

  def parse_PLATFORMS # :nodoc:
    while not @tokens.empty? and :text == peek.first do
      _, name, = get :text

      @platforms << name

      skip :newline
    end
  end

  ##
  # Parses the requirements following the dependency +name+ and the +op+ for
  # the first token of the requirements and returns a Gem::Dependency object.

  def parse_dependency name, op # :nodoc:
    return Gem::Dependency.new name, op unless peek[0] == :text

    _, version, = get :text

    requirements = ["#{op} #{version}"]

    while peek[0] == :comma do
      get :comma
      _, op,      = get :requirement
      _, version, = get :text

      requirements << "#{op} #{version}"
    end

    Gem::Dependency.new name, requirements
  end

  private

  def skip type # :nodoc:
    @tokens.skip type
  end

  ##
  # Peeks at the next token for Lockfile

  def peek # :nodoc:
    @tokens.peek
  end

  def pinned_requirement name # :nodoc:
    spec = @set.sets.select { |set|
      Gem::Resolver::GitSet    === set or
        Gem::Resolver::VendorSet === set
    }.map { |set|
      set.specs[name]
    }.compact.first

    spec.version
  end

  ##
  # Ungets the last token retrieved by #get

  def unget token # :nodoc:
    @tokens.unshift token
  end
end

