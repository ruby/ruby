#
#   irb/locale.rb - internationalization module
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
module IRB
  class Locale
    @RCS_ID='-$Id$-'

    LOCALE_NAME_RE = %r[
      (?<language>[[:alpha:]]{2})
      (?:_
       (?<territory>[[:alpha:]]{2,3})
       (?:\.
	(?<codeset>[^@]+)
       )?
      )?
      (?:@
       (?<modifier>.*)
      )?
    ]x
    LOCALE_DIR = "/lc/"

    @@legacy_encoding_alias_map = {}.freeze

    def initialize(locale = nil)
      @lang = @territory = @encoding_name = @modifier = nil
      @locale = locale || ENV["IRB_LANG"] || ENV["LC_MESSAGES"] || ENV["LC_ALL"] || ENV["LANG"] || "C"
      if m = LOCALE_NAME_RE.match(@locale)
	@lang, @territory, @encoding_name, @modifier = m[:language], m[:territory], m[:codeset], m[:modifier]

	if @encoding_name
	  begin load 'irb/encoding_aliases.rb'; rescue LoadError; end
	  if @encoding = @@legacy_encoding_alias_map[@encoding_name]
	    warn "%s is obsolete. use %s" % ["#{@lang}_#{@territory}.#{@encoding_name}", "#{@lang}_#{@territory}.#{@encoding.name}"]
	  end
	  @encoding = Encoding.find(@encoding_name) rescue nil
	end
      end
      @encoding ||= (Encoding.find('locale') rescue Encoding::ASCII_8BIT)
    end

    attr_reader :lang, :territory, :encoding, :modifieer

    def String(mes)
      mes = super(mes)
      if @encoding
	mes.encode(@encoding)
      else
	mes
      end
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
      super(*ary)
    end

    def printf(*opts)
      s = format(*opts)
      print s
    end

    def puts(*opts)
      ary = opts.collect{|opt| String(opt)}
      super(*ary)
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

      if dir[0] == ?/ #/
	lc_path = search_file(dir, base)
	return real_load(lc_path, priv) if lc_path
      end

      for path in $:
	lc_path = search_file(path + "/" + dir, base)
	return real_load(lc_path, priv) if lc_path
      end
      raise LoadError, "No such file to load -- #{file}"
    end

    def real_load(path, priv)
      src = MagicFile.open(path){|f| f.read}
      if priv
	eval("self", TOPLEVEL_BINDING).extend(Module.new {eval(src, nil, path)})
      else
	eval(src, TOPLEVEL_BINDING, path)
      end
    end
    private :real_load

    def find(file , paths = $:)
      dir = File.dirname(file)
      dir = "" if dir == "."
      base = File.basename(file)
      if dir =~ /^\//
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
      each_sublocale do |lc|
	full_path = path + lc_path(file, lc)
	return full_path if File.exist?(full_path)
      end
      nil
    end
    private :search_file

    def lc_path(file = "", lc = @locale)
      if lc.nil?
	LOCALE_DIR + file
      else
	LOCALE_DIR + @lang + "/" + file
      end
    end
    private :lc_path

    def each_sublocale
      if @lang
	if @territory
	  if @encoding_name
	    yield "#{@lang}_#{@territory}.#{@encoding_name}@#{@modifier}" if @modifier
	    yield "#{@lang}_#{@territory}.#{@encoding_name}"
	  end
	  yield "#{@lang}_#{@territory}@#{@modifier}" if @modifier
	  yield "#{@lang}_#{@territory}"
	end
	yield "#{@lang}@#{@modifier}" if @modifier
	yield "#{@lang}"
      end
      yield nil
    end
    private :each_sublocale
  end
end




