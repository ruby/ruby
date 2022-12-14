require 'ripper'
require 'irb/ruby-lex'

class TerminationChecker < RubyLex
  def terminated?(code)
    code.gsub!(/\n*$/, '').concat("\n")
    @tokens = self.class.ripper_lex_without_warning(code)
    continue = process_continue
    code_block_open = check_code_block(code)
    indent = process_nesting_level
    ltype = process_literal_type
    if code_block_open or ltype or continue or indent > 0
      false
    else
      true
    end
  end
end

class AutoIndent < RubyLex
  def initialize
    context = Struct.new("MockIRBContext", :auto_indent_mode, :workspace, :local_variables).new(true, nil, [])
    set_input(self, context: context)
    set_auto_indent(context)
  end

  def auto_indent(&block)
    Reline.auto_indent_proc = block
  end
end
