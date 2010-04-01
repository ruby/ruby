##
# Methods for manipulating comment text

module RDoc::Text

  ##
  # Expands tab characters in +text+ to eight spaces

  def expand_tabs text
    expanded = []

    text.each_line do |line|
      line.gsub!(/^(.{8}*?)([^\t\r\n]{0,7})\t/) do
        "#{$1}#{$2}#{' ' * (8 - $2.size)}"
      end until line !~ /\t/

      expanded << line
    end

    expanded.join
  end

  ##
  # Flush +text+ left based on the shortest line

  def flush_left text
    indents = []

    text.each_line do |line|
      indents << (line =~ /[^\s]/ || 9999)
    end

    indent = indents.min

    flush = []

    text.each_line do |line|
      line[/^ {0,#{indent}}/] = ''
      flush << line
    end

    flush.join
  end

  ##
  # Convert a string in markup format into HTML.  Removes the first paragraph
  # tags if +remove_para+ is true.
  #
  # Requires the including class to implement #formatter

  def markup text
    document = parse text

    document.accept formatter
  end

  ##
  # Strips hashes, expands tabs then flushes +text+ to the left

  def normalize_comment text
    return text if text.empty?

    text = strip_hashes text
    text = expand_tabs text
    text = flush_left text
    strip_newlines text
  end

  ##
  # Normalizes +text+ then builds a RDoc::Markup::Document from it

  def parse text
    return text if RDoc::Markup::Document === text

    text = normalize_comment text

    return RDoc::Markup::Document.new if text =~ /\A\n*\z/

    RDoc::Markup::Parser.parse text
  rescue RDoc::Markup::Parser::Error => e
    $stderr.puts <<-EOF
While parsing markup, RDoc encountered a #{e.class}:

#{e}
\tfrom #{e.backtrace.join "\n\tfrom "}

---8<---
#{text}
---8<---

RDoc #{RDoc::VERSION}

Ruby #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL} #{RUBY_RELEASE_DATE}

Please file a bug report with the above information at:

http://rubyforge.org/tracker/?atid=2472&group_id=627&func=browse

    EOF
    raise
  end

  ##
  # Strips leading # characters from +text+

  def strip_hashes text
    return text if text =~ /^(?>\s*)[^\#]/
    text.gsub(/^\s*(#+)/) { $1.tr '#',' ' }
  end

  ##
  # Strips leading and trailing \n characters from +text+

  def strip_newlines text
    text.gsub(/\A\n*(.*?)\n*\z/m, '\1')
  end

  ##
  # Strips /* */ style comments

  def strip_stars text
    text = text.gsub %r%Document-method:\s+[\w:.#]+%, ''
    text.sub!  %r%/\*+%       do " " * $&.length end
    text.sub!  %r%\*+/%       do " " * $&.length end
    text.gsub! %r%^[ \t]*\*%m do " " * $&.length end
    text
  end

end

