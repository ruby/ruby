#
#   irb/loader.rb - irb loader 
#   	$Release Version: 0.7.3$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#   
#

module IRB
  class LoadAbort < GlobalExit;end

  module Loader
    @RCS_ID='-$Id$-'

    alias ruby_load load
    alias ruby_require require

    def irb_load(file_name)
      return ruby_load(file_name) unless IRB.conf[:USE_LOADER]

      load_sub(file_name)
      return true
    end

    def irb_require(file_name)
      return ruby_require(file_name) unless IRB.conf[:USE_LOADER]

      rex = Regexp.new("#{Regexp.quote(file_name)}(\.o|\.rb)?")
      return false if $".find{|f| f =~ rex}

      case file_name
      when /\.rb$/
	begin
	  load_sub(file_name)
	  $".push file_name
	  return true
	rescue LoadError
	end
      when /\.(so|o|sl)$/
	return ruby_require(file_name)
      end
      
      begin
	load_sub(f = file_name + ".rb")
	$".push f
	return true
      rescue LoadError
	return ruby_require(file_name)
      end
    end

    def load_sub(fn)
      if fn =~ /^#{Regexp.quote(File::Separator)}/
	return false unless File.exist?(fn)
	return irb_context.load_file(fn)
      end
      
      for path in $:
	if File.exist?(f = File.join(path, fn))
	  return irb_context.load_file(f)
	end
      end
      raise LoadError, "No such file to load -- #{file_name}"
    end

    alias load irb_load
    alias require irb_require
  end

#   class Context
#     def load_from(file_name)
#       io = FileInputMethod.new(file_name)
#       @irb.signal_status(:IN_LOAD) do
# 	switch_io(io, file_name) do
# 	  eval_input
# 	end
#       end
#     end
#   end

  class Context
    def load_file(path)
      back_io = @io
      back_path = @irb_path
      back_name = @irb_name
      back_scanner = @irb.scanner
      begin
 	@io = FileInputMethod.new(path)
 	@irb_name = File.basename(path)
	@irb_path = path
	@irb.signal_status(:IN_LOAD) do
	  if back_io.kind_of?(FileInputMethod)
	    @irb.eval_input
	  else
	    begin
	      @irb.eval_input
	    rescue LoadAbort
	      print "load abort!!\n"
	    end
	  end
	end
      ensure
 	@io = back_io
 	@irb_name = back_name
 	@irb_path = back_path
	@irb.scanner = back_scanner
      end
    end
  end

  module ExtendCommand
    include Loader
  end
end
