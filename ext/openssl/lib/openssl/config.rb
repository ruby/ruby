=begin
= Ruby-space definitions that completes C-space funcs for Config

= Info
  Copyright (C) 2010  Hiroshi Nakamura <nahi@ruby-lang.org>

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

=end

require 'stringio'

module OpenSSL
  ##
  # = OpenSSL::Config
  #
  # Configuration for the openssl library. See also
  # http://www.openssl.org/docs/apps/config.html
  #
  # Many system's installation of openssl library will land a default system
  # configuration. See the value of OpenSSL::Config::DEFAULT_CONFIG_FILE for
  # the location of the file for your host.
  #
  #
  class Config
    include Enumerable

    class << self

      ##
      # parse +str+ as a blob that is the contents of a configuration file.
      #
      # If the configuration file source is an IO, then use
      # OpenSSL::Config#parse_config instead
      def parse(str)
        c = new()
        parse_config(StringIO.new(str)).each do |section, hash|
          c[section] = hash
        end
        c
      end

      ##
      # load is an alias to OpenSSL::Config.new
      alias load new

      ##
      # parse the configuration data read from +io+
      #
      # raises ConfigError on invalid configuration data
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
        while definition = get_definition(io)
          definition = clear_comments(definition)
          next if definition.empty?
          if definition[0] == ?[
            if /\[([^\]]*)\]/ =~ definition
              section = $1.strip
              data[section] ||= {}
            else
              raise ConfigError, "missing close square bracket"
            end
          else
            if /\A([^:\s]*)(?:::([^:\s]*))?\s*=(.*)\z/ =~ definition
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

      def get_definition(io)
        if line = get_line(io)
          while /[^\\]\\\z/ =~ line
            if extra = get_line(io)
              line += extra
            else
              break
            end
          end
          return line.strip
        end
      end

      def get_line(io)
        if line = io.gets
          line.gsub(/[\r\n]*/, '')
        end
      end
    end

    ##
    # Construct a new instance of an openssl configuration (OpenSSL::Config)
    #
    # This can be used in contexts like OpenSSL::X509::ExtensionFactory.config=
    #
    # If optional parameter +filename+ is provided, then it is read in and
    # parsed.
    # 
    # This can raise IO exceptions based on the access or availability of
    # the file, or ConfigError on parsing of the configuration.
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
    # get the value of +key+ from +section+
    #
    #   c = OpenSSL::Config.load('foo.cnf')
    #    => #<OpenSSL::Config sections=["default"]> 
    #   puts c.to_s
    #     [ default ]
    #     foo=bar
    #
    #    => nil 
    #   c.get_value('default','foo')
    #    => "bar" 
    #
    def get_value(section, key)
      if section.nil?
        raise TypeError.new('nil not allowed')
      end
      section = 'default' if section.empty?
      get_key_string(section, key)
    end

    ##
    # this value getter is deprecated; See OpenSSL::Config#get_value instead
    def value(arg1, arg2 = nil)
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
    # set +key+ with +value+, in +section+
    #
    #   c = OpenSSL::Config.new
    #    => #<OpenSSL::Config sections=[]>
    #   puts c.to_s
    #
    #    => nil
    #   c.add_value('default', 'foo', 'bar')
    #    => "bar"
    #   puts c.to_s
    #     [ default ]
    #     foo=bar
    #
    #    => nil
    #
    def add_value(section, key, value)
      check_modify
      (@data[section] ||= {})[key] = value
    end

    ##
    # Get the +section+ from the current configuration
    #
    #   c = OpenSSL::Config.load('/home/vbatts/foo.cnf')
    #    => #<OpenSSL::Config sections=["default"]>
    #   puts c.to_s
    #    [ default ]
    #    foo=bar
    #
    #    => nil
    #   c['default']
    #    => {"foo"=>"bar"}
    #
    def [](section)
      @data[section] || {}
    end

    ##
    # Config#section is deprecated; use Config#[]
    def section(name)
      warn('Config#section is deprecated; use Config#[]')
      @data[name] || {}
    end

    ##
    # Set +section+ name with a Hash +pairs+
    #
    #   c = OpenSSL::Config.new
    #    => #<OpenSSL::Config sections=[]> 
    #   c['default'] = {"foo"=>"bar","baz"=>"buz"}
    #    => {"foo"=>"bar", "baz"=>"buz"} 
    #   puts c.to_s
    #    [ default ]
    #    foo=bar
    #    baz=buz
    #
    #    => nil
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
    #   c = OpenSSL::Config.new
    #    => #<OpenSSL::Config sections=[]>
    #   c['default'] = {"foo"=>"bar","baz"=>"buz"}
    #     => {"foo"=>"bar", "baz"=>"buz"}
    #   puts c.to_s
    #    [ default ]
    #    foo=bar
    #    baz=buz
    #
    #    => nil
    #   c1 = OpenSSL::Config.parse(c.to_s)
    #    => #<OpenSSL::Config sections=["default"]> 
    #   puts c1
    #    [ default ]
    #    foo=bar
    #    baz=buz
    #
    #    => nil
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
    # For a block. Receive the section and its Hash pairs for the current
    # configuration
    #
    #   c.each do |section, pairs|
    #     [...]
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
    # this class name, and the sections present
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
