# frozen_string_literal: true
# $Id$

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
    exit true
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    $stderr.puts err.message
    $stderr.puts parser.help
    exit false
  end
  unless ARGV.size == 1
    abort "wrong number of arguments (#{ARGV.size} for 1)"
  end
  out = "".dup
  File.open(ARGV[0]) {|f|
    prelude f, out
    grammar f, out
    usercode f, out
  }
  if output
    File.open(output, 'w') {|f|
      f.write out
    }
  else
    print out
  end
end

def prelude(f, out)
  @exprs = {}
  while line = f.gets
    case line
    when %r</\*%%%\*/>
      out << '/*' << $/
    when %r</\*%>
      out << '*/' << $/
    when %r<%\*/>
      out << $/
    when /\A%%/
      out << '%%' << $/
      return
    when /\A%token/
      out << line.sub(/<\w+>/, '<val>')
    when /\A%type/
      out << line.sub(/<\w+>/, '<val>')
    else
      if (/^enum lex_state_(?:bits|e) \{/ =~ line)..(/^\}/ =~ line)
        case line
        when /^\s*(EXPR_\w+),\s+\/\*(.+)\*\//
          @exprs[$1.chomp("_bit")] = $2.strip
        when /^\s*(EXPR_\w+)\s+=\s+(.+)$/
          name = $1
          val = $2.chomp(",")
          @exprs[name] = "equals to " + (val.start_with?("(") ? "<tt>#{val}</tt>" : "+#{val}+")
        end
      end
      out << line
    end
  end
end

def grammar(f, out)
  while line = f.gets
    case line
    when %r</\*%%%\*/>
      out << '#if 0' << $/
    when %r</\*%c%\*/>
      out << '/*' << $/
    when %r</\*%c>
      out << '*/' << $/
    when %r</\*%>
      out << '#endif' << $/
    when %r<%\*/>
      out << $/
    when /\A%%/
      out << '%%' << $/
      return
    else
      out << line
    end
  end
end

def usercode(f, out)
  require 'erb'
  compiler = ERB::Compiler.new('%-')
  compiler.put_cmd = compiler.insert_cmd = "out.<<"
  lineno = f.lineno
  src, = compiler.compile(f.read)
  eval(src, binding, f.path, lineno)
end

main
