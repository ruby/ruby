# Parse a Fortran 95 file.

require "rdoc/code_objects"

module RDoc

  # See rdoc/parsers/parse_f95.rb
 
  class Token

    NO_TEXT = "??".freeze
    
    def initialize(line_no, char_no)
      @line_no = line_no
      @char_no = char_no
      @text    = NO_TEXT
    end
    # Because we're used in contexts that expect to return a token,
    # we set the text string and then return ourselves
    def set_text(text)
      @text = text
      self
    end

    attr_reader :line_no, :char_no, :text

  end

  class Fortran95parser

    extend ParserFactory
    parse_files_matching(/\.(f9(0|5)|F)$/)
    
    # prepare to parse a Fortran 95 file
    def initialize(top_level, file_name, body, options)
      @body = body
      @options = options
      @top_level = top_level
      @progress = $stderr unless options.quiet
    end
    
    # devine code constructs
    def scan

      # modules and programs
      if @body =~ /^(module|program)\s+(\w+)/i
	progress "m"
	f9x_module = @top_level.add_module NormalClass, $2
	f9x_module.record_location @top_level
	first_comment, second_comment = $`.gsub(/^!\s?/,"").split "\n\s*\n"
	if second_comment
	  @top_level.comment = first_comment if first_comment
	  f9x_module.comment = second_comment
	else
	  f9x_module.comment = first_comment if first_comment
	end
      end

      # use modules
      remaining_code = @body
      while remaining_code =~ /^\s*use\s+(\w+)/i
	remaining_code = $~.post_match
	progress "."
	f9x_module.add_include Include.new($1, "") if f9x_module
      end

      # subroutines
      remaining_code = @body
      while remaining_code =~ /^\s*subroutine\s+(\w+)\s*\((.*?)\)/im
	remaining_code = $~.post_match
        subroutine = AnyMethod.new("Text", $1)
	subroutine.singleton = false

        prematchText = $~.pre_match
        params = $2
        params.gsub!(/&/,'')
	subroutine.params = params
        comment = find_comments prematchText
	subroutine.comment = comment if comment

        subroutine.start_collecting_tokens
        remaining_code =~ /^\s*end\s+subroutine/i
        code = "subroutine #{subroutine.name} (#{subroutine.params})\n"
        code += $~.pre_match
        code += "\nend subroutine\n"
        subroutine.add_token Token.new(1,1).set_text(code)
        
        progress "s"
        f9x_module.add_method subroutine if f9x_module
      end

      @top_level

    end

    def find_comments text
      lines = text.split("\n").reverse
      comment_block = Array.new
      lines.each do |line|
	break if line =~ /^\s*\w/
        comment_block.unshift line.sub(/^!\s?/,"")
      end
      nice_lines = comment_block.join("\n").split "\n\s*\n"
      nice_lines.shift
      nice_lines.shift
      nice_lines.shift
    end

    def progress(char)
      unless @options.quiet
        @progress.print(char)
        @progress.flush
      end
    end

  end # class Fortran95parser

end # module RDoc
