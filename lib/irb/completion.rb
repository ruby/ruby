#
#   irb/completor.rb - 
#   	$Release Version: 0.7.1$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       From Original Idea of shugo@ruby-lang.org
#

require "readline"

module IRB
  module InputCompletor

    @RCS_ID='-$Id$-'

    ReservedWords = [
      "BEGIN", "END",
      "alias", "and", 
      "begin", "break", 
      "case", "class",
      "def", "defined", "do",
      "else", "elsif", "end", "ensure",
      "false", "for", 
      "if", "in", 
      "module", 
      "next", "nil", "not",
      "or", 
      "redo", "rescue", "retry", "return",
      "self", "super",
      "then", "true",
      "undef", "unless", "until",
      "when", "while",
      "yield",
    ]
      
    CompletionProc = proc { |input|
      bind = IRB.conf[:MAIN_CONTEXT].workspace.binding
      case input
      when /^(\/[^\/]*\/)\.([^.]*)$/
	# Regexp
	receiver = $1
	message = Regexp.quote($2)

	candidates = Regexp.instance_methods(true)
	select_message(receiver, message, candidates)

      when /^([^\]]*\])\.([^.]*)$/
	# Array
	receiver = $1
	message = Regexp.quote($2)

	candidates = Array.instance_methods(true)
	select_message(receiver, message, candidates)

      when /^([^\}]*\})\.([^.]*)$/
	# Proc or Hash
	receiver = $1
	message = Regexp.quote($2)

	candidates = Proc.instance_methods(true) | Hash.instance_methods(true)
	select_message(receiver, message, candidates)
	
      when /^(:[^:]*)$/
 	# Symbol
	if Symbol.respond_to?(:all_symbols)
	  sym = $1
	  candidates = Symbol.all_symbols.collect{|s| s.id2name}
	  candidates.grep(/^#{sym}/)
	else
	  []
	end

      when /^::([A-Z][^:\.\(]*)$/
	# Absolute Constant or class methods
	receiver = $1
	candidates = Object.constants
	candidates.grep(/^#{receiver}/).collect{|e| "::" + e}

      when /^(((::)?[A-Z][^:.\(]*)+)::?([^:.]*)$/
	# Constant or class methods
	receiver = $1
	message = Regexp.quote($4)
	begin
	  candidates = eval("#{receiver}.constants | #{receiver}.methods", bind)
	rescue Exception
	  candidates = []
	end
	candidates.grep(/^#{message}/).collect{|e| receiver + "::" + e}

      when /^(:[^.]+)\.([^.]*)$/
	# Symbol
	receiver = $1
	message = Regexp.quote($2)

	candidates = Symbol.instance_methods(true)
	select_message(receiver, message, candidates)

      when /^([0-9_]+(\.[0-9_]+)?(e[0-9]+)?)\.([^.]*)$/
	# Numeric
	receiver = $1
	message = Regexp.quote($4)

	begin
	  candidates = eval(receiver, bind).methods
	rescue Exception
	  candidates
	end
	select_message(receiver, message, candidates)

#      when /^(\$?(\.?[^.]+)+)\.([^.]*)$/
      when /^((\.?[^.]+)+)\.([^.]*)$/
	# variable
	receiver = $1
	message = Regexp.quote($3)

	gv = eval "global_variables", bind
	lv = eval "local_variables", bind
	cv = eval "type.constants", bind
	
	if (gv | lv | cv).include?(receiver)
	  # foo.func and foo is local var.
	  candidates = eval("#{receiver}.methods", bind)
	elsif /^[A-Z]/ =~ receiver and /\./ !~ receiver
	  # Foo::Bar.func
	  begin
	    candidates = eval("#{receiver}.methods", bind)
	  rescue Exception
	    candidates = []
	  end
	else
	  # func1.func2
	  candidates = []
	  ObjectSpace.each_object(Module){|m|
	    next if /^(IRB|SLex|RubyLex|RubyToken)/ =~ m.name
	    candidates.concat m.instance_methods
	  }
	  candidates.sort!
	  candidates.uniq!
	end
	select_message(receiver, message, candidates)

      when /^\.([^.]*)$/
	# unknown(maybe String)

	receiver = ""
	message = Regexp.quote($1)

	candidates = String.instance_methods(true)
	select_message(receiver, message, candidates)

      else
	candidates = eval("methods | private_methods | local_variables | type.constants", bind)
			  
	(candidates|ReservedWords).grep(/^#{Regexp.quote(input)}/)
      end
    }

    Operators = ["%", "&", "*", "**", "+",  "-",  "/",
      "<", "<<", "<=", "<=>", "==", "===", "=~", ">", ">=", ">>",
      "[]", "[]=", "^",]

    def self.select_message(receiver, message, candidates)
      candidates.grep(/^#{message}/).collect do |e|
	case e
	when /^[a-zA-Z_]/
	  receiver + "." + e
	when /^[0-9]/
	when *Operators
	  #receiver + " " + e
	end
      end
    end
  end
end

Readline.completion_proc = IRB::InputCompletor::CompletionProc
