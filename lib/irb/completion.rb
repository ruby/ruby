
require "readline"

module IRB
  module InputCompletion
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
      "yield"
    ]
      
    CompletionProc = proc { |input|
      case input
      when /^([^.]+)\.([^.]*)$/
	receiver = $1
	message = $2
	if eval("(local_variables|#{receiver}.type.constants).include?('#{receiver}')", 
	    IRB.conf[:MAIN_CONTEXT].bind)
	  candidates = eval("#{receiver}.methods", IRB.conf[:MAIN_CONTEXT].bind)
	else
	  candidates = []
	end
	candidates.grep(/^#{Regexp.quote(message)}/).collect{|e| receiver + "." + e}
      else
	candidates = eval("methods | private_methods | local_variables | type.constants", 
			  IRB.conf[:MAIN_CONTEXT].bind)
	(candidates|ReservedWords).grep(/^#{Regexp.quote(input)}/)
      end
    }
  end
end

Readline.completion_proc = IRB::InputCompletion::CompletionProc
