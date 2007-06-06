require 'json/version'

module JSON
  class << self
    # If object is string like parse the string and return the parsed result as a
    # Ruby data structure. Otherwise generate a JSON text from the Ruby data
    # structure object and return it.
    def [](object)
      if object.respond_to? :to_str
        JSON.parse(object.to_str)
      else
        JSON.generate(object)
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
      path = path.to_s
      path.split(/::/).inject(Object) do |p, c|
        case
        when c.empty?             then p
        when p.const_defined?(c)  then p.const_get(c)
        else                      raise ArgumentError, "can't find const #{path}"
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

  # The base exception for JSON errors.
  class JSONError < StandardError; end

  # This exception is raised, if a parser error occurs.
  class ParserError < JSONError; end

  # This exception is raised, if the nesting of parsed datastructures is too
  # deep.
  class NestingError < ParserError; end

  # This exception is raised, if a generator or unparser error occurs.
  class GeneratorError < JSONError; end
  # For backwards compatibility
  UnparserError = GeneratorError

  # If a circular data structure is encountered while unparsing
  # this exception is raised.
  class CircularDatastructure < GeneratorError; end

  # This exception is raised, if the required unicode support is missing on the
  # system. Usually this means, that the iconv library is not installed.
  class MissingUnicodeSupport < JSONError; end

  module_function

  # Parse the JSON string _source_ into a Ruby data structure and return it.
  #
  # _opts_ can have the following
  # keys:
  # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
  #   structures. Disable depth checking with :max_nesting => false. This value
  #   defaults to 19.
  def parse(source, opts = {})
    JSON.parser.new(source, opts).parse
  end

  # Parse the JSON string _source_ into a Ruby data structure and return it.
  #
  # _opts_ can have the following
  # keys:
  # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
  #   structures. Enable depth checking with :max_nesting => anInteger. The parse!
  #   methods defaults to not doing max depth checking: This can be dangerous,
  #   if someone wants to fill up your stack.
  def parse!(source, opts = {})
    opts = {
      :max_nesting => false
    }.update(opts)
    JSON.parser.new(source, opts).parse
  end

  # Unparse the Ruby data structure _obj_ into a single line JSON string and
  # return it. _state_ is a JSON::State object, that can be used to configure
  # the output further.
  #
  # It defaults to a state object, that creates the shortest possible JSON text
  # in one line and only checks for circular data structures. If you are sure,
  # that the objects don't contain any circles, you can set _state_ to nil, to
  # disable these checks in order to create the JSON text faster. See also
  # fast_generate.
  def generate(obj, state = JSON.state.new)
    obj.to_json(state)
  end

  alias unparse generate
  module_function :unparse

  # Unparse the Ruby data structure _obj_ into a single line JSON string and
  # return it. This method disables the checks for circles in Ruby objects.
  #
  # *WARNING*: Be careful not to pass any Ruby data structures with circles as
  # _obj_ argument, because this will cause JSON to go into an infinite loop.
  def fast_generate(obj)
    obj.to_json(nil)
  end

  alias fast_unparse fast_generate
  module_function :fast_unparse

  # Unparse the Ruby data structure _obj_ into a JSON string and return it. The
  # returned string is a prettier form of the string returned by #unparse.
  def pretty_generate(obj)
    state = JSON.state.new(
      :indent     => '  ',
      :space      => ' ',
      :object_nl  => "\n",
      :array_nl   => "\n",
      :check_circular => true
    )
    obj.to_json(state)
  end

  alias pretty_unparse pretty_generate
  module_function :pretty_unparse
end

module ::Kernel
  # Outputs _objs_ to STDOUT as JSON strings in the shortest form, that is in
  # one line.
  def j(*objs)
    objs.each do |obj|
      puts JSON::generate(obj)
    end
    nil
  end

  # Ouputs _objs_ to STDOUT as JSON strings in a pretty format, with
  # indentation and over many lines.
  def jj(*objs)
    objs.each do |obj|
      puts JSON::pretty_generate(obj)
    end
    nil
  end

  # If object is string like parse the string and return the parsed result as a
  # Ruby data structure. Otherwise generate a JSON text from the Ruby data
  # structure object and return it.
  def JSON(object)
    if object.respond_to? :to_str
      JSON.parse(object.to_str)
    else
      JSON.generate(object)
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
  # vim: set et sw=2 ts=2:
