# Cheap-n-cheerful HTML page template system. You create a
# template containing:
#
# * variable names between percent signs (<tt>%fred%</tt>)
# * blocks of repeating stuff:
#
#     START:key
#       ... stuff
#     END:key
#
# You feed the code a hash. For simple variables, the values
# are resolved directly from the hash. For blocks, the hash entry
# corresponding to +key+ will be an array of hashes. The block will
# be generated once for each entry. Blocks can be nested arbitrarily
# deeply.
#
# The template may also contain
#
#   IF:key
#     ... stuff
#   ENDIF:key
#
# _stuff_ will only be included in the output if the corresponding
# key is set in the value hash.
#
# Usage:  Given a set of templates <tt>T1, T2,</tt> etc
#
#            values = { "name" => "Dave", state => "TX" }
#
#            t = TemplatePage.new(T1, T2, T3)
#            File.open(name, "w") {|f| t.write_html_on(f, values)}
#         or
#            res = ''
#            t.write_html_on(res, values)
#
#

class TemplatePage

  ##########
  # A context holds a stack of key/value pairs (like a symbol
  # table). When asked to resolve a key, it first searches the top of
  # the stack, then the next level, and so on until it finds a match
  # (or runs out of entries)

  class Context
    def initialize
      @stack = []
    end

    def push(hash)
      @stack.push(hash)
    end

    def pop
      @stack.pop
    end

    # Find a scalar value, throwing an exception if not found. This
    # method is used when substituting the %xxx% constructs

    def find_scalar(key)
      @stack.reverse_each do |level|
        if val = level[key]
          return val unless val.kind_of? Array
        end
      end
      raise "Template error: can't find variable '#{key}'"
    end

    # Lookup any key in the stack of hashes

    def lookup(key)
      @stack.reverse_each do |level|
        val = level[key]
        return val if val
      end
      nil
    end
  end

  #########
  # Simple class to read lines out of a string

  class LineReader
    # we're initialized with an array of lines
    def initialize(lines)
      @lines = lines
    end

    # read the next line
    def read
      @lines.shift
    end

    # Return a list of lines up to the line that matches
    # a pattern. That last line is discarded.
    def read_up_to(pattern)
      res = []
      while line = read
        if pattern.match(line)
          return LineReader.new(res)
        else
          res << line
        end
      end
      raise "Missing end tag in template: #{pattern.source}"
    end

    # Return a copy of ourselves that can be modified without
    # affecting us
    def dup
      LineReader.new(@lines.dup)
    end
  end



  # +templates+ is an array of strings containing the templates.
  # We start at the first, and substitute in subsequent ones
  # where the string <tt>!INCLUDE!</tt> occurs. For example,
  # we could have the overall page template containing
  #
  #   <html><body>
  #     <h1>Master</h1>
  #     !INCLUDE!
  #   </bost></html>
  #
  # and substitute subpages in to it by passing [master, sub_page].
  # This gives us a cheap way of framing pages

  def initialize(*templates)
    result = "!INCLUDE!"
    templates.each do |content|
      result.sub!(/!INCLUDE!/, content)
    end
    @lines = LineReader.new(result.split($/))
  end

  # Render the templates into HTML, storing the result on +op+
  # using the method <tt><<</tt>. The <tt>value_hash</tt> contains
  # key/value pairs used to drive the substitution (as described above)

  def write_html_on(op, value_hash)
    @context = Context.new
    op << substitute_into(@lines, value_hash).tr("\000", '\\')
  end


  # Substitute a set of key/value pairs into the given template.
  # Keys with scalar values have them substituted directly into
  # the page. Those with array values invoke <tt>substitute_array</tt>
  # (below), which examples a block of the template once for each
  # row in the array.
  #
  # This routine also copes with the <tt>IF:</tt>_key_ directive,
  # removing chunks of the template if the corresponding key
  # does not appear in the hash, and the START: directive, which
  # loops its contents for each value in an array

  def substitute_into(lines, values)
    @context.push(values)
    skip_to = nil
    result = []

    while line = lines.read

      case line

      when /^IF:(\w+)/
        lines.read_up_to(/^ENDIF:#$1/) unless @context.lookup($1)

    when /^IFNOT:(\w+)/
        lines.read_up_to(/^ENDIF:#$1/) if @context.lookup($1)

      when /^ENDIF:/
        ;

      when /^START:(\w+)/
        tag = $1
        body = lines.read_up_to(/^END:#{tag}/)
        inner_values = @context.lookup(tag)
        raise "unknown tag: #{tag}" unless inner_values
        raise "not array: #{tag}"   unless inner_values.kind_of?(Array)
        inner_values.each do |vals|
          result << substitute_into(body.dup, vals)
        end
      else
        result << expand_line(line.dup)
      end
    end

    @context.pop

    result.join("\n")
  end

  # Given an individual line, we look for %xxx% constructs and
  # HREF:ref:name: constructs, substituting for each.

  def expand_line(line)
    # Generate a cross reference if a reference is given,
    # otherwise just fill in the name part

    line.gsub!(/HREF:(\w+?):(\w+?):/) {
      ref = @context.lookup($1)
      name = @context.find_scalar($2)

      if ref and !ref.kind_of?(Array)
	"<a href=\"#{ref}\">#{name}</a>"
      else
	name
      end
    }

    # Substitute in values for %xxx% constructs.  This is made complex
    # because the replacement string may contain characters that are
    # meaningful to the regexp (like \1)

    line = line.gsub(/%([a-zA-Z]\w*)%/) {
      val = @context.find_scalar($1)
      val.tr('\\', "\000")
    }


    line
  rescue Exception => e
    $stderr.puts "Error in template: #{e}"
    $stderr.puts "Original line: #{line}"
    exit
  end

end

