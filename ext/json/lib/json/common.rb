# frozen_string_literal: true

require 'json/version'

module JSON
  autoload :GenericObject, 'json/generic_object'

  NOT_SET = Object.new.freeze
  private_constant :NOT_SET

  class << self
    # :call-seq:
    #   JSON[object] -> new_array or new_string
    #
    # If +object+ is a \String,
    # calls JSON.parse with +object+ and +opts+ (see method #parse):
    #   json = '[0, 1, null]'
    #   JSON[json]# => [0, 1, nil]
    #
    # Otherwise, calls JSON.generate with +object+ and +opts+ (see method #generate):
    #   ruby = [0, 1, nil]
    #   JSON[ruby] # => '[0,1,null]'
    def [](object, opts = {})
      if object.is_a?(String)
        return JSON.parse(object, opts)
      elsif object.respond_to?(:to_str)
        str = object.to_str
        if str.is_a?(String)
          return JSON.parse(str, opts)
        end
      end

      JSON.generate(object, opts)
    end

    # Returns the JSON parser class that is used by JSON.
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
      Object.const_get(path)
    rescue NameError => e
      raise ArgumentError, "can't get const #{path}: #{e}"
    end

    # Set the module _generator_ to be used by JSON.
    def generator=(generator) # :nodoc:
      old, $VERBOSE = $VERBOSE, nil
      @generator = generator
      generator_methods = generator::GeneratorMethods
      for const in generator_methods.constants
        klass = const_get(const)
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
      const_set :SAFE_STATE_PROTOTYPE, State.new # for JRuby
      const_set :FAST_STATE_PROTOTYPE, create_fast_state
      const_set :PRETTY_STATE_PROTOTYPE, create_pretty_state
    ensure
      $VERBOSE = old
    end

    def create_fast_state
      State.new(
        :indent         => '',
        :space          => '',
        :object_nl      => "",
        :array_nl       => "",
        :max_nesting    => false
      )
    end

    def create_pretty_state
      State.new(
        :indent         => '  ',
        :space          => ' ',
        :object_nl      => "\n",
        :array_nl       => "\n"
      )
    end

    # Returns the JSON generator module that is used by JSON.
    attr_reader :generator

    # Sets or Returns the JSON generator state class that is used by JSON.
    attr_accessor :state

    private

    def deprecated_singleton_attr_accessor(*attrs)
      args = RUBY_VERSION >= "3.0" ? ", category: :deprecated" : ""
      attrs.each do |attr|
        singleton_class.class_eval <<~RUBY
          def #{attr}
            warn "JSON.#{attr} is deprecated and will be removed in json 3.0.0", uplevel: 1 #{args}
            @#{attr}
          end

          def #{attr}=(val)
            warn "JSON.#{attr}= is deprecated and will be removed in json 3.0.0", uplevel: 1 #{args}
            @#{attr} = val
          end

          def _#{attr}
            @#{attr}
          end
        RUBY
      end
    end
  end

  # Sets create identifier, which is used to decide if the _json_create_
  # hook of a class should be called; initial value is +json_class+:
  #   JSON.create_id # => 'json_class'
  def self.create_id=(new_value)
    Thread.current[:"JSON.create_id"] = new_value.dup.freeze
  end

  # Returns the current create identifier.
  # See also JSON.create_id=.
  def self.create_id
    Thread.current[:"JSON.create_id"] || 'json_class'
  end

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
  class GeneratorError < JSONError
    attr_reader :invalid_object

    def initialize(message, invalid_object = nil)
      super(message)
      @invalid_object = invalid_object
    end

    def detailed_message(...)
      # Exception#detailed_message doesn't exist until Ruby 3.2
      super_message = defined?(super) ? super : message

      if @invalid_object.nil?
        super_message
      else
        "#{super_message}\nInvalid object: #{@invalid_object.inspect}"
      end
    end
  end

  # For backwards compatibility
  UnparserError = GeneratorError # :nodoc:

  # This exception is raised if the required unicode support is missing on the
  # system. Usually this means that the iconv library is not installed.
  class MissingUnicodeSupport < JSONError; end

  # Fragment of JSON document that is to be included as is:
  #   fragment = JSON::Fragment.new("[1, 2, 3]")
  #   JSON.generate({ count: 3, items: fragments })
  #
  # This allows to easily assemble multiple JSON fragments that have
  # been persisted somewhere without having to parse them nor resorting
  # to string interpolation.
  #
  # Note: no validation is performed on the provided string. It is the
  # responsability of the caller to ensure the string contains valid JSON.
  Fragment = Struct.new(:json) do
    def initialize(json)
      unless string = String.try_convert(json)
        raise TypeError, " no implicit conversion of #{json.class} into String"
      end

      super(string)
    end

    def to_json(state = nil, *)
      json
    end
  end

  module_function

  # :call-seq:
  #   JSON.parse(source, opts) -> object
  #
  # Returns the Ruby objects created by parsing the given +source+.
  #
  # Argument +source+ contains the \String to be parsed.
  #
  # Argument +opts+, if given, contains a \Hash of options for the parsing.
  # See {Parsing Options}[#module-JSON-label-Parsing+Options].
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
  # Parses nested JSON objects:
  #   source = <<~JSON
  #     {
  #     "name": "Dave",
  #       "age" :40,
  #       "hats": [
  #         "Cattleman's",
  #         "Panama",
  #         "Tophat"
  #       ]
  #     }
  #   JSON
  #   ruby = JSON.parse(source)
  #   ruby # => {"name"=>"Dave", "age"=>40, "hats"=>["Cattleman's", "Panama", "Tophat"]}
  #
  # ---
  #
  # Raises an exception if +source+ is not valid JSON:
  #   # Raises JSON::ParserError (783: unexpected token at ''):
  #   JSON.parse('')
  #
  def parse(source, opts = nil)
    Parser.parse(source, opts)
  end

  # :call-seq:
  #   JSON.parse!(source, opts) -> object
  #
  # Calls
  #   parse(source, opts)
  # with +source+ and possibly modified +opts+.
  #
  # Differences from JSON.parse:
  # - Option +max_nesting+, if not provided, defaults to +false+,
  #   which disables checking for nesting depth.
  # - Option +allow_nan+, if not provided, defaults to +true+.
  def parse!(source, opts = nil)
    options = {
      :max_nesting  => false,
      :allow_nan    => true
    }
    options.merge!(opts) if opts
    Parser.new(source, options).parse
  end

  # :call-seq:
  #   JSON.load_file(path, opts={}) -> object
  #
  # Calls:
  #   parse(File.read(path), opts)
  #
  # See method #parse.
  def load_file(filespec, opts = nil)
    parse(File.read(filespec, encoding: Encoding::UTF_8), opts)
  end

  # :call-seq:
  #   JSON.load_file!(path, opts = {})
  #
  # Calls:
  #   JSON.parse!(File.read(path, opts))
  #
  # See method #parse!
  def load_file!(filespec, opts = nil)
    parse!(File.read(filespec, encoding: Encoding::UTF_8), opts)
  end

  # :call-seq:
  #   JSON.generate(obj, opts = nil) -> new_string
  #
  # Returns a \String containing the generated \JSON data.
  #
  # See also JSON.fast_generate, JSON.pretty_generate.
  #
  # Argument +obj+ is the Ruby object to be converted to \JSON.
  #
  # Argument +opts+, if given, contains a \Hash of options for the generation.
  # See {Generating Options}[#module-JSON-label-Generating+Options].
  #
  # ---
  #
  # When +obj+ is an \Array, returns a \String containing a \JSON array:
  #   obj = ["foo", 1.0, true, false, nil]
  #   json = JSON.generate(obj)
  #   json # => '["foo",1.0,true,false,null]'
  #
  # When +obj+ is a \Hash, returns a \String containing a \JSON object:
  #   obj = {foo: 0, bar: 's', baz: :bat}
  #   json = JSON.generate(obj)
  #   json # => '{"foo":0,"bar":"s","baz":"bat"}'
  #
  # For examples of generating from other Ruby objects, see
  # {Generating \JSON from Other Objects}[#module-JSON-label-Generating+JSON+from+Other+Objects].
  #
  # ---
  #
  # Raises an exception if any formatting option is not a \String.
  #
  # Raises an exception if +obj+ contains circular references:
  #   a = []; b = []; a.push(b); b.push(a)
  #   # Raises JSON::NestingError (nesting of 100 is too deep):
  #   JSON.generate(a)
  #
  def generate(obj, opts = nil)
    if State === opts
      opts.generate(obj)
    else
      State.generate(obj, opts, nil)
    end
  end

  # :call-seq:
  #   JSON.fast_generate(obj, opts) -> new_string
  #
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
      state = opts
    else
      state = JSON.create_fast_state.configure(opts)
    end
    state.generate(obj)
  end

  # :call-seq:
  #   JSON.pretty_generate(obj, opts = nil) -> new_string
  #
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
      state = JSON.create_pretty_state
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

  # Sets or returns default options for the JSON.unsafe_load method.
  # Initially:
  #   opts = JSON.load_default_options
  #   opts # => {:max_nesting=>false, :allow_nan=>true, :allow_blank=>true, :create_additions=>true}
  deprecated_singleton_attr_accessor :unsafe_load_default_options

  @unsafe_load_default_options = {
    :max_nesting      => false,
    :allow_nan        => true,
    :allow_blank      => true,
    :create_additions => true,
  }

  # Sets or returns default options for the JSON.load method.
  # Initially:
  #   opts = JSON.load_default_options
  #   opts # => {:max_nesting=>false, :allow_nan=>true, :allow_blank=>true, :create_additions=>true}
  deprecated_singleton_attr_accessor :load_default_options

  @load_default_options = {
    :allow_nan        => true,
    :allow_blank      => true,
    :create_additions => nil,
  }
  # :call-seq:
  #   JSON.unsafe_load(source, proc = nil, options = {}) -> object
  #
  # Returns the Ruby objects created by parsing the given +source+.
  #
  # BEWARE: This method is meant to serialise data from trusted user input,
  # like from your own database server or clients under your control, it could
  # be dangerous to allow untrusted users to pass JSON sources into it.
  #
  # - Argument +source+ must be, or be convertible to, a \String:
  #   - If +source+ responds to instance method +to_str+,
  #     <tt>source.to_str</tt> becomes the source.
  #   - If +source+ responds to instance method +to_io+,
  #     <tt>source.to_io.read</tt> becomes the source.
  #   - If +source+ responds to instance method +read+,
  #     <tt>source.read</tt> becomes the source.
  #   - If both of the following are true, source becomes the \String <tt>'null'</tt>:
  #     - Option +allow_blank+ specifies a truthy value.
  #     - The source, as defined above, is +nil+ or the empty \String <tt>''</tt>.
  #   - Otherwise, +source+ remains the source.
  # - Argument +proc+, if given, must be a \Proc that accepts one argument.
  #   It will be called recursively with each result (depth-first order).
  #   See details below.
  # - Argument +opts+, if given, contains a \Hash of options for the parsing.
  #   See {Parsing Options}[#module-JSON-label-Parsing+Options].
  #   The default options can be changed via method JSON.unsafe_load_default_options=.
  #
  # ---
  #
  # When no +proc+ is given, modifies +source+ as above and returns the result of
  # <tt>parse(source, opts)</tt>;  see #parse.
  #
  # Source for following examples:
  #   source = <<~JSON
  #     {
  #       "name": "Dave",
  #       "age" :40,
  #       "hats": [
  #         "Cattleman's",
  #         "Panama",
  #         "Tophat"
  #       ]
  #     }
  #   JSON
  #
  # Load a \String:
  #   ruby = JSON.unsafe_load(source)
  #   ruby # => {"name"=>"Dave", "age"=>40, "hats"=>["Cattleman's", "Panama", "Tophat"]}
  #
  # Load an \IO object:
  #   require 'stringio'
  #   object = JSON.unsafe_load(StringIO.new(source))
  #   object # => {"name"=>"Dave", "age"=>40, "hats"=>["Cattleman's", "Panama", "Tophat"]}
  #
  # Load a \File object:
  #   path = 't.json'
  #   File.write(path, source)
  #   File.open(path) do |file|
  #     JSON.unsafe_load(file)
  #   end # => {"name"=>"Dave", "age"=>40, "hats"=>["Cattleman's", "Panama", "Tophat"]}
  #
  # ---
  #
  # When +proc+ is given:
  # - Modifies +source+ as above.
  # - Gets the +result+ from calling <tt>parse(source, opts)</tt>.
  # - Recursively calls <tt>proc(result)</tt>.
  # - Returns the final result.
  #
  # Example:
  #   require 'json'
  #
  #   # Some classes for the example.
  #   class Base
  #     def initialize(attributes)
  #       @attributes = attributes
  #     end
  #   end
  #   class User    < Base; end
  #   class Account < Base; end
  #   class Admin   < Base; end
  #   # The JSON source.
  #   json = <<-EOF
  #   {
  #     "users": [
  #         {"type": "User", "username": "jane", "email": "jane@example.com"},
  #         {"type": "User", "username": "john", "email": "john@example.com"}
  #     ],
  #     "accounts": [
  #         {"account": {"type": "Account", "paid": true, "account_id": "1234"}},
  #         {"account": {"type": "Account", "paid": false, "account_id": "1235"}}
  #     ],
  #     "admins": {"type": "Admin", "password": "0wn3d"}
  #   }
  #   EOF
  #   # Deserializer method.
  #   def deserialize_obj(obj, safe_types = %w(User Account Admin))
  #     type = obj.is_a?(Hash) && obj["type"]
  #     safe_types.include?(type) ? Object.const_get(type).new(obj) : obj
  #   end
  #   # Call to JSON.unsafe_load
  #   ruby = JSON.unsafe_load(json, proc {|obj|
  #     case obj
  #     when Hash
  #       obj.each {|k, v| obj[k] = deserialize_obj v }
  #     when Array
  #       obj.map! {|v| deserialize_obj v }
  #     end
  #   })
  #   pp ruby
  # Output:
  #   {"users"=>
  #      [#<User:0x00000000064c4c98
  #        @attributes=
  #          {"type"=>"User", "username"=>"jane", "email"=>"jane@example.com"}>,
  #        #<User:0x00000000064c4bd0
  #        @attributes=
  #          {"type"=>"User", "username"=>"john", "email"=>"john@example.com"}>],
  #    "accounts"=>
  #      [{"account"=>
  #          #<Account:0x00000000064c4928
  #          @attributes={"type"=>"Account", "paid"=>true, "account_id"=>"1234"}>},
  #       {"account"=>
  #          #<Account:0x00000000064c4680
  #          @attributes={"type"=>"Account", "paid"=>false, "account_id"=>"1235"}>}],
  #    "admins"=>
  #      #<Admin:0x00000000064c41f8
  #      @attributes={"type"=>"Admin", "password"=>"0wn3d"}>}
  #
  def unsafe_load(source, proc = nil, options = nil)
    opts = if options.nil?
      _unsafe_load_default_options
    else
      _unsafe_load_default_options.merge(options)
    end

    unless source.is_a?(String)
      if source.respond_to? :to_str
        source = source.to_str
      elsif source.respond_to? :to_io
        source = source.to_io.read
      elsif source.respond_to?(:read)
        source = source.read
      end
    end

    if opts[:allow_blank] && (source.nil? || source.empty?)
      source = 'null'
    end
    result = parse(source, opts)
    recurse_proc(result, &proc) if proc
    result
  end

  # :call-seq:
  #   JSON.load(source, proc = nil, options = {}) -> object
  #
  # Returns the Ruby objects created by parsing the given +source+.
  #
  # BEWARE: This method is meant to serialise data from trusted user input,
  # like from your own database server or clients under your control, it could
  # be dangerous to allow untrusted users to pass JSON sources into it.
  # If you must use it, use JSON.unsafe_load instead to make it clear.
  #
  # Since JSON version 2.8.0, `load` emits a deprecation warning when a
  # non native type is deserialized, without `create_additions` being explicitly
  # enabled, and in JSON version 3.0, `load` will have `create_additions` disabled
  # by default.
  #
  # - Argument +source+ must be, or be convertible to, a \String:
  #   - If +source+ responds to instance method +to_str+,
  #     <tt>source.to_str</tt> becomes the source.
  #   - If +source+ responds to instance method +to_io+,
  #     <tt>source.to_io.read</tt> becomes the source.
  #   - If +source+ responds to instance method +read+,
  #     <tt>source.read</tt> becomes the source.
  #   - If both of the following are true, source becomes the \String <tt>'null'</tt>:
  #     - Option +allow_blank+ specifies a truthy value.
  #     - The source, as defined above, is +nil+ or the empty \String <tt>''</tt>.
  #   - Otherwise, +source+ remains the source.
  # - Argument +proc+, if given, must be a \Proc that accepts one argument.
  #   It will be called recursively with each result (depth-first order).
  #   See details below.
  # - Argument +opts+, if given, contains a \Hash of options for the parsing.
  #   See {Parsing Options}[#module-JSON-label-Parsing+Options].
  #   The default options can be changed via method JSON.load_default_options=.
  #
  # ---
  #
  # When no +proc+ is given, modifies +source+ as above and returns the result of
  # <tt>parse(source, opts)</tt>;  see #parse.
  #
  # Source for following examples:
  #   source = <<~JSON
  #     {
  #       "name": "Dave",
  #       "age" :40,
  #       "hats": [
  #         "Cattleman's",
  #         "Panama",
  #         "Tophat"
  #       ]
  #     }
  #   JSON
  #
  # Load a \String:
  #   ruby = JSON.load(source)
  #   ruby # => {"name"=>"Dave", "age"=>40, "hats"=>["Cattleman's", "Panama", "Tophat"]}
  #
  # Load an \IO object:
  #   require 'stringio'
  #   object = JSON.load(StringIO.new(source))
  #   object # => {"name"=>"Dave", "age"=>40, "hats"=>["Cattleman's", "Panama", "Tophat"]}
  #
  # Load a \File object:
  #   path = 't.json'
  #   File.write(path, source)
  #   File.open(path) do |file|
  #     JSON.load(file)
  #   end # => {"name"=>"Dave", "age"=>40, "hats"=>["Cattleman's", "Panama", "Tophat"]}
  #
  # ---
  #
  # When +proc+ is given:
  # - Modifies +source+ as above.
  # - Gets the +result+ from calling <tt>parse(source, opts)</tt>.
  # - Recursively calls <tt>proc(result)</tt>.
  # - Returns the final result.
  #
  # Example:
  #   require 'json'
  #
  #   # Some classes for the example.
  #   class Base
  #     def initialize(attributes)
  #       @attributes = attributes
  #     end
  #   end
  #   class User    < Base; end
  #   class Account < Base; end
  #   class Admin   < Base; end
  #   # The JSON source.
  #   json = <<-EOF
  #   {
  #     "users": [
  #         {"type": "User", "username": "jane", "email": "jane@example.com"},
  #         {"type": "User", "username": "john", "email": "john@example.com"}
  #     ],
  #     "accounts": [
  #         {"account": {"type": "Account", "paid": true, "account_id": "1234"}},
  #         {"account": {"type": "Account", "paid": false, "account_id": "1235"}}
  #     ],
  #     "admins": {"type": "Admin", "password": "0wn3d"}
  #   }
  #   EOF
  #   # Deserializer method.
  #   def deserialize_obj(obj, safe_types = %w(User Account Admin))
  #     type = obj.is_a?(Hash) && obj["type"]
  #     safe_types.include?(type) ? Object.const_get(type).new(obj) : obj
  #   end
  #   # Call to JSON.load
  #   ruby = JSON.load(json, proc {|obj|
  #     case obj
  #     when Hash
  #       obj.each {|k, v| obj[k] = deserialize_obj v }
  #     when Array
  #       obj.map! {|v| deserialize_obj v }
  #     end
  #   })
  #   pp ruby
  # Output:
  #   {"users"=>
  #      [#<User:0x00000000064c4c98
  #        @attributes=
  #          {"type"=>"User", "username"=>"jane", "email"=>"jane@example.com"}>,
  #        #<User:0x00000000064c4bd0
  #        @attributes=
  #          {"type"=>"User", "username"=>"john", "email"=>"john@example.com"}>],
  #    "accounts"=>
  #      [{"account"=>
  #          #<Account:0x00000000064c4928
  #          @attributes={"type"=>"Account", "paid"=>true, "account_id"=>"1234"}>},
  #       {"account"=>
  #          #<Account:0x00000000064c4680
  #          @attributes={"type"=>"Account", "paid"=>false, "account_id"=>"1235"}>}],
  #    "admins"=>
  #      #<Admin:0x00000000064c41f8
  #      @attributes={"type"=>"Admin", "password"=>"0wn3d"}>}
  #
  def load(source, proc = nil, options = nil)
    opts = if options.nil?
      _load_default_options
    else
      _load_default_options.merge(options)
    end

    unless source.is_a?(String)
      if source.respond_to? :to_str
        source = source.to_str
      elsif source.respond_to? :to_io
        source = source.to_io.read
      elsif source.respond_to?(:read)
        source = source.read
      end
    end

    if opts[:allow_blank] && (source.nil? || source.empty?)
      source = 'null'
    end
    result = parse(source, opts)
    recurse_proc(result, &proc) if proc
    result
  end

  # Recursively calls passed _Proc_ if the parsed data structure is an _Array_ or _Hash_
  def recurse_proc(result, &proc) # :nodoc:
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

  # Sets or returns the default options for the JSON.dump method.
  # Initially:
  #   opts = JSON.dump_default_options
  #   opts # => {:max_nesting=>false, :allow_nan=>true}
  deprecated_singleton_attr_accessor :dump_default_options
  @dump_default_options = {
    :max_nesting => false,
    :allow_nan   => true,
  }

  # :call-seq:
  #   JSON.dump(obj, io = nil, limit = nil)
  #
  # Dumps +obj+ as a \JSON string, i.e. calls generate on the object and returns the result.
  #
  # The default options can be changed via method JSON.dump_default_options.
  #
  # - Argument +io+, if given, should respond to method +write+;
  #   the \JSON \String is written to +io+, and +io+ is returned.
  #   If +io+ is not given, the \JSON \String is returned.
  # - Argument +limit+, if given, is passed to JSON.generate as option +max_nesting+.
  #
  # ---
  #
  # When argument +io+ is not given, returns the \JSON \String generated from +obj+:
  #   obj = {foo: [0, 1], bar: {baz: 2, bat: 3}, bam: :bad}
  #   json = JSON.dump(obj)
  #   json # => "{\"foo\":[0,1],\"bar\":{\"baz\":2,\"bat\":3},\"bam\":\"bad\"}"
  #
  # When argument +io+ is given, writes the \JSON \String to +io+ and returns +io+:
  #   path = 't.json'
  #   File.open(path, 'w') do |file|
  #     JSON.dump(obj, file)
  #   end # => #<File:t.json (closed)>
  #   puts File.read(path)
  # Output:
  #   {"foo":[0,1],"bar":{"baz":2,"bat":3},"bam":"bad"}
  def dump(obj, anIO = nil, limit = nil, kwargs = nil)
    if kwargs.nil?
      if limit.nil?
        if anIO.is_a?(Hash)
          kwargs = anIO
          anIO = nil
        end
      elsif limit.is_a?(Hash)
        kwargs = limit
        limit = nil
      end
    end

    unless anIO.nil?
      if anIO.respond_to?(:to_io)
        anIO = anIO.to_io
      elsif limit.nil? && !anIO.respond_to?(:write)
        anIO, limit = nil, anIO
      end
    end

    opts = JSON._dump_default_options
    opts = opts.merge(:max_nesting => limit) if limit
    opts = opts.merge(kwargs) if kwargs

    begin
      State.generate(obj, opts, anIO)
    rescue JSON::NestingError
      raise ArgumentError, "exceed depth limit"
    end
  end

  # Encodes string using String.encode.
  def self.iconv(to, from, string)
    string.encode(to, from)
  end

  # JSON::Coder holds a parser and generator configuration.
  #
  #   module MyApp
  #     JSONC_CODER = JSON::Coder.new(
  #       allow_trailing_comma: true
  #     )
  #   end
  #
  #   MyApp::JSONC_CODER.load(document)
  #
  class Coder
    # :call-seq:
    #   JSON.new(options = nil, &block)
    #
    # Argument +options+, if given, contains a \Hash of options for both parsing and generating.
    # See {Parsing Options}[#module-JSON-label-Parsing+Options], and {Generating Options}[#module-JSON-label-Generating+Options].
    #
    # For generation, the <tt>strict: true</tt> option is always set. When a Ruby object with no native \JSON counterpart is
    # encoutered, the block provided to the initialize method is invoked, and must return a Ruby object that has a native
    # \JSON counterpart:
    #
    #  module MyApp
    #    API_JSON_CODER = JSON::Coder.new do |object|
    #      case object
    #      when Time
    #        object.iso8601(3)
    #      else
    #        object # Unknown type, will raise
    #      end
    #    end
    #  end
    #
    #  puts MyApp::API_JSON_CODER.dump(Time.now.utc) # => "2025-01-21T08:41:44.286Z"
    #
    def initialize(options = nil, &as_json)
      if options.nil?
        options = { strict: true }
      else
        options = options.dup
        options[:strict] = true
      end
      options[:as_json] = as_json if as_json
      options[:create_additions] = false unless options.key?(:create_additions)

      @state = State.new(options).freeze
      @parser_config = Ext::Parser::Config.new(options)
    end

    # call-seq:
    #   dump(object) -> String
    #   dump(object, io) -> io
    #
    # Serialize the given object into a \JSON document.
    def dump(object, io = nil)
      @state.generate_new(object, io)
    end
    alias_method :generate, :dump

    # call-seq:
    #   load(string) -> Object
    #
    # Parse the given \JSON document and return an equivalent Ruby object.
    def load(source)
      @parser_config.parse(source)
    end
    alias_method :parse, :load

    # call-seq:
    #   load(path) -> Object
    #
    # Parse the given \JSON document and return an equivalent Ruby object.
    def load_file(path)
      load(File.read(path, encoding: Encoding::UTF_8))
    end
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
    if object.is_a?(String)
      return JSON.parse(object, args.first)
    elsif object.respond_to?(:to_str)
      str = object.to_str
      if str.is_a?(String)
        return JSON.parse(object.to_str, args.first)
      end
    end

    JSON.generate(object, args.first)
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
