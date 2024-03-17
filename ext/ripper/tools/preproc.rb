# frozen_string_literal: true
# $Id$

require 'optparse'

def main
  output = nil
  template = nil
  parser = OptionParser.new
  parser.banner = "Usage: #{File.basename($0)} [--output=PATH] [--template=PATH] <parse.y>"
  parser.on('--output=PATH', 'An output file.') {|path|
    output = path
  }
  parser.on('--template=PATH', 'An template file.') {|path|
    template = path
  }
  parser.on('--help', 'Prints this message and quit.') {
    puts parser.help
    exit true
  }
  begin
    parser.parse!
  rescue OptionParser::ParseError => err
    warn err.message
    abort parser.help
  end
  out = "".dup
  if ARGV[0] == "-"
    unless ARGV.size == 2
      abort "wrong number of arguments (#{ARGV.size} for 2)"
    end
    process STDIN, out, ARGV[1], template
  else
    unless ARGV.size == 1
      abort "wrong number of arguments (#{ARGV.size} for 1)"
    end
    File.open(ARGV[0]) {|f|
      process f, out, ARGV[0], template
    }
  end
  if output
    File.write(output, out)
  else
    print out
  end
end

def process(f, out, path, template)
  prelude f, out
  grammar f, out
  usercode f, out, path, template
end

def prelude(f, out)
  @exprs = {}
  while line = f.gets
    case line
    when /\A%%/
      out << "%%\n"
      return
    when /\A%token/, /\A%type/, /\A} <node(?>_\w+)?>/
      # types in %union which have corresponding set_yylval_* macro.
      out << line
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

def usercode(f, out, path, template)
  require 'erb'
  lineno = nil
  src = nil
  compiler = ERB::Compiler.new('%-')
  compiler.put_cmd = compiler.insert_cmd = "out.<<"

  if template
    File.open(template) do |f|
      out.clear
      lineno = f.lineno
      src, = compiler.compile(f.read)
      path = template
    end
  else
    lineno = f.lineno
    src, = compiler.compile(f.read)
  end

  eval(src, binding, path, lineno)
end

main
