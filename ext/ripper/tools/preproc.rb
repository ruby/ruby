# $Id$

require 'stringio'
require 'optparse'

def main
  output = nil
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0)} [--output=PATH] <parse.y>"
  parser.on('--output=PATH', 'An output file.') {|path|
    output = path
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit 0
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit 1
  end
  unless ARGV.size == 1
    $stderr.puts "wrong number of arguments (#{ARGV.size} for 1)"
    exit 1
  end
  out = StringIO.new
  File.open(ARGV[0]) {|f|
    prelude f, out
    grammar f, out
    usercode f, out
  }
  if output
    File.open(output, 'w') {|f|
      f.write out.string
    }
  else
    print out.string
  end
end

def prelude(f, out)
  while line = f.gets
    case line
    when %r</\*%%%\*/>
      out.puts '/*'
    when %r</\*%>
      out.puts '*/'
    when %r<%\*/>
      out.puts
    when /\A%%/
      out.puts '%%'
      return
    when /\A%token/
      out.puts line.sub(/<\w+>/, '<val>')
    when /\A%type/
      out.puts line.sub(/<\w+>/, '<val>')
    else
      out.print line
    end
  end
end

def grammar(f, out)
  while line = f.gets
    case line
    when %r</\*%%%\*/>
      out.puts '#if 0'
    when %r</\*%c%\*/>
      out.puts '/*'
    when %r</\*%c>
      out.puts '*/'
    when %r</\*%>
      out.puts '#endif'
    when %r<%\*/>
      out.puts
    when /\A%%/
      out.puts '%%'
      return
    else
      out.print line
    end
  end
end

def usercode(f, out)
  while line = f.gets
    out.print line
  end
end

main
