#
#   irb/input-method.rb - input methods using irb
#   	$Release Version: 0.9$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
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

      def ReadlineInputMethod.create_finalizer(hist, file)
	proc do
	  if num = IRB.conf[:SAVE_HISTORY] and (num = num.to_i) > 0
            if hf = IRB.conf[:HISTORY_FILE]
	      file = File.expand_path(hf)
            end
            if file
              open(file, 'w' ) do |f|
                hist = hist.to_a
                f.puts(hist[-num..-1] || hist)
              end
	    end
	  end
	end
      end

      def initialize
	super

	@line_no = 0
	@line = []
	@eof = false

	loader = proc {|f| f.each {|l| HISTORY << l.chomp}}
	if hist = IRB.conf[:HISTORY_FILE]
	  hist = File.expand_path(hist)
	  begin
	    open(hist, &loader) 
	  rescue
	  end
	else
	  IRB.rc_files("_history") do |hist|
	    begin
	      open(hist, &loader)
	    rescue
	      hist = nil
	    else
	      break
	    end
	  end
	end
	ObjectSpace.define_finalizer(self, ReadlineInputMethod.create_finalizer(HISTORY, hist))
      end

      def gets
	if l = readline(@prompt, true)
	  HISTORY.pop if l.empty?
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
