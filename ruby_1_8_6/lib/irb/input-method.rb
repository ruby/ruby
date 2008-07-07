#
#   irb/input-method.rb - input methods used irb
#   	$Release Version: 0.9.5$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#   
#
module IRB
  # 
  # InputMethod
  #	StdioInputMethod
  #	FileInputMethod
  #	(ReadlineInputMethod)
  #
  STDIN_FILE_NAME = "(line)"
  class InputMethod
    @RCS_ID='-$Id$-'

    def initialize(file = STDIN_FILE_NAME)
      @file_name = file
    end
    attr_reader :file_name

    attr_accessor :prompt
    
    def gets
      IRB.fail NotImplementedError, "gets"
    end
    public :gets

    def readable_atfer_eof?
      false
    end
  end
  
  class StdioInputMethod < InputMethod
    def initialize
      super
      @line_no = 0
      @line = []
    end

    def gets
      print @prompt
      @line[@line_no += 1] = $stdin.gets
    end

    def eof?
      $stdin.eof?
    end

    def readable_atfer_eof?
      true
    end

    def line(line_no)
      @line[line_no]
    end
  end
  
  class FileInputMethod < InputMethod
    def initialize(file)
      super
      @io = open(file)
    end
    attr_reader :file_name

    def eof?
      @io.eof?
    end

    def gets
      print @prompt
      l = @io.gets
#      print @prompt, l
      l
    end
  end

  begin
    require "readline"
    class ReadlineInputMethod < InputMethod
      include Readline 
      def initialize
	super

	@line_no = 0
	@line = []
	@eof = false
      end

      def gets
	if l = readline(@prompt, false)
          HISTORY.push(l) if !l.empty?
	  @line[@line_no += 1] = l + "\n"
	else
	  @eof = true
	  l
	end
      end

      def eof?
	@eof
      end

      def readable_atfer_eof?
	true
      end

      def line(line_no)
	@line[line_no]
      end
    end
  rescue LoadError
  end
end
