#
#  tkfont.rb - the class to treat fonts on Ruby/Tk
#
#                               by  Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

class TkFont
  include Tk
  extend TkCore

  Tk_FontID = [0]
  Tk_FontNameTBL = {}
  Tk_FontUseTBL = {}

  # set default font
  case Tk::TK_VERSION
  when /^4\.*/
    DEFAULT_LATIN_FONT_NAME = 'a14'.freeze
    DEFAULT_KANJI_FONT_NAME = 'k14'.freeze
  when /^8\.*/
    if JAPANIZED_TK
      begin
        fontnames = tk_call('font', 'names')
	case fontnames
	when /defaultgui/
          # Tcl/Tk-JP for Windows
          ltn = 'defaultgui'
          knj = 'defaultgui'
	when /Mincho:Helvetica-12/
          # Tcl/Tk-JP for UNIX/X
          ltn, knj = tk_split_simplelist(tk_call('font', 'configure', 
                                                 'Mincho:Helvetica-12', 
                                                 '-compound'))
        else
          # unknown Tcl/Tk-JP
	  platform = tk_call('set', 'tcl_platform(platform)')
	  case platform
	  when 'unix'
	    ltn = {'family'=>'Helvetica'.freeze, 'size'=>-12}
	    knj = 'k14'
	    #knj = '-misc-fixed-medium-r-normal--14-*-*-*-c-*-jisx0208.1983-0'
	  when 'windows'
	    ltn = {'family'=>'MS Sans Serif'.freeze, 'size'=>8}
	    knj = 'mincho'
	  when 'macintosh'
	    ltn = 'system'
	    knj = 'mincho'
	  else # unknown
	    ltn = 'Helvetica'
	    knj = 'mincho'
	  end
        end
      rescue
        ltn = 'Helvetica'
        knj = 'mincho'
      end

    else # not JAPANIZED_TK
      begin
	platform = tk_call('set', 'tcl_platform(platform)')
	case platform
	when 'unix'
	  ltn = {'family'=>'Helvetica'.freeze, 'size'=>-12}
	  knj = 'k14'
	  #knj = '-misc-fixed-medium-r-normal--14-*-*-*-c-*-jisx0208.1983-0'
	when 'windows'
	  ltn = {'family'=>'MS Sans Serif'.freeze, 'size'=>8}
	  knj = 'mincho'
	when 'macintosh'
	  ltn = 'system'
	  knj = 'mincho'
	else # unknown
	  ltn = 'Helvetica'
	  knj = 'mincho'
	end
      rescue
	ltn = 'Helvetica'
	knj = 'mincho'
      end
    end

    DEFAULT_LATIN_FONT_NAME = ltn.freeze
    DEFAULT_KANJI_FONT_NAME = knj.freeze

  else # unknown version
    DEFAULT_LATIN_FONT_NAME = 'Helvetica'.freeze
    DEFAULT_KANJI_FONT_NAME = 'mincho'.freeze

  end

  if $DEBUG
    print "default latin font = "; p DEFAULT_LATIN_FONT_NAME
    print "default kanji font = "; p DEFAULT_KANJI_FONT_NAME
  end

  ###################################
  # class methods
  ###################################
  def TkFont.families(window=nil)
    case (Tk::TK_VERSION)
    when /^4\.*/
      ['fixed']

    when /^8\.*/
      if window
	tk_split_simplelist(tk_call('font', 'families', '-displayof', window))
      else
	tk_split_simplelist(tk_call('font', 'families'))
      end
    end
  end

  def TkFont.names
    case (Tk::TK_VERSION)
    when /^4\.*/
      r = ['fixed']
      r += ['a14', 'k14'] if JAPANIZED_TK
      Tk_FontNameTBL.each_value{|obj| r.push(obj)}
      r | []

    when /^8\.*/
      tk_split_simplelist(tk_call('font', 'names'))

    end
  end

  def TkFont.create_copy(font)
    fail 'source-font need to be TkFont' unless font.kind_of? TkFont
    keys = {}
    font.configinfo.each{|key,value| keys[key] = value }
    TkFont.new(font.latin_font, font.kanji_font, keys)
  end

  def TkFont.get_obj(name)
    if name =~ /^(@font[0-9]+)(|c|l|k)$/
      Tk_FontNameTBL[$1]
    else
      nil
    end
  end

  def TkFont.init_widget_font(path, *args)
    case (Tk::TK_VERSION)
    when /^4\.*/
      conf = tk_split_simplelist(tk_call(*args)).
	find_all{|prop| prop[0..5]=='-font ' || prop[0..10]=='-kanjifont '}.
	collect{|prop| tk_split_simplelist(prop)}
      if font_inf = conf.assoc('-font')
	ltn = font_inf[4]
	ltn = nil if ltn == []
      else 
	#ltn = nil
	raise RuntimeError, "unknown option '-font'"
      end
      if font_inf = conf.assoc('-kanjifont')
	knj = font_inf[4]
	knj = nil if knj == []
      else
	knj = nil
      end
      TkFont.new(ltn, knj).call_font_configure(path, *(args + [{}]))

    when /^8\.*/
      font_prop = tk_split_simplelist(tk_call(*args)).find{|prop| 
	prop[0..5] == '-font '
      }
      unless font_prop
	raise RuntimeError, "unknown option '-font'"
      end
      fnt = tk_split_simplelist(font_prop)[4]
      if fnt == ""
	TkFont.new(nil, nil).call_font_configure(path, *(args + [{}]))
      else
	begin
	  compound = Hash[*tk_split_simplelist(tk_call('font', 'configure', 
					       fnt))].collect{|key,value|
	    [key[1..-1], value]
	  }.assoc('compound')[1]
	rescue
	  compound = []
	end
	if compound == []
	  TkFont.new(fnt, DEFAULT_KANJI_FONT_NAME) \
	  .call_font_configure(path, *(args + [{}]))
	else
	  TkFont.new(compound[0], compound[1]) \
	  .call_font_configure(path, *(args + [{}]))
	end
      end
    end
  end

  def TkFont.used_on(path=nil)
    if path
      Tk_FontUseTBL[path]
    else
      Tk_FontUseTBL.values | []
    end
  end

  def TkFont.failsafe(font)
    begin
      if /^8\.*/ === Tk::TK_VERSION  && JAPANIZED_TK
        tk_call('font', 'failsafe', font)
      end
    rescue
    end
  end

  ###################################
  private
  ###################################
  def initialize(ltn=DEFAULT_LATIN_FONT_NAME, knj=nil, keys=nil)
    @id = format("@font%.4d", Tk_FontID[0])
    Tk_FontID[0] += 1
    Tk_FontNameTBL[@id] = self
    knj = DEFAULT_KANJI_FONT_NAME if JAPANIZED_TK && !knj
    create_compoundfont(ltn, knj, keys)
  end

  def _get_font_info_from_hash(font)
    foundry  = (info = font['foundry'] .to_s)?  info: '*'
    family   = (info = font['family']  .to_s)?  info: '*'
    weight   = (info = font['weight']  .to_s)?  info: '*'
    slant    = (info = font['slant']   .to_s)?  info: '*'
    swidth   = (info = font['swidth']  .to_s)?  info: '*'
    adstyle  = (info = font['adstyle'] .to_s)?  info: '*'
    pixels   = (info = font['pixels']  .to_s)?  info: '*'
    points   = (info = font['points']  .to_s)?  info: '*'
    resx     = (info = font['resx']    .to_s)?  info: '*'
    resy     = (info = font['resy']    .to_s)?  info: '*'
    space    = (info = font['space']   .to_s)?  info: '*'
    avgWidth = (info = font['avgWidth'].to_s)?  info: '*'
    charset  = (info = font['charset'] .to_s)?  info: '*'
    encoding = (info = font['encoding'].to_s)?  info: '*'

    [foundry, family, weight, slant, swidth, adstyle,
      pixels, points, resx, resy, space, avgWidth, charset, encoding]
  end

  def create_latinfont_tk4x(font)
    if font.kind_of? Hash
      @latinfont = '-' + _get_font_info_from_hash(font).join('-') + '-'

    elsif font.kind_of? Array
      finfo = {}
      finfo['family'] = font[0].to_s
      if font[1]
	fsize = font[1].to_s
	if fsize != '0' && fsize =~ /^(|\+|-)([0-9]+)$/
	  if $1 == '-'
	    finfo['pixels'] = $2
	  else
	    finfo['points'] = $2
	  end
	else
	  finfo['points'] = '13'
	end
      end
      font[2..-1].each{|style|
	case (style)
	when 'normal'
	  finfo['weight'] = style
	when 'bold'
	  finfo['weight'] = style
	when 'roman'
	  finfo['slant'] = 'r'
	when 'italic'
	  finfo['slant'] = 'i'
	end
      }

      @latinfont = '-' + _get_font_info_from_hash(finfo).join('-') + '-'

    elsif font.kind_of? TkFont
      @latinfont = font.latin_font

    else
      if font
        @latinfont = font
      else
        @latinfont = DEFAULT_LATIN_FONT_NAME
      end

    end
  end

  def create_kanjifont_tk4x(font)
    unless JAPANIZED_TK
      @kanjifont = ""
      return
    end

    if font.kind_of? Hash
      @kanjifont = '-' + _get_font_info_from_hash(font).join('-') + '-'

    elsif font.kind_of? Array
      finfo = {}
      finfo['family'] = font[0].to_s
      if font[1]
	fsize = font[1].to_s
	if fsize != '0' && fsize =~ /^(|\+|-)([0-9]+)$/
	  if $1 == '-'
	    finfo['pixels'] = $2
	  else
	    finfo['points'] = $2
	  end
	else
	  finfo['points'] = '13'
	end
      end
      font[2..-1].each{|style|
	case (style)
	when 'normal'
	  finfo['weight'] = style
	when 'bold'
	  finfo['weight'] = style
	when 'roman'
	  finfo['slant'] = 'r'
	when 'italic'
	  finfo['slant'] = 'i'
	end
      }

      @kanjifont = '-' + _get_font_info_from_hash(finfo).join('-') + '-'
    elsif font.kind_of? TkFont
      @kanjifont = font.kanji_font
    else
      if font
        @kanjifont = font
      else
        @kanjifont = DEFAULT_KANJI_FONT_NAME
      end
    end
  end

  def create_compoundfont_tk4x(ltn, knj, keys)
    create_latinfont(ltn)
    create_kanjifont(knj)

    if JAPANIZED_TK
      @compoundfont = [[@latinfont], [@kanjifont]]
      @fontslot = {'font'=>@latinfont, 'kanjifont'=>@kanjifont}
    else
      @compoundfont = @latinfont
      @fontslot = {'font'=>@latinfont}
    end
  end

  def create_latinfont_tk8x(font)
    @latinfont = @id + 'l'

    if JAPANIZED_TK
      if font.kind_of? Hash
	if font['charset']
	  tk_call('font', 'create', @latinfont, *hash_kv(font))
	else
	  tk_call('font', 'create', @latinfont, 
                  '-charset', 'iso8859', *hash_kv(font))
	end
      elsif font.kind_of? Array
	tk_call('font', 'create', @latinfont, '-copy', array2tk_list(font))
        tk_call('font', 'configure', @latinfont, '-charset', 'iso8859')
      elsif font.kind_of? TkFont
	tk_call('font', 'create', @latinfont, '-copy', font.latin_font)
      elsif font
	tk_call('font', 'create', @latinfont, '-copy', font, 
                '-charset', 'iso8859')
      else
	tk_call('font', 'create', @latinfont, '-charset', 'iso8859')
      end
    else
      if font.kind_of? Hash
	tk_call('font', 'create', @latinfont, *hash_kv(font))
      else
	keys = {}
	if font.kind_of? Array
	  actual_core(array2tk_list(font)).each{|key,val| keys[key] = val}
	elsif font.kind_of? TkFont
	  actual_core(font.latin_font).each{|key,val| keys[key] = val}
	elsif font
	  actual_core(font).each{|key,val| keys[key] = val}
	end
	tk_call('font', 'create', @latinfont, *hash_kv(keys))
      end

      if font && @compoundfont
        keys = {}
        actual_core(@latinfont).each{|key,val| keys[key] = val}
	tk_call('font', 'configure', @compoundfont, *hash_kv(keys))
      end
    end
  end

  def create_kanjifont_tk8x(font)
    @kanjifont = @id + 'k'

    if JAPANIZED_TK
      if font.kind_of? Hash
        if font['charset']
	  tk_call('font', 'create', @kanjifont, *hash_kv(font))
        else
	  tk_call('font', 'create', @kanjifont, 
		  '-charset', 'jisx0208.1983', *hash_kv(font))
        end
      elsif font.kind_of? Array
        tk_call('font', 'create', @kanjifont, '-copy', array2tk_list(font))
        tk_call('font', 'configure', @kanjifont, '-charset', 'jisx0208.1983')
      elsif font.kind_of? TkFont
        tk_call('font', 'create', @kanjifont, '-copy', font.kanji_font)
      elsif font
        tk_call('font', 'create', @kanjifont, '-copy', font, 
	        '-charset', 'jisx0208.1983')
      else
        tk_call('font', 'create', @kanjifont, '-charset', 'jisx0208.1983')
      end
      # end of JAPANIZED_TK

    else
      if font.kind_of? Hash
        tk_call('font', 'create', @kanjifont, *hash_kv(font))
      else
        keys = {}
        if font.kind_of? Array
	  actual_core(array2tk_list(font)).each{|key,val| keys[key] = val}
        elsif font.kind_of? TkFont
	  actual_core(font.kanji_font).each{|key,val| keys[key] = val}
        elsif font
	  actual_core(font).each{|key,val| keys[key] = val}
        end
        tk_call('font', 'create', @kanjifont, *hash_kv(keys))
      end

      if font && @compoundfont
        keys = {}
        actual_core(@kanjifont).each{|key,val| keys[key] = val}
        tk_call('font', 'configure', @compoundfont, *hash_kv(keys))
      end
    end
  end

  def create_compoundfont_tk8x(ltn, knj, keys)
    create_latinfont(ltn)
    create_kanjifont(knj)

    @compoundfont = @id + 'c'
    if JAPANIZED_TK
      @fontslot = {'font'=>@compoundfont}
      tk_call('font', 'create', @compoundfont, 
	      '-compound', [@latinfont, @kanjifont], *hash_kv(keys))
    else
      tk_call('font', 'create', @compoundfont)

      latinkeys = {}
      begin
	actual_core(@latinfont).each{|key,val| latinkeys[key] = val}
      rescue
	latinkeys {}
      end
      if latinkeys != {}
	tk_call('font', 'configure', @compoundfont, *hash_kv(latinkeys))
      end

      if knj
	kanjikeys = {}
	begin
	  actual_core(@kanjifont).each{|key,val| kanjikeys[key] = val}
	rescue
	  kanjikeys {}
	end
	if kanjikeys != {}
	  tk_call('font', 'configure', @compoundfont, *hash_kv(kanjikeys))
	end
      end

      @fontslot = {'font'=>@compoundfont}
      tk_call('font', 'configure', @compoundfont, *hash_kv(keys))
    end
  end

  def actual_core_tk4x(font, window=nil, option=nil)
    # dummy
    if option
      ""
    else
      [['family',[]], ['size',[]], ['weight',[]], ['slant',[]], 
	['underline',[]], ['overstrike',[]], ['charset',[]], 
	['pointadjust',[]]]
    end
  end

  def actual_core_tk8x(font, window=nil, option=nil)
    if option == 'compound'
      ""
    elsif option
      if window
	tk_call('font', 'actual', font, "-displayof", window, "-#{option}")
      else
	tk_call('font', 'actual', font, "-#{option}")
      end
    else
      l = tk_split_simplelist(if window
			 	 tk_call('font', 'actual', font, 
					             "-displayof", window)
			      else
			  	 tk_call('font', 'actual', font)
			      end)
      r = []
      while key=l.shift
	if key == '-compound'
	  l.shift
	else
	  r.push [key[1..-1], l.shift]
	end
      end
      r
    end
  end

  def configure_core_tk4x(font, slot, value=None)
    ""
  end

  def configinfo_core_tk4x(font, option=nil)
    # dummy
    if option
      ""
    else
      [['family',[]], ['size',[]], ['weight',[]], ['slant',[]], 
	['underline',[]], ['overstrike',[]], ['charset',[]], 
	['pointadjust',[]]]
    end
  end

  def configure_core_tk8x(font, slot, value=None)
    if slot.kind_of? Hash
      tk_call 'font', 'configure', font, *hash_kv(slot)
    else
      tk_call 'font', 'configure', font, "-#{slot}", value
    end
  end

  def configinfo_core_tk8x(font, option=nil)
    if option == 'compound'
      ""
    elsif option
      tk_call('font', 'configure', font, "-#{option}")
    else
      l = tk_split_simplelist(tk_call('font', 'configure', font))
      r = []
      while key=l.shift
	if key == '-compound'
	  l.shift
	else
	  r.push [key[1..-1], l.shift]
	end
      end
      r
    end
  end

  def delete_core_tk4x
    Tk_FontNameTBL[@id] = nil
    Tk_FontUseTBL.delete_if{|key,value| value == self}
  end

  def delete_core_tk8x
    begin
      tk_call('font', 'delete', @latinfont)
    rescue
    end
    begin
      tk_call('font', 'delete', @kanjifont)
    rescue
    end
    begin
      tk_call('font', 'delete', @compoundfont)
    rescue
    end
    Tk_FontNameTBL[@id] = nil
    Tk_FontUseTBL.delete_if{|key,value| value == self}
  end

  def latin_replace_core_tk4x(ltn)
    create_latinfont_tk4x(ltn)
    @compoundfont[0] = [@latinfont] if JAPANIZED_TK
    @fontslot['font'] = @latinfont
    Tk_FontUseTBL.dup.each{|w, fobj|
      if self == fobj
	begin
	  if w.include?(';')
	    win, tag = w.split(';')
	    winobj = tk_tcl2ruby(win)
#	    winobj.tagfont_configure(tag, {'font'=>@latinfont})
	    if winobj.kind_of? TkText
	      tk_call(win, 'tag', 'configure', tag, '-font', @latinfont)
	    elsif winobj.kind_of? TkCanvas
	      tk_call(win, 'itemconfigure', tag, '-font', @latinfont)
	    elsif winobj.kind_of? TkMenu
	      tk_call(win, 'entryconfigure', tag, '-font', @latinfont)
	    else
	      raise RuntimeError, "unknown widget type"
	    end
	  else
#	    tk_tcl2ruby(w).font_configure('font'=>@latinfont)
	    tk_call(w, 'configure', '-font', @latinfont)
	  end
	rescue
	  Tk_FontUseTBL[w] = nil
	end
      end
    }
    self
  end

  def kanji_replace_core_tk4x(knj)
    return self unless JAPANIZED_TK

    create_kanjifont_tk4x(knj)
    @compoundfont[1] = [@kanjifont]
    @fontslot['kanjifont'] = @kanjifont
    Tk_FontUseTBL.dup.each{|w, fobj|
      if self == fobj
	begin
	  if w.include?(';')
	    win, tag = w.split(';')
	    winobj = tk_tcl2ruby(win)
#	    winobj.tagfont_configure(tag, {'kanjifont'=>@kanjifont})
	    if winobj.kind_of? TkText
	      tk_call(win, 'tag', 'configure', tag, '-kanjifont', @kanjifont)
	    elsif winobj.kind_of? TkCanvas
	      tk_call(win, 'itemconfigure', tag, '-kanjifont', @kanjifont)
	    elsif winobj.kind_of? TkMenu
	      tk_call(win, 'entryconfigure', tag, '-kanjifont', @latinfont)
	    else
	      raise RuntimeError, "unknown widget type"
	    end
	  else
#	    tk_tcl2ruby(w).font_configure('kanjifont'=>@kanjifont)
	    tk_call(w, 'configure', '-kanjifont', @kanjifont)
	  end
	rescue
	  Tk_FontUseTBL[w] = nil
	end
      end
    }
    self
  end

  def latin_replace_core_tk8x(ltn)
    begin
      tk_call('font', 'delete', @latinfont)
    rescue
    end
    create_latinfont(ltn)
    self
  end

  def kanji_replace_core_tk8x(knj)
    begin
      tk_call('font', 'delete', @kanjifont)
    rescue
    end
    create_kanjifont(knj)
    self
  end

  def measure_core_tk4x(window, text)
    0
  end

  def measure_core_tk8x(window, text)
    if window
      number(tk_call('font', 'measure', @compoundfont, 
		     '-displayof', window, text))
    else
      number(tk_call('font', 'measure', @compoundfont, text))
    end
  end

  def metrics_core_tk4x(font, window, option=nil)
    # dummy
    if option
      ""
    else
      [['ascent',[]], ['descent',[]], ['linespace',[]], ['fixed',[]]]
    end
  end

  def metrics_core_tk8x(font, window, option=nil)
    if option
      if window
	number(tk_call('font', 'metrics', font, 
		       "-displayof", window, "-#{option}"))
      else
	number(tk_call('font', 'metrics', font, "-#{option}"))
      end
    else
      l = tk_split_list(if window
			  tk_call('font','metrics',font,"-displayof",window)
			else
			  tk_call('font','metrics',font)
			end)
      r = []
      while key=l.shift
	r.push [key[1..-1], l.shift.to_i]
      end
      r
    end
  end

  ###################################
  # private alias
  ###################################
  case (Tk::TK_VERSION)
  when /^4\.*/
    alias create_latinfont    create_latinfont_tk4x
    alias create_kanjifont    create_kanjifont_tk4x
    alias create_compoundfont create_compoundfont_tk4x
    alias actual_core         actual_core_tk4x
    alias configure_core      configure_core_tk4x
    alias configinfo_core     configinfo_core_tk4x
    alias delete_core         delete_core_tk4x
    alias latin_replace_core  latin_replace_core_tk4x
    alias kanji_replace_core  kanji_replace_core_tk4x
    alias measure_core        measure_core_tk4x
    alias metrics_core        metrics_core_tk4x

  when /^8\.[0123]/
    alias create_latinfont    create_latinfont_tk8x
    alias create_kanjifont    create_kanjifont_tk8x
    alias create_compoundfont create_compoundfont_tk8x
    alias actual_core         actual_core_tk8x
    alias configure_core      configure_core_tk8x
    alias configinfo_core     configinfo_core_tk8x
    alias delete_core         delete_core_tk8x
    alias latin_replace_core  latin_replace_core_tk8x
    alias kanji_replace_core  kanji_replace_core_tk8x
    alias measure_core        measure_core_tk8x
    alias metrics_core        metrics_core_tk8x

  when /^8\.*/
    alias create_latinfont    create_latinfont_tk8x
    alias create_kanjifont    create_kanjifont_tk8x
    alias create_compoundfont create_compoundfont_tk8x
    alias actual_core         actual_core_tk8x
    alias configure_core      configure_core_tk8x
    alias configinfo_core     configinfo_core_tk8x
    alias delete_core         delete_core_tk8x
    alias latin_replace_core  latin_replace_core_tk8x
    alias kanji_replace_core  kanji_replace_core_tk8x
    alias measure_core        measure_core_tk8x
    alias metrics_core        metrics_core_tk8x

  end

  ###################################
  public
  ###################################
  def method_missing(id, *args)
    name = id.id2name
    case args.length
    when 1
      configure name, args[0]
    when 0
      begin
	configinfo name
      rescue
	fail NameError, "undefined local variable or method `#{name}' for #{self.to_s}", error_at
      end
    else
      fail NameError, "undefined method `#{name}' for #{self.to_s}", error_at
    end
  end

  def call_font_configure(path, *args)
    args += hash_kv(args.pop.update(@fontslot))
    tk_call *args
    Tk_FontUseTBL[path] = self
    self
  end

  def used
    ret = []
    Tk_FontUseTBL.each{|key,value|
      if key.include?(';')
	win, tag = key.split(';')
	winobj = tk_tcl2ruby(win)
	if winobj.kind_of? TkText
	  ret.push([winobj, winobj.tagid2obj(tag)])
	elsif winobj.kind_of? TkCanvas
	  if (tagobj = TkcTag.id2obj(winobj, tag)).kind_of? TkcTag
	    ret.push([winobj, tagobj])
	  elsif (tagobj = TkcItem.id2obj(tag)).kind_of? TkcItem
	    ret.push([winobj, tagobj])
	  else
	    ret.push([winobj, tag])
	  end
	elsif winobj.kind_of? TkMenu
	  ret.push([winobj, tag])
	else
	  ret.push([win, tag])
	end
      else
	ret.push(tk_tcl2ruby(key)) if value == self
      end
    }
    ret
  end

  def id
    @id
  end

  def to_eval
    font
  end

  def font
    @compoundfont
  end

  def latin_font
    @latinfont
  end

  def kanji_font
    @kanjifont
  end

  def actual(option=nil)
    actual_core(@compoundfont, nil, option)
  end

  def actual_displayof(window, option=nil)
    window = '.' unless window
    actual_core(@compoundfont, window, option)
  end

  def latin_actual(option=nil)
    actual_core(@latinfont, nil, option)
  end

  def latin_actual_displayof(window, option=nil)
    window = '.' unless window
    actual_core(@latinfont, window, option)
  end

  def kanji_actual(option=nil)
    #if JAPANIZED_TK
    if @kanjifont != ""
      actual_core(@kanjifont, nil, option)
    else
      actual_core_tk4x(nil, nil, option)
    end
  end

  def kanji_actual_displayof(window, option=nil)
    #if JAPANIZED_TK
    if @kanjifont != ""
      window = '.' unless window
      actual_core(@kanjifont, window, option)
    else
      actual_core_tk4x(nil, window, option)
    end
  end

  def [](slot)
    configinfo slot
  end

  def []=(slot, val)
    configure slot, val
  end

  def configure(slot, value=None)
    configure_core(@compoundfont, slot, value)
  end

  def configinfo(slot=nil)
    configinfo_core(@compoundfont, slot)
  end

  def delete
    delete_core
  end

  def latin_configure(slot, value=None)
    if JAPANIZED_TK
      configure_core(@latinfont, slot, value)
    else
      configure(slot, value)
    end
  end

  def latin_configinfo(slot=nil)
    if JAPANIZED_TK
      configinfo_core(@latinfont, slot)
    else
      configinfo(slot)
    end
  end

  def kanji_configure(slot, value=None)
    #if JAPANIZED_TK
    if @kanjifont != ""
      configure_core(@kanjifont, slot, value)
      configure('size'=>configinfo('size')) # to reflect new configuration
    else
      #""
      configure(slot, value)
    end
  end

  def kanji_configinfo(slot=nil)
    #if JAPANIZED_TK
    if @kanjifont != ""
      configinfo_core(@kanjifont, slot)
    else
      #[]
      configinfo(slot)
    end
  end

  def replace(ltn, knj)
    latin_replace(ltn)
    kanji_replace(knj)
    self
  end

  def latin_replace(ltn)
    latin_replace_core(ltn)
    reset_pointadjust
  end

  def kanji_replace(knj)
    kanji_replace_core(knj)
    reset_pointadjust
  end

  def measure(text)
    measure_core(nil, text)
  end

  def measure_displayof(window, text)
    window = '.' unless window
    measure_core(window, text)
  end

  def metrics(option=nil)
    metrics_core(@compoundfont, nil, option)
  end

  def metrics_displayof(window, option=nil)
    window = '.' unless window
    metrics_core(@compoundfont, window, option)
  end

  def latin_metrics(option=nil)
    metrics_core(@latinfont, nil, option)
  end

  def latin_metrics_displayof(window, option=nil)
    window = '.' unless window
    metrics_core(@latinfont, window, option)
  end

  def kanji_metrics(option=nil)
    if JAPANIZED_TK
      metrics_core(@kanjifont, nil, option)
    else
      metrics_core_tk4x(nil, nil, option)
    end
  end

  def kanji_metrics_displayof(window, option=nil)
    if JAPANIZED_TK
      window = '.' unless window
      metrics_core(@kanjifont, window, option)
    else
      metrics_core_tk4x(nil, window, option)
    end
  end

  def reset_pointadjust
    begin
      if /^8\.*/ === Tk::TK_VERSION  && JAPANIZED_TK
        configure('pointadjust' => latin_actual.assoc('size')[1].to_f / 
                                      kanji_actual.assoc('size')[1].to_f )
      end
    rescue
    end
    self
  end

  ###################################
  # public alias
  ###################################
  alias ascii_font             latin_font
  alias create_asciifont       create_latinfont
  alias ascii_actual           latin_actual
  alias ascii_actual_displayof latin_actual_displayof
  alias ascii_configure        latin_configure
  alias ascii_configinfo       latin_configinfo
  alias ascii_replace          latin_replace
  alias ascii_metrics          latin_metrics

end

module TkTreatTagFont
  def font_configinfo
    @parent.tagfont_configinfo(@id)
  end
#  alias font font_configinfo

  def font_configure(slot)
    @parent.tagfont_configure(@id, slot)
  end

  def latinfont_configure(ltn, keys=nil)
    @parent.latintagfont_configure(@id, ltn, keys)
  end
  alias asciifont_configure latinfont_configure

  def kanjifont_configure(knj, keys=nil)
    @parent.kanjitagfont_configure(@id, ltn, keys)
  end

  def font_copy(window, wintag=nil)
    @parent.tagfont_copy(@id, window, wintag)
  end

  def latinfont_copy(window, wintag=nil)
    @parent.latintagfont_copy(@id, window, wintag)
  end
  alias asciifont_copy latinfont_copy

  def kanjifont_copy(window, wintag=nil)
    @parent.kanjitagfont_copy(@id, window, wintag)
  end
end
