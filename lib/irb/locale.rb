#
#   irb/locale.rb - internationalization module
#   	$Release Version: 0.7.4$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#   
#

autoload :Tempfile, "tempfile"
autoload :Kconv, "kconv"

module IRB
  class Locale
    @RCS_ID='-$Id$-'

    JPDefaultLocale = "ja"
    LOCALE_DIR = "/lc/"

    def initialize(locale = nil)
      @lang = locale || ENV["IRB_LANG"] || ENV["LC_MESSAGES"] || ENV["LC_ALL"] || ENV["LANG"]
      @lang = "C" unless @lang
    end

    attr_reader :lang

    def String(mes)
      mes = super(mes)
      case @lang
      when /^ja/
	@@LC2KCONV = {
	  #      "ja" => Kconv::JIS,
	  #      "ja_JP" => Kconv::JIS,
	  "ja_JP.ujis" => Kconv::EUC,
	  "ja_JP.euc" => Kconv::EUC,
	  "ja_JP.eucJP" => Kconv::EUC,
	  "ja_JP.sjis" => Kconv::SJIS,
	  "ja_JP.SJIS" => Kconv::SJIS,
	  } unless defined? @@LC2KCONV
	
	mes = Kconv::kconv(mes, @@LC2KCONV[@lang])
      else
	mes
      end
      mes
    end

    def format(*opts)
      String(super(*opts))
    end

    def gets(*rs)
      String(super(*rs))
    end

    def readline(*rs)
      String(super(*rs))
    end

    def print(*opts)
      ary = opts.collect{|opt| String(opt)}
      super *ary
    end

    def printf(*opts)
      s = format(*opts)
      print s
    end

    def puts(*opts)
      ary = opts.collect{|opt| String(opts)}
      super *ary
    end

    def require(file, priv = nil)
      rex = Regexp.new("lc/#{Regexp.quote(file)}\.(so|o|sl|rb)?")
      return false if $".find{|f| f =~ rex}

      case file
      when /\.rb$/
	begin
	  load(file, priv)
	  $".push file
	  return true
	rescue LoadError
	end
      when /\.(so|o|sl)$/
	return super
      end

      begin
	load(f = file + ".rb")
	$".push f  #"
	return true
      rescue LoadError
	return ruby_require(file)
      end
    end

    alias toplevel_load load
    
    def load(file, priv=nil)
      dir = File.dirname(file)
      dir = "" if dir == "."
      base = File.basename(file)

      if /^ja(_JP)?$/ =~ @lang
 	back, @lang = @lang, "C"
      end
      begin
	if dir[0] == ?/ #/
	  lc_path = search_file(dir, base)
	  return real_load(lc_path, priv) if lc_path
	end
	
	for path in $:
	  lc_path = search_file(path + "/" + dir, base)
	  return real_load(lc_path, priv) if lc_path
	end
      ensure
	@lang = back if back
      end
      raise LoadError, "No such file to load -- #{file}"
    end 

    def real_load(path, priv)
      tmp_base = path.tr("./:", "___")
      lc_file = Tempfile.new(tmp_base)
      File.foreach(path) do |line|
	line = self.String(line)
	lc_file.print(line)
      end
      lc_file.close
      toplevel_load lc_file.path, priv
    end
    private :real_load

    def find(file , paths = $:)
      dir = File.dirname(file)
      dir = "" if dir == "."
      base = File.basename(file)
      if dir[0] == ?/ #/
	  return lc_path = search_file(dir, base)
      else
	for path in $:
	  if lc_path = search_file(path + "/" + dir, base)
	    return lc_path
	  end
	end
      end
      nil
    end

    def search_file(path, file)
      if File.exists?(p1 = path + lc_path(file, "C"))
	if File.exists?(p2 = path + lc_path(file))
	  return p2
	else
	end
	return p1
      else
      end
      nil
    end
    private :search_file

    def lc_path(file = "", lc = @lang)
      case lc
      when "C"
	LOCALE_DIR + file
      when /^ja/
	LOCALE_DIR + "ja/" + file
      else
	LOCALE_DIR + @lang + "/" + file
      end
    end
    private :lc_path
  end
end




