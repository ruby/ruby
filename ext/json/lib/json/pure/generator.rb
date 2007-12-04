module JSON
  MAP = {
    "\x0" => '\u0000',
    "\x1" => '\u0001',
    "\x2" => '\u0002',
    "\x3" => '\u0003',
    "\x4" => '\u0004',
    "\x5" => '\u0005',
    "\x6" => '\u0006',
    "\x7" => '\u0007',
    "\b"  =>  '\b',
    "\t"  =>  '\t',
    "\n"  =>  '\n',
    "\xb" => '\u000b',
    "\f"  =>  '\f',
    "\r"  =>  '\r',
    "\xe" => '\u000e',
    "\xf" => '\u000f',
    "\x10" => '\u0010',
    "\x11" => '\u0011',
    "\x12" => '\u0012',
    "\x13" => '\u0013',
    "\x14" => '\u0014',
    "\x15" => '\u0015',
    "\x16" => '\u0016',
    "\x17" => '\u0017',
    "\x18" => '\u0018',
    "\x19" => '\u0019',
    "\x1a" => '\u001a',
    "\x1b" => '\u001b',
    "\x1c" => '\u001c',
    "\x1d" => '\u001d',
    "\x1e" => '\u001e',
    "\x1f" => '\u001f',
    '"'   =>  '\"',
    '\\'  =>  '\\\\',
    '/'   =>  '\/',
  } # :nodoc:

  # Convert a UTF8 encoded Ruby string _string_ to a JSON string, encoded with
  # UTF16 big endian characters as \u????, and return it.
  def utf8_to_json(string) # :nodoc:
    string = string.gsub(/["\\\/\x0-\x1f]/) { |c| MAP[c] }
    string.gsub!(/(
                    (?:
                      [\xc2-\xdf][\x80-\xbf]    |
                      [\xe0-\xef][\x80-\xbf]{2} |
                      [\xf0-\xf4][\x80-\xbf]{3}
                    )+ |
                    [\x80-\xc1\xf5-\xff]       # invalid
                  )/nx) { |c|
      c.size == 1 and raise GeneratorError, "invalid utf8 byte: '#{c}'"
      s = JSON::UTF8toUTF16.iconv(c).unpack('H*')[0]
      s.gsub!(/.{4}/n, '\\\\u\&')
    }
    string
  rescue Iconv::Failure => e
    raise GeneratorError, "Caught #{e.class}: #{e}"
  end
  module_function :utf8_to_json

  module Pure
    module Generator
      # This class is used to create State instances, that are use to hold data
      # while generating a JSON text from a a Ruby data structure.
      class State
        # Creates a State object from _opts_, which ought to be Hash to create
        # a new State instance configured by _opts_, something else to create
        # an unconfigured instance. If _opts_ is a State object, it is just
        # returned.
        def self.from_state(opts)
          case opts
          when self
            opts
          when Hash
            new(opts)
          else
            new
          end
        end

        # Instantiates a new State object, configured by _opts_.
        #
        # _opts_ can have the following keys:
        #
        # * *indent*: a string used to indent levels (default: ''),
        # * *space*: a string that is put after, a : or , delimiter (default: ''),
        # * *space_before*: a string that is put before a : pair delimiter (default: ''),
        # * *object_nl*: a string that is put at the end of a JSON object (default: ''), 
        # * *array_nl*: a string that is put at the end of a JSON array (default: ''),
        # * *check_circular*: true if checking for circular data structures
        #   should be done (the default), false otherwise.
        # * *check_circular*: true if checking for circular data structures
        #   should be done, false (the default) otherwise.
        # * *allow_nan*: true if NaN, Infinity, and -Infinity should be
        #   generated, otherwise an exception is thrown, if these values are
        #   encountered. This options defaults to false.
        def initialize(opts = {})
          @seen = {}
          @indent         = ''
          @space          = ''
          @space_before   = ''
          @object_nl      = ''
          @array_nl       = ''
          @check_circular = true
          @allow_nan      = false
          configure opts
        end

        # This string is used to indent levels in the JSON text.
        attr_accessor :indent

        # This string is used to insert a space between the tokens in a JSON
        # string.
        attr_accessor :space

        # This string is used to insert a space before the ':' in JSON objects.
        attr_accessor :space_before

        # This string is put at the end of a line that holds a JSON object (or
        # Hash).
        attr_accessor :object_nl

        # This string is put at the end of a line that holds a JSON array.
        attr_accessor :array_nl

        # This integer returns the maximum level of data structure nesting in
        # the generated JSON, max_nesting = 0 if no maximum is checked.
        attr_accessor :max_nesting

        def check_max_nesting(depth) # :nodoc:
          return if @max_nesting.zero?
          current_nesting = depth + 1
          current_nesting > @max_nesting and
            raise NestingError, "nesting of #{current_nesting} is too deep"
        end

        # Returns true, if circular data structures should be checked,
        # otherwise returns false.
        def check_circular?
          @check_circular
        end

        # Returns true if NaN, Infinity, and -Infinity should be considered as
        # valid JSON and output.
        def allow_nan?
          @allow_nan
        end

        # Returns _true_, if _object_ was already seen during this generating
        # run. 
        def seen?(object)
          @seen.key?(object.__id__)
        end

        # Remember _object_, to find out if it was already encountered (if a
        # cyclic data structure is if a cyclic data structure is rendered). 
        def remember(object)
          @seen[object.__id__] = true
        end

        # Forget _object_ for this generating run.
        def forget(object)
          @seen.delete object.__id__
        end

        # Configure this State instance with the Hash _opts_, and return
        # itself.
        def configure(opts)
          @indent         = opts[:indent] if opts.key?(:indent)
          @space          = opts[:space] if opts.key?(:space)
          @space_before   = opts[:space_before] if opts.key?(:space_before)
          @object_nl      = opts[:object_nl] if opts.key?(:object_nl)
          @array_nl       = opts[:array_nl] if opts.key?(:array_nl)
          @check_circular = !!opts[:check_circular] if opts.key?(:check_circular)
          @allow_nan      = !!opts[:allow_nan] if opts.key?(:allow_nan)
          if !opts.key?(:max_nesting) # defaults to 19
            @max_nesting = 19
          elsif opts[:max_nesting]
            @max_nesting = opts[:max_nesting]
          else
            @max_nesting = 0
          end
          self
        end

        # Returns the configuration instance variables as a hash, that can be
        # passed to the configure method.
        def to_h
          result = {}
          for iv in %w[indent space space_before object_nl array_nl check_circular allow_nan max_nesting]
            result[iv.intern] = instance_variable_get("@#{iv}")
          end
          result
        end
      end

      module GeneratorMethods
        module Object
          # Converts this object to a string (calling #to_s), converts
          # it to a JSON string, and returns the result. This is a fallback, if no
          # special method #to_json was defined for some object.
          def to_json(*) to_s.to_json end
        end

        module Hash
          # Returns a JSON string containing a JSON object, that is unparsed from
          # this Hash instance.
          # _state_ is a JSON::State object, that can also be used to configure the
          # produced JSON string output further.
          # _depth_ is used to find out nesting depth, to indent accordingly.
          def to_json(state = nil, depth = 0, *)
            if state
              state = JSON.state.from_state(state)
              state.check_max_nesting(depth)
              json_check_circular(state) { json_transform(state, depth) }
            else
              json_transform(state, depth)
            end
          end

          private

          def json_check_circular(state)
            if state and state.check_circular?
              state.seen?(self) and raise JSON::CircularDatastructure,
                  "circular data structures not supported!"
              state.remember self
            end
            yield
          ensure
            state and state.forget self
          end

          def json_shift(state, depth)
            state and not state.object_nl.empty? or return ''
            state.indent * depth
          end

          def json_transform(state, depth)
            delim = ','
            delim << state.object_nl if state
            result = '{'
            result << state.object_nl if state
            result << map { |key,value|
              s = json_shift(state, depth + 1)
              s << key.to_s.to_json(state, depth + 1)
              s << state.space_before if state
              s << ':'
              s << state.space if state
              s << value.to_json(state, depth + 1)
            }.join(delim)
            result << state.object_nl if state
            result << json_shift(state, depth)
            result << '}'
            result
          end
        end

        module Array
          # Returns a JSON string containing a JSON array, that is unparsed from
          # this Array instance.
          # _state_ is a JSON::State object, that can also be used to configure the
          # produced JSON string output further.
          # _depth_ is used to find out nesting depth, to indent accordingly.
          def to_json(state = nil, depth = 0, *)
            if state
              state = JSON.state.from_state(state)
              state.check_max_nesting(depth)
              json_check_circular(state) { json_transform(state, depth) }
            else
              json_transform(state, depth)
            end
          end

          private

          def json_check_circular(state)
            if state and state.check_circular?
              state.seen?(self) and raise JSON::CircularDatastructure,
                "circular data structures not supported!"
              state.remember self
            end
            yield
          ensure
            state and state.forget self
          end

          def json_shift(state, depth)
            state and not state.array_nl.empty? or return ''
            state.indent * depth
          end

          def json_transform(state, depth)
            delim = ','
            delim << state.array_nl if state
            result = '['
            result << state.array_nl if state
            result << map { |value|
              json_shift(state, depth + 1) << value.to_json(state, depth + 1)
            }.join(delim)
            result << state.array_nl if state
            result << json_shift(state, depth) 
            result << ']'
            result
          end
        end

        module Integer
          # Returns a JSON string representation for this Integer number.
          def to_json(*) to_s end
        end

        module Float
          # Returns a JSON string representation for this Float number.
          def to_json(state = nil, *)
            case
            when infinite?
              if !state || state.allow_nan?
                to_s
              else
                raise GeneratorError, "#{self} not allowed in JSON"
              end
            when nan?
              if !state || state.allow_nan?
                to_s
              else
                raise GeneratorError, "#{self} not allowed in JSON"
              end
            else
              to_s
            end
          end
        end

        module String
          # This string should be encoded with UTF-8 A call to this method
          # returns a JSON string encoded with UTF16 big endian characters as
          # \u????.
          def to_json(*)
            '"' << JSON.utf8_to_json(self) << '"'
          end

          # Module that holds the extinding methods if, the String module is
          # included.
          module Extend
            # Raw Strings are JSON Objects (the raw bytes are stored in an array for the
            # key "raw"). The Ruby String can be created by this module method.
            def json_create(o)
              o['raw'].pack('C*')
            end
          end

          # Extends _modul_ with the String::Extend module.
          def self.included(modul)
            modul.extend Extend
          end

          # This method creates a raw object hash, that can be nested into
          # other data structures and will be unparsed as a raw string. This
          # method should be used, if you want to convert raw strings to JSON
          # instead of UTF-8 strings, e. g. binary data.
          def to_json_raw_object
            {
              JSON.create_id  => self.class.name,
              'raw'           => self.unpack('C*'),
            }
          end

          # This method creates a JSON text from the result of
          # a call to to_json_raw_object of this String.
          def to_json_raw(*args)
            to_json_raw_object.to_json(*args)
          end
        end

        module TrueClass
          # Returns a JSON string for true: 'true'.
          def to_json(*) 'true' end
        end

        module FalseClass
          # Returns a JSON string for false: 'false'.
          def to_json(*) 'false' end
        end

        module NilClass
          # Returns a JSON string for nil: 'null'.
          def to_json(*) 'null' end
        end
      end
    end
  end
end
