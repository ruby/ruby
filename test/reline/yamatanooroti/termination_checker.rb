require 'ripper'

module TerminationChecker
  def self.terminated?(code)
    Ripper.sexp(code) ? true : false
  end
end

module AutoIndent
  def self.calculate_indent(lines, line_index, byte_pointer, is_newline)
    if is_newline
      2 * nesting_level(lines[0..line_index - 1])
    else
      lines = lines.dup
      lines[line_index] = lines[line_index]&.byteslice(0, byte_pointer)
      prev_level = nesting_level(lines[0..line_index - 1])
      level = nesting_level(lines[0..line_index])
      2 * level if level < prev_level
    end
  end

  def self.nesting_level(lines)
    code = lines.join("\n")
    code.scan(/if|def|\(|\[|\{/).size - code.scan(/end|\)|\]|\}/).size
  end
end
