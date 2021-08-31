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
  lex_state_def = false
  while line = f.gets
    case line
    when /\A%%/
      out << "%%\n"
      return
    when /\A%token/
      out << line.sub(/<\w+>/, '<val>')
    when /\A%type/
      out << line.sub(/<\w+>/, '<val>')
    when /^enum lex_state_(?:bits|e) \{/
      lex_state_def = true
      out << line
    when /^\}/
      lex_state_def = false
      out << line
    else
      out << line
    end
    if lex_state_def
      case line
      when /^\s*(EXPR_\w+),\s+\/\*(.+)\*\//
        @exprs[$1.chomp("_bit")] = $2.strip
      when /^\s*(EXPR_\w+)\s+=\s+(.+)$/
        name = $1
        val = $2.chomp(",")
        @exprs[name] = "equals to " + (val.start_with?("(") ? "<tt>#{val}</tt>" : "+#{val}+")
      end
    end
  end
end

require_relative "dsl"

def grammar(f, out)
  while line = f.gets
    case line
    when %r</\*% *ripper(?:\[(.*?)\])?: *(.*?) *%\*/>
      out << DSL.new($2, ($1 || "").split(",")).generate << "\n"
    when %r</\*%%%\*/>
      out << "#if 0\n"
    when %r</\*%>
      out << "#endif\n"
    when %r<%\*/>
      out << "\n"
    when /\A%%/
      out << "%%\n"
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
