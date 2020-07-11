# frozen_string_literal: false
=begin
= Ruby-space definitions that completes C-space funcs for Config

= Info
  Copyright (C) 2010  Hiroshi Nakamura <nahi@ruby-lang.org>

= Licence
  This program is licensed under the same licence as Ruby.
  (See the file 'LICENCE'.)

=end

require 'stringio'

module OpenSSL
  ##
  # = OpenSSL::Config
  #
  # Configuration for the openssl library.
  #
  # Many system's installation of openssl library will depend on your system
  # configuration. See the value of OpenSSL::Config::DEFAULT_CONFIG_FILE for
  # the location of the file for your host.
  #
  # See also http://www.openssl.org/docs/apps/config.html
  class Config
    include Enumerable

    class << self

      ##
      # Parses a given _string_ as a blob that contains configuration for
      # OpenSSL.
      #
      # If the source of the IO is a file, then consider using #parse_config.
      def parse(string)
        c = new()
        parse_config(StringIO.new(string)).each do |section, hash|
          c[section] = hash
        end
        c
      end

      ##
      # load is an alias to ::new
      alias load new

      ##
      # Parses the configuration data read from _io_, see also #parse.
      #
      # Raises a ConfigError on invalid configuration data.
      def parse_config(io)
        begin
          parse_config_lines(io)
        rescue ConfigError => e
          e.message.replace("error in line #{io.lineno}: " + e.message)
          raise
        end
      end

      def get_key_string(data, section, key) # :nodoc:
        if v = data[section] && data[section][key]
          return v
        elsif section == 'ENV'
          if v = ENV[key]
            return v
          end
        end
        if v = data['default'] && data['default'][key]
          return v
        end
      end

    private

      def parse_config_lines(io)
        section = 'default'
        data = {section => {}}
        io_stack = [io]
        while definition = get_definition(io_stack)
          definition = clear_comments(definition)
          next if definition.empty?
          case definition
          when /\A\[/
            if /\[([^\]]*)\]/ =~ definition
              section = $1.strip
              data[section] ||= {}
            else
              raise ConfigError, "missing close square bracket"
            end
          when /\A\.include (\s*=\s*)?(.+)\z/
            path = $2
            if File.directory?(path)
              files = Dir.glob(File.join(path, "*.{cnf,conf}"), File::FNM_EXTGLOB)
            else
              files = [path]
            end

            files.each do |filename|
              begin
                io_stack << StringIO.new(File.read(filename))
              rescue
                raise ConfigError, "could not include file '%s'" % filename
              end
            end
          when /\A([^:\s]*)(?:::([^:\s]*))?\s*=(.*)\z/
            if $2
              section = $1
              key = $2
            else
              key = $1
            end
            value = unescape_value(data, section, $3)
            (data[section] ||= {})[key] = value.strip
          else
            raise ConfigError, "missing equal sign"
          end
        end
        data
      end

      # escape with backslash
      QUOTE_REGEXP_SQ = /\A([^'\\]*(?:\\.[^'\\]*)*)'/
      # escape with backslash and doubled dq
      QUOTE_REGEXP_DQ = /\A([^"\\]*(?:""[^"\\]*|\\.[^"\\]*)*)"/
      # escaped char map
      ESCAPE_MAP = {
        "r" => "\r",
        "n" => "\n",
        "b" => "\b",
        "t" => "\t",
      }

      def unescape_value(data, section, value)
        scanned = []
        while m = value.match(/['"\\$]/)
          scanned << m.pre_match
          c = m[0]
          value = m.post_match
          case c
          when "'"
            if m = value.match(QUOTE_REGEXP_SQ)
              scanned << m[1].gsub(/\\(.)/, '\\1')
              value = m.post_match
            else
              break
            end
          when '"'
            if m = value.match(QUOTE_REGEXP_DQ)
              scanned << m[1].gsub(/""/, '').gsub(/\\(.)/, '\\1')
              value = m.post_match
            else
              break
            end
          when "\\"
            c = value.slice!(0, 1)
            scanned << (ESCAPE_MAP[c] || c)
          when "$"
            ref, value = extract_reference(value)
            refsec = section
            if ref.index('::')
              refsec, ref = ref.split('::', 2)
            end
            if v = get_key_string(data, refsec, ref)
              scanned << v
            else
              raise ConfigError, "variable has no value"
            end
          else
            raise 'must not reaced'
          end
        end
        scanned << value
        scanned.join
      end

      def extract_reference(value)
        rest = ''
        if m = value.match(/\(([^)]*)\)|\{([^}]*)\}/)
          value = m[1] || m[2]
          rest = m.post_match
        elsif [?(, ?{].include?(value[0])
          raise ConfigError, "no close brace"
        end
        if m = value.match(/[a-zA-Z0-9_]*(?:::[a-zA-Z0-9_]*)?/)
          return m[0], m.post_match + rest
        else
          raise
        end
      end

      def clear_comments(line)
        # FCOMMENT
        if m = line.match(/\A([\t\n\f ]*);.*\z/)
          return m[1]
        end
        # COMMENT
        scanned = []
        while m = line.match(/[#'"\\]/)
          scanned << m.pre_match
          c = m[0]
          line = m.post_match
          case c
          when '#'
            line = nil
            break
          when "'", '"'
            regexp = (c == "'") ? QUOTE_REGEXP_SQ : QUOTE_REGEXP_DQ
            scanned << c
            if m = line.match(regexp)
              scanned << m[0]
              line = m.post_match
            else
              scanned << line
              line = nil
              break
            end
          when "\\"
            scanned << c
            scanned << line.slice!(0, 1)
          else
            raise 'must not reaced'
          end
        end
        scanned << line
        scanned.join
      end

      def get_definition(io_stack)
        if line = get_line(io_stack)
          while /[^\\]\\\z/ =~ line
            if extra = get_line(io_stack)
              line += extra
            else
              break
            end
          end
          return line.strip
        end
      end

      def get_line(io_stack)
        while io = io_stack.last
          if line = io.gets
            return line.gsub(/[\r\n]*/, '')
          end
          io_stack.pop
        end
      end
    end

    ##
    # Creates an instance of OpenSSL's configuration class.
    #
    # This can be used in contexts like OpenSSL::X509::ExtensionFactory.config=
    #
    # If the optional _filename_ parameter is provided, then it is read in and
    # parsed via #parse_config.
    #
    # This can raise IO exceptions based on the access, or availability of the
    # file. A ConfigError exception may be raised depending on the validity of
    # the data being configured.
    #
    def initialize(filename = nil)
      @data = {}
      if filename
        File.open(filename.to_s) do |file|
          Config.parse_config(file).each do |section, hash|
            self[section] = hash
          end
        end
      end
    end

    ##
    # Gets the value of _key_ from the given _section_
    #
    # Given the following configurating file being loaded:
    #
    #   config = OpenSSL::Config.load('foo.cnf')
    #     #=> #<OpenSSL::Config sections=["default"]>
    #   puts config.to_s
    #     #=> [ default ]
    #     #   foo=bar
    #
    # You can get a specific value from the config if you know the _section_
    # and _key_ like so:
    #
    #   config.get_value('default','foo')
    #     #=> "bar"
    #
    def get_value(section, key)
      if section.nil?
        raise TypeError.new('nil not allowed')
      end
      section = 'default' if section.empty?
      get_key_string(section, key)
    end

    ##
    #
    # *Deprecated*
    #
    # Use #get_value instead
    def value(arg1, arg2 = nil) # :nodoc:
      warn('Config#value is deprecated; use Config#get_value')
      if arg2.nil?
        section, key = 'default', arg1
      else
        section, key = arg1, arg2
      end
      section ||= 'default'
      section = 'default' if section.empty?
      get_key_string(section, key)
    end

    ##
    # Set the target _key_ with a given _value_ under a specific _section_.
    #
    # Given the following configurating file being loaded:
    #
    #   config = OpenSSL::Config.load('foo.cnf')
    #     #=> #<OpenSSL::Config sections=["default"]>
    #   puts config.to_s
    #     #=> [ default ]
    #     #   foo=bar
    #
    # You can set the value of _foo_ under the _default_ section to a new
    # value:
    #
    #   config.add_value('default', 'foo', 'buzz')
    #     #=> "buzz"
    #   puts config.to_s
    #     #=> [ default ]
    #     #   foo=buzz
    #
    def add_value(section, key, value)
      check_modify
      (@data[section] ||= {})[key] = value
    end

    ##
    # Get a specific _section_ from the current configuration
    #
    # Given the following configurating file being loaded:
    #
    #   config = OpenSSL::Config.load('foo.cnf')
    #     #=> #<OpenSSL::Config sections=["default"]>
    #   puts config.to_s
    #     #=> [ default ]
    #     #   foo=bar
    #
    # You can get a hash of the specific section like so:
    #
    #   config['default']
    #     #=> {"foo"=>"bar"}
    #
    def [](section)
      @data[section] || {}
    end

    ##
    # Deprecated
    #
    # Use #[] instead
    def section(name) # :nodoc:
      warn('Config#section is deprecated; use Config#[]')
      @data[name] || {}
    end

    ##
    # Sets a specific _section_ name with a Hash _pairs_.
    #
    # Given the following configuration being created:
    #
    #   config = OpenSSL::Config.new
    #     #=> #<OpenSSL::Config sections=[]>
    #   config['default'] = {"foo"=>"bar","baz"=>"buz"}
    #     #=> {"foo"=>"bar", "baz"=>"buz"}
    #   puts config.to_s
    #     #=> [ default ]
    #     #   foo=bar
    #     #   baz=buz
    #
    # It's important to note that this will essentially merge any of the keys
    # in _pairs_ with the existing _section_. For example:
    #
    #   config['default']
    #     #=> {"foo"=>"bar", "baz"=>"buz"}
    #   config['default'] = {"foo" => "changed"}
    #     #=> {"foo"=>"changed"}
    #   config['default']
    #     #=> {"foo"=>"changed", "baz"=>"buz"}
    #
    def []=(section, pairs)
      check_modify
      @data[section] ||= {}
      pairs.each do |key, value|
        self.add_value(section, key, value)
      end
    end

    ##
    # Get the names of all sections in the current configuration
    def sections
      @data.keys
    end

    ##
    # Get the parsable form of the current configuration
    #
    # Given the following configuration being created:
    #
    #   config = OpenSSL::Config.new
    #     #=> #<OpenSSL::Config sections=[]>
    #   config['default'] = {"foo"=>"bar","baz"=>"buz"}
    #     #=> {"foo"=>"bar", "baz"=>"buz"}
    #   puts config.to_s
    #     #=> [ default ]
    #     #   foo=bar
    #     #   baz=buz
    #
    # You can parse get the serialized configuration using #to_s and then parse
    # it later:
    #
    #   serialized_config = config.to_s
    #   # much later...
    #   new_config = OpenSSL::Config.parse(serialized_config)
    #     #=> #<OpenSSL::Config sections=["default"]>
    #   puts new_config
    #     #=> [ default ]
    #         foo=bar
    #         baz=buz
    #
    def to_s
      ary = []
      @data.keys.sort.each do |section|
        ary << "[ #{section} ]\n"
        @data[section].keys.each do |key|
          ary << "#{key}=#{@data[section][key]}\n"
        end
        ary << "\n"
      end
      ary.join
    end

    ##
    # For a block.
    #
    # Receive the section and its pairs for the current configuration.
    #
    #   config.each do |section, key, value|
    #     # ...
    #   end
    #
    def each
      @data.each do |section, hash|
        hash.each do |key, value|
          yield [section, key, value]
        end
      end
    end

    ##
    # String representation of this configuration object, including the class
    # name and its sections.
    def inspect
      "#<#{self.class.name} sections=#{sections.inspect}>"
    end

  protected

    def data # :nodoc:
      @data
    end

  private

    def initialize_copy(other)
      @data = other.data.dup
    end

    def check_modify
      raise TypeError.new("Insecure: can't modify OpenSSL config") if frozen?
    end

    def get_key_string(section, key)
      Config.get_key_string(@data, section, key)
    end
  end
end
