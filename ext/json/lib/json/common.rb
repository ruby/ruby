# frozen_string_literal: true

require 'json/version'

module JSON
  module ParserOptions # :nodoc:
    class << self
      def on_load(on_load, object_class, array_class)
        on_load = object_class_proc(object_class, on_load) if object_class
        on_load = array_class_proc(array_class, on_load) if array_class
        on_load
      end

      private

      def object_class_proc(object_class, on_load)
        ->(obj) do
          if Hash === obj
            object = object_class.new
            obj.each { |k, v| object[k] = v }
            obj = object
          end
          on_load.nil? ? obj : on_load.call(obj)
        end
      end

      def array_class_proc(array_class, on_load)
        ->(obj) do
          if Array === obj
            array = array_class.new
            obj.each { |v| array << v }
            obj = array
          end
          on_load.nil? ? obj : on_load.call(obj)
        end
      end
    end
  end

  private_constant :ParserOptions

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
    def [](object, opts = nil)
      opts ||= {}.freeze

      if object.is_a?(String)
        return JSON.parse(object, **opts)
      elsif object.respond_to?(:to_str)
        str = object.to_str
        if str.is_a?(String)
          return JSON.parse(str, **opts)
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

    # Set the module _generator_ to be used by JSON.
    def generator=(generator) # :nodoc:
      old, $VERBOSE = $VERBOSE, nil

      # The default proc used when the +sort_keys+ generation option is +true+.
      # It returns a new hash with the entries sorted by their keys.
      sort_keys_proc = ->(hash) { hash.sort.to_h }
      if defined?(::Ractor) && Ractor.respond_to?(:shareable_lambda)
        sort_keys_proc = Ractor.shareable_lambda(&sort_keys_proc)
      end
      generator::State.default_sort_keys_proc = sort_keys_proc

      @generator = generator
      if generator.const_defined?(:GeneratorMethods)
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
      end
      self.state = generator::State
      const_set :State, state
    ensure
      $VERBOSE = old
    end

    # Returns the JSON generator module that is used by JSON.
    attr_reader :generator

    # Sets or Returns the JSON generator state class that is used by JSON.
    attr_accessor :state

    private

    # Called from the extension when a hash has both string and symbol keys
    def on_mixed_keys_hash(hash)
      set = {}
      hash.each_key do |key|
        key_str = key.to_s

        if set[key_str]
          raise GeneratorError, "detected duplicate key #{key_str.inspect} in #{hash.inspect}"
        else
          set[key_str] = true
        end
      end
    end
  end

  NaN           = Float::NAN

  Infinity      = Float::INFINITY

  MinusInfinity = -Infinity

  # The base exception for JSON errors.
  class JSONError < StandardError; end

  # This exception is raised if a parser error occurs.
  class ParserError < JSONError
    # Line number where the parser encountered an error.
    # Is <tt>nil</tt> when raised by JSON::ResumableParser.
    attr_reader :line

    # Column number where the parser encountered an error.
    # Is <tt>nil</tt> when raised by JSON::ResumableParser.
    attr_reader :column

    # Returns a best effort JSONPath string representing where in the document
    # the parser encountered an error:
    #
    #   begin
    #     JSON.parse('{"articles": [ { "title": invalid } ]}')
    #   rescue JSON::ParserError => error
    #     error.json_path # => "$.articles[0].title"
    #   end
    def json_path
      return @json_path if String === @json_path

      if Array === @json_path
        path = build_json_path(@json_path)
        @json_path = path unless frozen?
        return path
      end
    end

    private

    def build_json_path(segments)
      error = false
      path = segments.filter_map do |segment|
        next if error

        case segment
        when Integer
          "[#{segment}]"
        when String, Symbol
          if segment.match?(/\A[a-zA-Z\$\_][a-zA-Z\$\_0-9]*\z/)
            ".#{segment}"
          else
            segment = segment.to_s.gsub(/["\\]/, { '"' => '\\"', '\\' => '\\\\' })
            %{["#{segment}"]}
          end
        else
          error = true
          nil
        end
      end.join
      "$#{path}".freeze
    end
  end

  # This exception is raised if the nesting of parsed data structures is too
  # deep.
  class NestingError < ParserError; end

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

  # Fragment of JSON document that is to be included as is:
  #   fragment = JSON::Fragment.new("[1, 2, 3]")
  #   JSON.generate({ count: 3, items: fragments })
  #
  # This allows to easily assemble multiple JSON fragments that have
  # been persisted somewhere without having to parse them nor resorting
  # to string interpolation.
  #
  # Note: no validation is performed on the provided string. It is the
  # responsibility of the caller to ensure the string contains valid JSON.
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
  #   # Raises JSON::ParserError unexpected character: 'invalid' at line 1 column 1 :
  #   JSON.parse('invalid')
  #
  def parse(source, on_load: nil, object_class: nil, array_class: nil, **options)
    if object_class || array_class
      on_load = ParserOptions.on_load(on_load, object_class, array_class)
    end

    options[:on_load] = on_load if on_load
    Parser.parse(source, options)
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
  def parse!(source, **options)
    parse(source, max_nesting: false, allow_nan: true, **options)
  end

  # :call-seq:
  #   JSON.load_file(path, **) -> object
  #
  # Calls:
  #   parse(File.read(path), **)
  #
  # See method #parse.
  def load_file(filespec, ...)
    parse(File.read(filespec, encoding: Encoding::UTF_8), ...)
  end

  # :call-seq:
  #   JSON.load_file!(path, **)
  #
  # Calls:
  #   JSON.parse!(File.read(path), **)
  #
  # See method #parse!
  def load_file!(filespec, ...)
    parse!(File.read(filespec, encoding: Encoding::UTF_8), ...)
  end

  # :call-seq:
  #   JSON.generate(obj, opts = nil) -> new_string
  #
  # Returns a \String containing the generated \JSON data.
  #
  # See also JSON.pretty_generate.
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
      State.generate(obj, opts.frozen? ? opts : opts.dup, nil)
    end
  end

  PRETTY_GENERATE_OPTIONS = {
    indent: '  ',
    space: ' ',
    object_nl: "\n",
    array_nl: "\n",
  }.freeze
  private_constant :PRETTY_GENERATE_OPTIONS

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
    return opts.generate(obj) if State === opts

    options = PRETTY_GENERATE_OPTIONS

    if opts
      unless opts.is_a?(Hash)
        if opts.respond_to? :to_hash
          opts = opts.to_hash
        elsif opts.respond_to? :to_h
          opts = opts.to_h
        else
          raise TypeError, "can't convert #{opts.class} into Hash"
        end
      end

      options = options.merge(opts)
    end

    State.generate(obj, options, nil)
  end

  # :call-seq:
  #   JSON.unsafe_load(source, options = {}) -> object
  #   JSON.unsafe_load(source, proc = nil, options = {}) -> object
  #
  # Returns the Ruby objects created by parsing the given +source+.
  #
  # BEWARE: This method is meant to deserialise data from trusted user input,
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
  #     obj
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
  def unsafe_load(source, proc = nil, **options)
    load(source, proc, max_nesting: false, **options)
  end

  # :call-seq:
  #   JSON.load(source, options = {}) -> object
  #   JSON.load(source, proc = nil, options = {}) -> object
  #
  # Returns the Ruby objects created by parsing the given +source+.
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
  #     obj
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
  def load(source, proc = nil, allow_blank: true, **options)
    unless source.is_a?(String)
      if source.respond_to? :to_str
        source = source.to_str
      elsif source.respond_to? :to_io
        source = source.to_io.read
      elsif source.respond_to?(:read)
        source = source.read
      end
    end

    if allow_blank && (source.nil? || (String === source && source.empty?))
      source = 'null'
    end

    if proc
      parse(source, allow_nan: true, on_load: proc.to_proc, **options)
    else
      parse(source, allow_nan: true, **options)
    end
  end

  # :call-seq:
  #   JSON.dump(obj, io = nil, options = nil)
  #
  # Dumps +obj+ as a \JSON string, i.e. calls generate on the object and returns the result.
  #
  # The default options can be changed via method JSON.dump_default_options.
  #
  # - Argument +io+, if given, should respond to method +write+;
  #   the \JSON \String is written to +io+, and +io+ is returned.
  #   If +io+ is not given, the \JSON \String is returned.
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
  def dump(obj, anIO = nil, kwargs = nil)
    if kwargs.nil?
      if anIO.is_a?(Hash)
        kwargs = anIO
        anIO = nil
      end
    end

    if anIO&.respond_to?(:to_io)
      anIO = anIO.to_io
    end

    opts = {
      allow_nan: true,
    }
    opts.merge!(kwargs) if kwargs

    State.generate(obj, opts, anIO)
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
    PARSER_OPTIONS = %i(
      max_nesting
      allow_nan
      allow_trailing_comma
      allow_comments
      allow_control_characters
      allow_invalid_escape
      symbolize_names
      freeze
      allow_duplicate_key
      decimal_class
    ).freeze
    private_constant :PARSER_OPTIONS

    EXCLUDED_GENERATOR_OPTIONS = (PARSER_OPTIONS - %i(
      max_nesting
      allow_nan
      allow_duplicate_key
    )).freeze
    private_constant :EXCLUDED_GENERATOR_OPTIONS

    # :call-seq:
    #   JSON.new(options = nil, &block)
    #
    # Argument +options+, if given, contains a \Hash of options for both parsing and generating.
    # See {Parsing Options}[rdoc-ref:JSON@Parsing+Options],
    # and {Generating Options}[rdoc-ref:JSON@Generating+Options].
    #
    # For generation, the <tt>strict: true</tt> option is always set. When a Ruby object with no native \JSON counterpart is
    # encountered, the block provided to the initialize method is invoked, and must return a Ruby object that has a native
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
    def initialize(object_class: nil, array_class: nil, on_load: nil, **options, &as_json)
      if object_class || array_class
        on_load = ParserOptions.on_load(on_load, object_class, array_class)
      end
      parser_options = options.slice(*PARSER_OPTIONS)
      parser_options[:on_load] = on_load if on_load
      @parser_config = Ext::Parser::Config.new(parser_options).freeze

      generator_options = options.reject { |k, _| EXCLUDED_GENERATOR_OPTIONS.include?(k) }
      @state = State.new(
        **generator_options,
        strict: true,
        as_json: as_json,
      ).freeze
    end

    # call-seq:
    #   dump(object) -> String
    #   dump(object, io) -> io
    #
    # Serialize the given object into a \JSON document.
    def dump(object, io = nil)
      @state.generate(object, io)
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

  module GeneratorMethods
    # call-seq: to_json(*)
    #
    # Converts this object into a JSON string.
    # If this object doesn't directly maps to a JSON native type,
    # first convert it to a string (calling #to_s), then converts
    # it to a JSON string, and returns the result.
    # This is a fallback, if no special method #to_json was defined for some object.
    def to_json(state = nil, *)
      obj = case self
      when nil, false, true, Integer, Float, Array, Hash
        self
      else
        "#{self}"
      end

      if state.nil?
        JSON::State._generate_no_fallback(obj, nil, nil)
      else
        JSON::State.from_state(state)._generate_no_fallback(obj)
      end
    end
  end
end

module ::Kernel
  private

  # If _object_ is string-like, parse the string and return the parsed result as
  # a Ruby data structure. Otherwise, generate a JSON text from the Ruby data
  # structure object and return it.
  #
  # The _opts_ argument is passed through to generate/parse respectively. See
  # generate and parse for their documentation.
  def JSON(object, opts = nil)
    JSON[object, opts]
  end
end

class Object
  include JSON::GeneratorMethods
end
