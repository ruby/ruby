#frozen_string_literal: false
require 'json/version'
require 'json/generic_object'

module JSON
  class << self
    # If +object+ is a
    # {String-convertible object}[doc/implicit_conversion_rdoc.html#label-String-Convertible+Objects]
    # (implementing +to_str+), calls JSON.parse with +object+ and +opts+:
    #   json = '[0, 1, null]'
    #   JSON[json]# => [0, 1, nil]
    #
    # Otherwise, calls JSON.generate with +object+ and +opts+:
    #   ruby = [0, 1, nil]
    #   JSON[ruby] # => "[0,1,null]"
    def [](object, opts = {})
      if object.respond_to? :to_str
        JSON.parse(object.to_str, opts)
      else
        JSON.generate(object, opts)
      end
    end

    # Returns the JSON parser class that is used by JSON. This is either
    # JSON::Ext::Parser or JSON::Pure::Parser:
    #   JSON.parser # => JSON::Ext::Parser
    attr_reader :parser

    # Set the JSON parser class _parser_ to be used by JSON.
    def parser=(parser) # :nodoc:
      @parser = parser
      remove_const :Parser if const_defined?(:Parser, false)
      const_set :Parser, parser
    end

    # Return the constant located at _path_. The format of _path_ has to be
    # either ::A::B::C or A::B::C. In any case, A has to be located at the top
    # level (absolute namespace path?). If there doesn't exist a constant at
    # the given path, an ArgumentError is raised.
    def deep_const_get(path) # :nodoc:
      path.to_s.split(/::/).inject(Object) do |p, c|
        case
        when c.empty?                  then p
        when p.const_defined?(c, true) then p.const_get(c)
        else
          begin
            p.const_missing(c)
          rescue NameError => e
            raise ArgumentError, "can't get const #{path}: #{e}"
          end
        end
      end
    end

    # Set the module _generator_ to be used by JSON.
    def generator=(generator) # :nodoc:
      old, $VERBOSE = $VERBOSE, nil
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
      const_set :SAFE_STATE_PROTOTYPE, State.new
      const_set :FAST_STATE_PROTOTYPE, State.new(
        :indent         => '',
        :space          => '',
        :object_nl      => "",
        :array_nl       => "",
        :max_nesting    => false
      )
      const_set :PRETTY_STATE_PROTOTYPE, State.new(
        :indent         => '  ',
        :space          => ' ',
        :object_nl      => "\n",
        :array_nl       => "\n"
      )
    ensure
      $VERBOSE = old
    end

    # Returns the JSON generator module that is used by JSON. This is
    # either JSON::Ext::Generator or JSON::Pure::Generator:
    #   JSON.generator # => JSON::Ext::Generator
    attr_reader :generator

    # Sets or Returns the JSON generator state class that is used by JSON. This is
    # either JSON::Ext::Generator::State or JSON::Pure::Generator::State:
    #   JSON.state # => JSON::Ext::Generator::State
    attr_accessor :state

    # Sets or returns create identifier, which is used to decide if the _json_create_
    # hook of a class should be called; initial value is +json_class+:
    #   JSON.create_id # => "json_class"
    attr_accessor :create_id
  end
  self.create_id = 'json_class'

  NaN           = 0.0/0

  Infinity      = 1.0/0

  MinusInfinity = -Infinity

  # The base exception for JSON errors.
  class JSONError < StandardError
    def self.wrap(exception)
      obj = new("Wrapped(#{exception.class}): #{exception.message.inspect}")
      obj.set_backtrace exception.backtrace
      obj
    end
  end

  # This exception is raised if a parser error occurs.
  class ParserError < JSONError; end

  # This exception is raised if the nesting of parsed data structures is too
  # deep.
  class NestingError < ParserError; end

  # :stopdoc:
  class CircularDatastructure < NestingError; end
  # :startdoc:

  # This exception is raised if a generator or unparser error occurs.
  class GeneratorError < JSONError; end
  # For backwards compatibility
  UnparserError = GeneratorError # :nodoc:

  # This exception is raised if the required unicode support is missing on the
  # system. Usually this means that the iconv library is not installed.
  class MissingUnicodeSupport < JSONError; end

  module_function

  # Argument +source+ contains the \String to be parsed. It must be a
  # {String-convertible object}[doc/implicit_conversion_rdoc.html#label-String-Convertible+Objects]
  # (implementing +to_str+), and must contain valid \JSON data.
  #
  # Argument +opts+, if given, contains options for the parsing, and must be a
  # {Hash-convertible object}[doc/implicit_conversion_rdoc.html#label-Hash-Convertible+Objects]
  # (implementing +to_hash+).
  #
  # Returns the Ruby objects created by parsing the given +source+.
  #
  # ---
  #
  # When +source+ is a \JSON array, returns a Ruby \Array:
  #   source = '["foo", 1.0, true, false, null]'
  #   ruby = JSON.parse(source)
  #   ruby # => ["foo", 1.0, true, false, nil]
  #   ruby.class # => Array
  #
  # When +source+ is a \JSON object, returns a Ruby \Hash:
  #   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
  #   ruby = JSON.parse(source)
  #   ruby # => {"a"=>"foo", "b"=>1.0, "c"=>true, "d"=>false, "e"=>nil}
  #   ruby.class # => Hash
  #
  # For examples of parsing for all \JSON data types, see
  # {Parsing \JSON}[#module-JSON-label-Parsing+JSON].
  #
  # ====== Input Options
  #
  # Option +max_nesting+ (\Integer) specifies the maximum nesting depth allowed;
  # defaults to +100+; specify +false+ to disable depth checking.
  #
  # With the default, +false+:
  #   source = '[0, [1, [2, [3]]]]'
  #   ruby = JSON.parse(source)
  #   ruby # => [0, [1, [2, [3]]]]
  # Too deep:
  #   # Raises JSON::NestingError (nesting of 2 is too deep):
  #   JSON.parse(source, {max_nesting: 1})
  # Bad value:
  #   # Raises TypeError (wrong argument type Symbol (expected Fixnum)):
  #   JSON.parse(source, {max_nesting: :foo})
  #
  # ---
  #
  # Option +allow_nan+ (boolean) specifies whether to allow
  # NaN, Infinity, and MinusInfinity in +source+;
  # defaults to +false+.
  #
  # With the default, +false+:
  #   # Raises JSON::ParserError (225: unexpected token at '[NaN]'):
  #   JSON.parse('[NaN]')
  #   # Raises JSON::ParserError (232: unexpected token at '[Infinity]'):
  #   JSON.parse('[Infinity]')
  #   # Raises JSON::ParserError (248: unexpected token at '[-Infinity]'):
  #   JSON.parse('[-Infinity]')
  # Allow:
  #   source = '[NaN, Infinity, -Infinity]'
  #   ruby = JSON.parse(source, {allow_nan: true})
  #   ruby # => [NaN, Infinity, -Infinity]
  # With a truthy value:
  #   ruby = JSON.parse(source, {allow_nan: :foo})
  #   ruby # => [NaN, Infinity, -Infinity]
  #
  # ====== Output Options
  #
  # Option +symbolize_names+ (boolean) specifies whether returned \Hash keys
  # should be Symbols;
  # defaults to +false+ (use Strings).
  #
  # With the default, +false+:
  #   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
  #   ruby = JSON.parse(source)
  #   ruby # => {"a"=>"foo", "b"=>1.0, "c"=>true, "d"=>false, "e"=>nil}
  # Use Symbols:
  #   ruby = JSON.parse(source, {symbolize_names: true})
  #   ruby # => {:a=>"foo", :b=>1.0, :c=>true, :d=>false, :e=>nil}
  #
  # ---
  #
  # Option +object_class+ (\Class) specifies the Ruby class to be used
  # for each \JSON object;
  # defaults to \Hash.
  #
  # With the default, \Hash:
  #   source = '{"a": "foo", "b": 1.0, "c": true, "d": false, "e": null}'
  #   ruby = JSON.parse(source)
  #   ruby.class # => Hash
  # Use class \OpenStruct:
  #   ruby = JSON.parse(source, {object_class: OpenStruct})
  #   ruby # => #<OpenStruct a="foo", b=1.0, c=true, d=false, e=nil>
  # Try class \Object:
  #   # Raises NoMethodError (undefined method `[]=' for #<Object:>):
  #   JSON.parse(source, {object_class: Object})
  # Bad value:
  #   # Raises TypeError (wrong argument type Symbol (expected Class)):
  #   JSON.parse(source, {object_class: :foo})
  #
  # ---
  #
  # Option +array_class+ (\Class) specifies the Ruby class to be used
  # for each \JSON array;
  # defaults to \Array.
  #
  # With the default, \Array:
  #   source = '["foo", 1.0, true, false, null]'
  #   ruby = JSON.parse(source)
  #   ruby.class # => Array
  # Use class \Set:
  #   ruby = JSON.parse(source, {array_class: Set})
  #   ruby # => #<Set: {"foo", 1.0, true, false, nil}>
  # Try class \Object:
  #   # Raises NoMethodError (undefined method `<<' for #<Object:>):
  #   JSON.parse(source, {array_class: Object})
  # Bad value:
  #   # Raises TypeError (wrong argument type Symbol (expected Class)):
  #   JSON.parse(source, {array_class: :foo})
  #
  # ---
  #
  # Option +create_additions+ (boolean) specifies whether to use \JSON additions in parsing.
  # See {\JSON Additions}[#module-JSON-label-JSON+Additions].
  #
  # ====== Exceptions
  #
  # Raises an exception if +source+ is not \String-convertible:
  #
  #   # Raises TypeError (no implicit conversion of Symbol into String):
  #   JSON.parse(:foo)
  #
  # Raises an exception if +opts+ is not \Hash-convertible:
  #
  #   # Raises TypeError (no implicit conversion of Symbol into Hash):
  #   JSON.parse(['foo'], :foo)
  #
  # Raises an exception if +source+ is not valid JSON:
  #
  #   # Raises JSON::ParserError (783: unexpected token at ''):
  #   JSON.parse('')
  #
  def parse(source, opts = {})
    Parser.new(source, **(opts||{})).parse
  end

  # Calls
  #   JSON.parse(source, opts)
  # with +source+ and possibly modified +opts+.
  #
  # Differences from JSON.parse:
  # - Option +max_nesting+, if not provided, defaults to +false+,
  #   which disables checking for nesting depth.
  # - Option +allow_nan+, if not provided, defaults to +true+.
  def parse!(source, opts = {})
    opts = {
      :max_nesting  => false,
      :allow_nan    => true
    }.merge(opts)
    Parser.new(source, **(opts||{})).parse
  end

  # Argument +obj+ is the Ruby object to be converted to \JSON.
  #
  # Argument +opts+, if given, contains options for the generation, and must be a
  # {Hash-convertible object}[doc/implicit_conversion_rdoc.html#label-Hash-Convertible+Objects]
  # (implementing +to_hash+).
  #
  # Returns a \String containing the generated \JSON data.
  #
  # See also JSON.fast_generate, JSON.pretty_generate.
  #
  # ---
  #
  # When +obj+ is an
  # {Array-convertible object}[doc/implicit_conversion_rdoc.html#label-Array-Convertible+Objects]
  # (implementing +to_ary+), returns a \String containing a \JSON array:
  #   obj = ["foo", 1.0, true, false, nil]
  #   json = JSON.generate(obj)
  #   json # => "[\"foo\",1.0,true,false,null]"
  #   json.class # => String
  #
  # When +obj+ is a
  # {Hash-convertible object}[doc/implicit_conversion_rdoc.html#label-Hash-Convertible+Objects],
  # return a \String containing a \JSON object:
  #   obj = {foo: 0, bar: 's', baz: :bat}
  #   json = JSON.generate(obj)
  #   json # => "{\"foo\":0,\"bar\":\"s\",\"baz\":\"bat\"}"
  #
  # For examples of generating from other Ruby objects, see
  # {Generating \JSON from Other Objects}[#module-JSON-label-Generating+JSON+from+Other+Objects].
  #
  # ====== Input Options
  #
  # Option +allow_nan+ (boolean) specifies whether
  # +NaN+, +Infinity+, and <tt>-Infinity</tt> may be generated;
  # defaults to +false+.
  #
  # With the default, +false+:
  #   # Raises JSON::GeneratorError (920: NaN not allowed in JSON):
  #   JSON.generate(JSON::NaN)
  #   # Raises JSON::GeneratorError (917: Infinity not allowed in JSON):
  #   JSON.generate(JSON::Infinity)
  #   # Raises JSON::GeneratorError (917: -Infinity not allowed in JSON):
  #   JSON.generate(JSON::MinusInfinity)
  #
  # Allow:
  #   ruby = [JSON::NaN, JSON::Infinity, JSON::MinusInfinity]
  #   JSON.generate(ruby, allow_nan: true) # => "[NaN,Infinity,-Infinity]"
  #
  # ---
  #
  # Option +max_nesting+ (\Integer) specifies the maximum nesting depth
  # in +obj+; defaults to +100+.
  #
  # With the default, +100+:
  #   obj = [[[[[[0]]]]]]
  #   JSON.generate(obj) # => "[[[[[[0]]]]]]"
  #
  # Too deep:
  #   # Raises JSON::NestingError (nesting of 2 is too deep):
  #   JSON.generate(obj, max_nesting: 2)
  #
  # Bad Value:
  #   # Raises TypeError (can't convert Symbol into Hash):
  #   JSON.generate(obj, :foo)
  #
  # ====== Output Options
  #
  # The default formatting options generate the most compact
  # \JSON data, all on one line and with no whitespace.
  #
  # You can use these formatting options to generate
  # \JSON data in a more open format, using whitespace.
  # See also JSON.pretty_generate.
  #
  # - Option +array_nl+ (\String) specifies a string (usually a newline)
  #   to be inserted after each \JSON array; defaults to the empty \String, <tt>''</tt>.
  # - Option +object_nl+ (\String) specifies a string (usually a newline)
  #   to be inserted after each \JSON object; defaults to the empty \String, <tt>''</tt>.
  # - Option +indent+ (\String) specifies the string (usually spaces) to be
  #   used for indentation; defaults to the empty \String, <tt>''</tt>;
  #   defaults to the empty \String, <tt>''</tt>;
  #   has no effect unless options +array_nl+ or +object_nl+ specify newlines.
  # - Option +space+ (\String) specifies a string (usually a space) to be
  #   inserted after the colon in each \JSON object's pair;
  #   defaults to the empty \String, <tt>''</tt>.
  # - Option +space_before+ (\String) specifies a string (usually a space) to be
  #   inserted before the colon in each \JSON object's pair;
  #   defaults to the empty \String, <tt>''</tt>.
  #
  # In this example, +obj+ is used first to generate the shortest
  # \JSON data (no whitespace), then again with all formatting options
  # specified:
  #
  #   obj = {foo: [:bar, :baz], bat: {bam: 0, bad: 1}}
  #   json = JSON.generate(obj)
  #   puts 'Compact:', json
  #   opts = {
  #     array_nl: "\n",
  #     object_nl: "\n",
  #     indent+: '  ',
  #     space_before: ' ',
  #     space: ' '
  #   }
  #   puts 'Open:', JSON.generate(obj, opts)
  #
  # Output:
  #   Compact:
  #   {"foo":["bar","baz"],"bat":{"bam":0,"bad":1}}
  #   Open:
  #   {
  #     "foo" : [
  #       "bar",
  #       "baz"
  #   ],
  #     "bat" : {
  #       "bam" : 0,
  #       "bad" : 1
  #     }
  #   }
  #
  # ---
  #
  # Raises an exception if any formatting option is not a \String.
  #
  # ====== Exceptions
  #
  # Raises an exception if +obj+ is not a valid Ruby object:
  #   # Raises NameError (uninitialized constant Foo):
  #   JSON.generate(Foo)
  #   # Raises NameError (undefined local variable or method `foo' for main:Object):
  #   JSON.generate(foo)
  #
  # Raises an exception if +obj+ contains circular references:
  #   a = []; b = []; a.push(b); b.push(a)
  #   # Raises JSON::NestingError (nesting of 100 is too deep):
  #   JSON.generate(a)
  #
  # Raises an exception if +opts is not a
  # {Hash-convertible object}[doc/implicit_conversion_rdoc.html#label-Hash-Convertible+Objects]
  # (implementing +to_hash+):
  #   # Raises TypeError (can't convert Symbol into Hash):
  #   JSON.generate('x', :foo)
  def generate(obj, opts = nil)
    if State === opts
      state, opts = opts, nil
    else
      state = SAFE_STATE_PROTOTYPE.dup
    end
    if opts
      if opts.respond_to? :to_hash
        opts = opts.to_hash
      elsif opts.respond_to? :to_h
        opts = opts.to_h
      else
        raise TypeError, "can't convert #{opts.class} into Hash"
      end
      state = state.configure(opts)
    end
    state.generate(obj)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and
  # later delete them.
  alias unparse generate
  module_function :unparse
  # :startdoc:

  # Arguments +obj+ and +opts+ here are the same as
  # arguments +obj+ and +opts+ in JSON.generate.
  #
  # By default, generates \JSON data without checking
  # for circular references in +obj+ (option +max_nesting+ set to +false+, disabled).
  #
  # Raises an exception if +obj+ contains circular references:
  #   a = []; b = []; a.push(b); b.push(a)
  #   # Raises SystemStackError (stack level too deep):
  #   JSON.fast_generate(a)
  def fast_generate(obj, opts = nil)
    if State === opts
      state, opts = opts, nil
    else
      state = FAST_STATE_PROTOTYPE.dup
    end
    if opts
      if opts.respond_to? :to_hash
        opts = opts.to_hash
      elsif opts.respond_to? :to_h
        opts = opts.to_h
      else
        raise TypeError, "can't convert #{opts.class} into Hash"
      end
      state.configure(opts)
    end
    state.generate(obj)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and later delete them.
  alias fast_unparse fast_generate
  module_function :fast_unparse
  # :startdoc:

  # Arguments +obj+ and +opts+ here are the same as
  # arguments +obj+ and +opts+ in JSON.generate.
  #
  # Default options are:
  #   {
  #     indent: '  ',   # Two spaces
  #     space: ' ',     # One space
  #     array_nl: "\n", # Newline
  #     object_nl: "\n" # Newline
  #   }
  #
  # Example:
  #   obj = {foo: [:bar, :baz], bat: {bam: 0, bad: 1}}
  #   json = JSON.pretty_generate(obj)
  #   puts json
  # Output:
  #   {
  #     "foo": [
  #       "bar",
  #       "baz"
  #     ],
  #     "bat": {
  #       "bam": 0,
  #       "bad": 1
  #     }
  #   }
  #
  def pretty_generate(obj, opts = nil)
    if State === opts
      state, opts = opts, nil
    else
      state = PRETTY_STATE_PROTOTYPE.dup
    end
    if opts
      if opts.respond_to? :to_hash
        opts = opts.to_hash
      elsif opts.respond_to? :to_h
        opts = opts.to_h
      else
        raise TypeError, "can't convert #{opts.class} into Hash"
      end
      state.configure(opts)
    end
    state.generate(obj)
  end

  # :stopdoc:
  # I want to deprecate these later, so I'll first be silent about them, and later delete them.
  alias pretty_unparse pretty_generate
  module_function :pretty_unparse
  # :startdoc:

  class << self
    # Sets or returns default options for the JSON.load method.
    # Initially:
    #   opts = JSON.load_default_options
    #   opts # => {:max_nesting=>false, :allow_nan=>true, :allow_blank=>true, :create_additions=>true}
    attr_accessor :load_default_options
  end
  self.load_default_options = {
    :max_nesting      => false,
    :allow_nan        => true,
    :allow_blank       => true,
    :create_additions => true,
  }

  # Load a ruby data structure from a JSON _source_ and return it. A source can
  # either be a string-like object, an IO-like object, or an object responding
  # to the read method. If _proc_ was given, it will be called with any nested
  # Ruby object as an argument recursively in depth first order. To modify the
  # default options pass in the optional _options_ argument as well.
  #
  # BEWARE: This method is meant to serialise data from trusted user input,
  # like from your own database server or clients under your control, it could
  # be dangerous to allow untrusted users to pass JSON sources into it. The
  # default options for the parser can be changed via the load_default_options
  # method.
  #
  # This method is part of the implementation of the load/dump interface of
  # Marshal and YAML.
  def load(source, proc = nil, options = {})
    opts = load_default_options.merge options
    if source.respond_to? :to_str
      source = source.to_str
    elsif source.respond_to? :to_io
      source = source.to_io.read
    elsif source.respond_to?(:read)
      source = source.read
    end
    if opts[:allow_blank] && (source.nil? || source.empty?)
      source = 'null'
    end
    result = parse(source, opts)
    recurse_proc(result, &proc) if proc
    result
  end

  # Recursively calls passed _Proc_ if the parsed data structure is an _Array_ or _Hash_
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

  class << self
    # Sets or returns the default options for the JSON.dump method.
    # Initially:
    #   opts = JSON.dump_default_options
    #   opts # => {:max_nesting=>false, :allow_nan=>true}
    attr_accessor :dump_default_options
  end
  self.dump_default_options = {
    :max_nesting => false,
    :allow_nan   => true,
  }

  # Dumps _obj_ as a JSON string, i.e. calls generate on the object and returns
  # the result.
  #
  # If anIO (an IO-like object or an object that responds to the write method)
  # was given, the resulting JSON is written to it.
  #
  # If the number of nested arrays or objects exceeds _limit_, an ArgumentError
  # exception is raised. This argument is similar (but not exactly the
  # same!) to the _limit_ argument in Marshal.dump.
  #
  # The default options for the generator can be changed via the
  # dump_default_options method.
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
    opts = JSON.dump_default_options
    opts = opts.merge(:max_nesting => limit) if limit
    result = generate(obj, opts)
    if anIO
      anIO.write result
      anIO
    else
      result
    end
  rescue JSON::NestingError
    raise ArgumentError, "exceed depth limit"
  end

  # Encodes string using String.encode.
  def self.iconv(to, from, string)
    string.encode(to, from)
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

  # Outputs _objs_ to STDOUT as JSON strings in a pretty format, with
  # indentation and over many lines.
  def jj(*objs)
    objs.each do |obj|
      puts JSON::pretty_generate(obj, :allow_nan => true, :max_nesting => false)
    end
    nil
  end

  # If _object_ is string-like, parse the string and return the parsed result as
  # a Ruby data structure. Otherwise, generate a JSON text from the Ruby data
  # structure object and return it.
  #
  # The _opts_ argument is passed through to generate/parse respectively. See
  # generate and parse for their documentation.
  def JSON(object, *args)
    if object.respond_to? :to_str
      JSON.parse(object.to_str, args.first)
    else
      JSON.generate(object, args.first)
    end
  end
end

# Extends any Class to include _json_creatable?_ method.
class ::Class
  # Returns true if this class can be used to create an instance
  # from a serialised JSON string. The class has to implement a class
  # method _json_create_ that expects a hash as first parameter. The hash
  # should include the required data.
  def json_creatable?
    respond_to?(:json_create)
  end
end
