# frozen_string_literal: true
module Psych
  ###
  # YAML event parser class.  This class parses a YAML document and calls
  # events on the handler that is passed to the constructor.  The events can
  # be used for things such as constructing a YAML AST or deserializing YAML
  # documents.  It can even be fed back to Psych::Emitter to emit the same
  # document that was parsed.
  #
  # See Psych::Handler for documentation on the events that Psych::Parser emits.
  #
  # Here is an example that prints out ever scalar found in a YAML document:
  #
  #   # Handler for detecting scalar values
  #   class ScalarHandler < Psych::Handler
  #     def scalar value, anchor, tag, plain, quoted, style
  #       puts value
  #     end
  #   end
  #
  #   parser = Psych::Parser.new(ScalarHandler.new)
  #   parser.parse(yaml_document)
  #
  # Here is an example that feeds the parser back in to Psych::Emitter.  The
  # YAML document is read from STDIN and written back out to STDERR:
  #
  #   parser = Psych::Parser.new(Psych::Emitter.new($stderr))
  #   parser.parse($stdin)
  #
  # Psych uses Psych::Parser in combination with Psych::TreeBuilder to
  # construct an AST of the parsed YAML document.

  class Parser
    class Mark < Struct.new(:index, :line, :column)
    end

    # The handler on which events will be called
    attr_accessor :handler

    # Set the encoding for this parser to +encoding+
    attr_writer :external_encoding

    ###
    # Creates a new Psych::Parser instance with +handler+.  YAML events will
    # be called on +handler+.  See Psych::Parser for more details.

    def initialize handler = Handler.new
      @handler = handler
      @external_encoding = ANY
    end

    ###
    # call-seq:
    #    parser.parse(yaml)
    #
    # Parse the YAML document contained in +yaml+.  Events will be called on
    # the handler set on the parser instance.
    #
    # See Psych::Parser and Psych::Parser#handler

    def parse yaml, path = yaml.respond_to?(:path) ? yaml.path : "<unknown>"
      _native_parse @handler, strip_bom(yaml), path
    end

    private

    BOM = {
      Encoding::UTF_8 => "\u{FEFF}".freeze,
      Encoding::UTF_16LE => "\u{FEFF}".encode(Encoding::UTF_16LE).freeze,
      Encoding::UTF_16BE => "\u{FEFF}".encode(Encoding::UTF_16BE).freeze,
    }.freeze
    private_constant :BOM

    # libyaml only skips a leading byte order mark when it detects the stream
    # encoding by itself.  Psych passes the encoding explicitly whenever it is
    # known, and on that path libyaml counts the BOM as a first-line character,
    # which shifts the column of every token on the first line and silently
    # terminates a block mapping at the second line [Bug #13615].
    def strip_bom yaml
      if String === yaml
        bom = BOM[yaml.encoding]
        return yaml[1..-1] if bom && yaml.start_with?(bom)
      elsif yaml.respond_to?(:read) && yaml.respond_to?(:external_encoding) &&
            yaml.respond_to?(:pos) && yaml.respond_to?(:seek)
        bom = BOM[yaml.external_encoding]
        skip_io_bom yaml, bom.b if bom
      end
      yaml
    end

    def skip_io_bom io, bom
      begin
        pos = io.pos
      rescue SystemCallError, IOError
        return # Not seekable; nothing has been consumed yet.
      end
      head = io.read(bom.bytesize)
      io.seek(pos, IO::SEEK_SET) if head && head.b != bom
    end
  end
end
