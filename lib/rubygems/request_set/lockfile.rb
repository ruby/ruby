require 'pathname'

class Gem::RequestSet::Lockfile

  ##
  # Raised when a lockfile cannot be parsed

  class ParseError < Gem::Exception

    ##
    # The column where the error was encountered

    attr_reader :column

    ##
    # The line where the error was encountered

    attr_reader :line

    ##
    # The location of the lock file

    attr_reader :path

    ##
    # Raises a ParseError with the given +message+ which was encountered at a
    # +line+ and +column+ while parsing.

    def initialize message, line, column, path
      @line   = line
      @column = column
      @path   = path
      super "#{message} (at #{line}:#{column})"
    end

  end

  ##
  # The platforms for this Lockfile

  attr_reader :platforms

  ##
  # Creates a new Lockfile for the given +request_set+ and +gem_deps_file+
  # location.

  def initialize request_set, gem_deps_file
    @set           = request_set
    @gem_deps_file = Pathname(gem_deps_file).expand_path
    @gem_deps_dir  = @gem_deps_file.dirname

    @current_token  = nil
    @line           = 0
    @line_pos       = 0
    @platforms      = []
    @tokens         = []
  end

  def add_DEPENDENCIES out # :nodoc:
    out << "DEPENDENCIES"

    @set.dependencies.sort.map do |dependency|
      source = @requests.find do |req|
        req.name == dependency.name and
          req.spec.class == Gem::DependencyResolver::VendorSpecification
      end

      source_dep = '!' if source

      requirement = dependency.requirement

      out << "  #{dependency.name}#{source_dep}#{requirement.for_lockfile}"
    end

    out << nil
  end

  def add_GEM out # :nodoc:
    out << "GEM"

    source_groups = @spec_groups.values.flatten.group_by do |request|
      request.spec.source.uri
    end

    source_groups.map do |group, requests|
      out << "  remote: #{group}"
      out << "  specs:"

      requests.sort_by { |request| request.name }.each do |request|
        platform = "-#{request.spec.platform}" unless
          Gem::Platform::RUBY == request.spec.platform

        out << "    #{request.name} (#{request.version}#{platform})"

        request.full_spec.dependencies.sort.each do |dependency|
          requirement = dependency.requirement
          out << "      #{dependency.name}#{requirement.for_lockfile}"
        end
      end
    end

    out << nil
  end

  def add_PATH out # :nodoc:
    return unless path_requests =
      @spec_groups.delete(Gem::DependencyResolver::VendorSpecification)

    out << "PATH"
    path_requests.each do |request|
      directory = Pathname(request.spec.source.uri).expand_path

      out << "  remote: #{directory.relative_path_from @gem_deps_dir}"
      out << "  specs:"
      out << "    #{request.name} (#{request.version})"
    end

    out << nil
  end

  def add_PLATFORMS out # :nodoc:
    out << "PLATFORMS"

    platforms = @requests.map { |request| request.spec.platform }.uniq
    platforms.delete Gem::Platform::RUBY if platforms.length > 1

    platforms.each do |platform|
      out << "  #{platform}"
    end

    out << nil
  end

  ##
  # Gets the next token for a Lockfile

  def get expected_type = nil, expected_value = nil # :nodoc:
    @current_token = @tokens.shift

    type, value, line, column = @current_token

    if expected_type and expected_type != type then
      unget

      message = "unexpected token [#{type.inspect}, #{value.inspect}], " +
                "expected #{expected_type.inspect}"

      raise ParseError.new message, line, column, "#{@gem_deps_file}.lock"
    end

    if expected_value and expected_value != value then
      unget

      message = "unexpected token [#{type.inspect}, #{value.inspect}], " +
                "expected [#{expected_type.inspect}, #{expected_value.inspect}]"

      raise ParseError.new message, line, column, "#{@gem_deps_file}.lock"
    end

    @current_token
  end

  def parse # :nodoc:
    tokenize

    until @tokens.empty? do
      type, data, column, line = get

      case type
      when :section then
        skip :newline

        case data
        when 'DEPENDENCIES' then
          parse_DEPENDENCIES
        when 'GEM' then
          parse_GEM
        when 'PLATFORMS' then
          parse_PLATFORMS
        else
          type, = get until @tokens.empty? or peek.first == :section
        end
      else
        raise "BUG: unhandled token #{type} (#{data.inspect}) at #{line}:#{column}"
      end
    end
  end

  def parse_DEPENDENCIES # :nodoc:
    while not @tokens.empty? and :text == peek.first do
      _, name, = get :text

      @set.gem name

      skip :newline
    end
  end

  def parse_GEM # :nodoc:
    get :entry, 'remote'
    _, data, = get :text

    source = Gem::Source.new data

    skip :newline

    get :entry, 'specs'

    skip :newline

    set = Gem::DependencyResolver::LockSet.new source

    while not @tokens.empty? and :text == peek.first do
      _, name, = get :text

      case peek[0]
      when :newline then # ignore
      when :l_paren then
        get :l_paren

        _, version, = get :text

        get :r_paren

        set.add name, version, Gem::Platform::RUBY
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
  # Peeks at the next token for Lockfile

  def peek # :nodoc:
    @tokens.first
  end

  def skip type # :nodoc:
    get while not @tokens.empty? and peek.first == type
  end

  def to_s
    @set.resolve

    out = []

    @requests = @set.sorted_requests

    @spec_groups = @requests.group_by do |request|
      request.spec.class
    end

    add_PATH out

    add_GEM out

    add_PLATFORMS out

    add_DEPENDENCIES out

    out.join "\n"
  end

  ##
  # Calculates the column (by byte) and the line of the current token based on
  # +byte_offset+.

  def token_pos byte_offset # :nodoc:
    [byte_offset - @line_pos, @line]
  end

  def tokenize # :nodoc:
    @line     = 0
    @line_pos = 0

    @platforms     = []
    @tokens        = []
    @current_token = nil

    lock_file = "#{@gem_deps_file}.lock"

    @input = File.read lock_file
    s      = StringScanner.new @input

    until s.eos? do
      pos = s.pos

      # leading whitespace is for the user's convenience
      next if s.scan(/ +/)

      if s.scan(/[<|=>]{7}/) then
        message = "your #{lock_file} contains merge conflict markers"
        line, column = token_pos pos

        raise ParseError.new message, line, column, lock_file
      end

      @tokens <<
        case
        when s.scan(/\r?\n/) then
          token = [:newline, nil, *token_pos(pos)]
          @line_pos = s.pos
          @line += 1
          token
        when s.scan(/[A-Z]+/) then
          [:section, s.matched, *token_pos(pos)]
        when s.scan(/([a-z]+):\s/) then
          s.pos -= 1 # rewind for possible newline
          [:entry, s[1], *token_pos(pos)]
        when s.scan(/\(/) then
          [:l_paren, nil, *token_pos(pos)]
        when s.scan(/\)/) then
          [:r_paren, nil, *token_pos(pos)]
        when s.scan(/[^\s)]*/) then
          [:text, s.matched, *token_pos(pos)]
        else
          raise "BUG: can't create token for: #{s.string[s.pos..-1].inspect}"
        end
    end

    @tokens
  end

  ##
  # Ungets the last token retrieved by #get

  def unget # :nodoc:
    @tokens.unshift @current_token
  end

end

