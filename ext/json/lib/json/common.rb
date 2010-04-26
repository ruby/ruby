require 'json/version'
require 'iconv'

module JSON
  class << self
    # If _object_ is string-like parse the string and return the parsed result
    # as a Ruby data structure. Otherwise generate a JSON text from the Ruby
    # data structure object and return it.
    #
    # The _opts_ argument is passed through to generate/parse respectively, see
    # generate and parse for their documentation.
    def [](object, opts = {})
      if object.respond_to? :to_str
        JSON.parse(object.to_str, opts => {})
      else
        JSON.generate(object, opts => {})
      end
    end

    # Returns the JSON parser class, that is used by JSON. This might be either
    # JSON::Ext::Parser or JSON::Pure::Parser.
    attr_reader :parser

    # Set the JSON parser class _parser_ to be used by JSON.
    def parser=(parser) # :nodoc:
      @parser = parser
      remove_const :Parser if const_defined? :Parser
      const_set :Parser, parser
    end

    # Return the constant located at _path_. The format of _path_ has to be
    # either ::A::B::C or A::B::C. In any case A has to be located at the top
    # level (absolute namespace path?). If there doesn't exist a constant at
    # the given path, an ArgumentError is raised.
    def deep_const_get(path) # :nodoc:
      path.to_s.split(/::/).inject(Object) do |p, c|
        case
        when c.empty?             then p
        when p.const_defined?(c)  then p.const_get(c)
        else
          begin
            p.const_missing(c)
          rescue NameError
            raise ArgumentError, "can't find const #{path}"
          end
        end
      end
    end

    # Set the module _generator_ to be used by JSON.
    def generator=(generator) # :nodoc:
      @generator = generator
      generator_methods = generator::GeneratorMethods
      for const in generator_methods.constants
        klass = deep_const_get(const)
        modul = generator_methods.const_get(const)
        klass.class_eval do
          instance_methods(false).each do |m|
            m.to_s == 'to_json' and remove_method m
          end
          include modul
        end
      end
      self.state = generator::State
      const_set :State, self.state
      const_set :SAFE_STATE_PROTOTYPE, State.new.freeze
      const_set :FAST_STATE_PROTOTYPE, State.new(
        :indent         => '',
        :space          => '',
        :object_nl      => "",
        :array_nl       => "",
        :max_nesting    => false
      ).freeze
      const_set :PRETTY_STATE_PROTOTYPE, State.new(
        :indent         => '  ',
        :space          => ' ',
        :object_nl      => "\n",
        :array_nl       => "\n"
      ).freeze
    end

    # Returns the JSON generator modul, that is used by JSON. This might be
    # either JSON::Ext::Generator or JSON::Pure::Generator.
    attr_reader :generator

    # Returns the JSON generator state class, that is used by JSON. This might
    # be either JSON::Ext::Generator::State or JSON::Pure::Generator::State.
    attr_accessor :state

    # This is create identifier, that is used to decide, if the _json_create_
    # hook of a class should be called. It defaults to 'json_class'.
    attr_accessor :create_id
  end
  self.create_id = 'json_class'

  NaN           = 0.0/0

  Infinity      = 1.0/0

  MinusInfinity = -Infinity

  # The base exception for JSON errors.
  class JSONError < StandardError; end

  # This exception is raised, if a parser error occurs.
  class ParserError < JSONError; end

  # This exception is raised, if the nesting of parsed datastructures is too
  # deep.
  class NestingError < ParserError; end

  # :stopdoc:
  class CircularDatastructure < NestingError; end
  # :startdoc:

  # This exception is raised, if a generator or unparser error occurs.
  class GeneratorError < JSONError; end
  # For backwards compatibility
  UnparserError = GeneratorError

  # This exception is raised, if the required unicode support is missing on the
  # system. Usually this means, that the iconv library is not installed.
  class MissingUnicodeSupport < JSONError; end

  module_function

  # Parse the JSON document _source_ into a Ruby data structure and return it.
  #
  # _opts_ can have the following
  # keys:
  # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
  #   structures. Disable depth checking with :max_nesting => false, it defaults
  #   to 19.
  # * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
  #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
  #   to false.
  # * *symbolize_names*: If set to true, returns symbols for the names
  #   (keys) in a JSON object. Otherwise strings are returned, which is also
  #   the default.
  # * *create_additions*: If set to false, the Parser doesn't create
  #   additions even if a matchin class and create_id was found. This option
  #   defaults to true.
  # * *object_class*: Defaults to Hash
  # * *array_class*: Defaults to Array
  def parse(source, opts = {})
    Parser.new(source, opts).parse
  end

  # Parse the JSON document _source_ into a Ruby data structure and return it.
  # The bang version of the parse method, defaults to the more dangerous values
  # for the _opts_ hash, so be sure only to parse trusted _source_ documents.
  #
  # _opts_ can have the following keys:
  # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
  #   structures. Enable depth checking with :max_nesting => anInteger. The parse!
  #   methods defaults to not doing max depth checking: This can be dangerous,
  #   if someone wants to fill up your stack.
  # * *allow_nan*: If set to true, allow NaN, Infinity, and -Infinity in
  #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
  #   to true.
  # * *create_additions*: If set to false, the Parser doesn't create
  #   additions even if a matchin class and create_id was found. This option
  #   defaults to true.
  def parse!(source, opts = {})
    opts = {
      :max_nesting  => false,
      :allow_nan    => true
    }.update(opts)
    Parser.new(source, opts).parse
  end

  # Generate a JSON document from the Ruby data structure _obj_ and return
  # it. _state_ is * a JSON::State object,
  # * or a Hash like object (responding to to_hash),
  # * an object convertible into a hash by a to_h method,
  # that is used as or to configure a State object.
  #
  # It defaults to a state object, that creates the shortest possible JSON text
  # in one line, checks for circular data structures and doesn't allow NaN,
  # Infinity, and -Infinity.
  #
  # A _state_ hash can have the following keys:
  # * *indent*: a string used to indent levels (default: ''),
  # * *space*: a string that is put after, a : or , delimiter (default: ''),
  # * *space_before*: a string that is put before a : pair delimiter (default: ''),
  # * *object_nl*: a string that is put at the end of a JSON object (default: ''), 
  # * *array_nl*: a string that is put at the end of a JSON array (default: ''),
  # * *allow_nan*: true if NaN, Infinity, and -Infinity should be
  #   generated, otherwise an exception is thrown, if these values are
  #   encountered. This options defaults to false.
  # * *max_nesting*: The maximum depth of nesting allowed in the data
  #   structures from which JSON is to be generated. Disable depth checking
  #   with :max_nesting => false, it defaults to 19.
  #
  # See also the fast_generate for the fastest creation method with the least
  # amount of sanity checks, and the pretty_generate method for some
  # defaults for a pretty output.
  def generate(obj, opts = nil)
    if opts
      if opts.respond_to? :to_hash
        opts = opts.to_hash
      elsif opts.respond_to? :to_h
        opts = opts.to_h
      else
        raise TypeError, "can't convert #{opts.class} into Hash"
      end
      state = SAFE_STATE_PROTOTYPE.dup
      state = state.configure(opts)
    else
      state = SAFE_STATE_PROTOTYPE
    end
    state.generate(obj)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and
  # later delete them.
  alias unparse generate
  module_function :unparse
  # :startdoc:

  # Generate a JSON document from the Ruby data structure _obj_ and return it.
  # This method disables the checks for circles in Ruby objects.
  #
  # *WARNING*: Be careful not to pass any Ruby data structures with circles as
  # _obj_ argument, because this will cause JSON to go into an infinite loop.
  def fast_generate(obj, opts = nil)
    if opts
      if opts.respond_to? :to_hash
        opts = opts.to_hash
      elsif opts.respond_to? :to_h
        opts = opts.to_h
      else
        raise TypeError, "can't convert #{opts.class} into Hash"
      end
      state = FAST_STATE_PROTOTYPE.dup
      state.configure(opts)
    else
      state = FAST_STATE_PROTOTYPE
    end
    state.generate(obj)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and later delete them.
  alias fast_unparse fast_generate
  module_function :fast_unparse
  # :startdoc:

  # Generate a JSON document from the Ruby data structure _obj_ and return it.
  # The returned document is a prettier form of the document returned by
  # #unparse.
  #
  # The _opts_ argument can be used to configure the generator, see the
  # generate method for a more detailed explanation.
  def pretty_generate(obj, opts = nil)
    if opts
      if opts.respond_to? :to_hash
        opts = opts.to_hash
      elsif opts.respond_to? :to_h
        opts = opts.to_h
      else
        raise TypeError, "can't convert #{opts.class} into Hash"
      end
      state = PRETTY_STATE_PROTOTYPE.dup
      state.configure(opts)
    else
      state = PRETTY_STATE_PROTOTYPE
    end
    state.generate(obj)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and later delete them.
  alias pretty_unparse pretty_generate
  module_function :pretty_unparse
  # :startdoc:

  # Load a ruby data structure from a JSON _source_ and return it. A source can
  # either be a string-like object, an IO like object, or an object responding
  # to the read method. If _proc_ was given, it will be called with any nested
  # Ruby object as an argument recursively in depth first order.
  #
  # This method is part of the implementation of the load/dump interface of
  # Marshal and YAML.
  def load(source, proc = nil)
    if source.respond_to? :to_str
      source = source.to_str
    elsif source.respond_to? :to_io
      source = source.to_io.read
    else
      source = source.read
    end
    result = parse(source, :max_nesting => false, :allow_nan => true)
    recurse_proc(result, &proc) if proc
    result
  end

  def recurse_proc(result, &proc)
    case result
    when Array
      result.each { |x| recurse_proc x, &proc }
      proc.call result
    when Hash
      result.each { |x, y| recurse_proc x, &proc; recurse_proc y, &proc }
      proc.call result
    else
      proc.call result
    end
  end

  alias restore load
  module_function :restore

  # Dumps _obj_ as a JSON string, i.e. calls generate on the object and returns
  # the result.
  #
  # If anIO (an IO like object or an object that responds to the write method)
  # was given, the resulting JSON is written to it.
  #
  # If the number of nested arrays or objects exceeds _limit_ an ArgumentError
  # exception is raised. This argument is similar (but not exactly the
  # same!) to the _limit_ argument in Marshal.dump.
  #
  # This method is part of the implementation of the load/dump interface of
  # Marshal and YAML.
  def dump(obj, anIO = nil, limit = nil)
    if anIO and limit.nil?
      anIO = anIO.to_io if anIO.respond_to?(:to_io)
      unless anIO.respond_to?(:write)
        limit = anIO
        anIO = nil
      end
    end
    limit ||= 0
    result = generate(obj, :allow_nan => true, :max_nesting => limit)
    if anIO
      anIO.write result
      anIO
    else
      result
    end
  rescue JSON::NestingError
    raise ArgumentError, "exceed depth limit"
  end

  # Shortuct for iconv.
  def self.iconv(to, from, string)
    Iconv.iconv(to, from, string).first
  end
end

module ::Kernel
  private

  # Outputs _objs_ to STDOUT as JSON strings in the shortest form, that is in
  # one line.
  def j(*objs)
    objs.each do |obj|
      puts JSON::generate(obj, :allow_nan => true, :max_nesting => false)
    end
    nil
  end

  # Ouputs _objs_ to STDOUT as JSON strings in a pretty format, with
  # indentation and over many lines.
  def jj(*objs)
    objs.each do |obj|
      puts JSON::pretty_generate(obj, :allow_nan => true, :max_nesting => false)
    end
    nil
  end

  # If _object_ is string-like parse the string and return the parsed result as
  # a Ruby data structure. Otherwise generate a JSON text from the Ruby data
  # structure object and return it.
  #
  # The _opts_ argument is passed through to generate/parse respectively, see
  # generate and parse for their documentation.
  def JSON(object, opts = {})
    if object.respond_to? :to_str
      JSON.parse(object.to_str, opts)
    else
      JSON.generate(object, opts)
    end
  end
end

class ::Class
  # Returns true, if this class can be used to create an instance
  # from a serialised JSON string. The class has to implement a class
  # method _json_create_ that expects a hash as first parameter, which includes
  # the required data.
  def json_creatable?
    respond_to?(:json_create)
  end
end
