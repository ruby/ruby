class TkFont
  include Tk
  extend TkCore

  Tk_FontID = [0]
  Tk_FontNameTBL = {}
  Tk_FontUseTBL = {}

  DEFAULT_LATIN_FONT_NAME = 'a14'.freeze
  DEFAULT_KANJI_FONT_NAME = 'k14'.freeze

  ###################################
  # class methods
  ###################################
  def TkFont.families(window=nil)
    case (Tk::TK_VERSION)
    when /^4.*/
      ['fixed']

    when /^8.*/
      if window
	list(tk_call('font', 'families', '-displayof', window))
      else
	list(tk_call('font', 'families'))
      end
    end
  end

  def TkFont.names
    r = []
    case (Tk::TK_VERSION)
    when /^4.*/
      r += ['fixed', 'a14', 'k14']
      Tk_FontNameTBL.each_value{|obj| r.push(obj)}
    when /^8.*/
      list(tk_call('font', 'names')).each{|f|
	if f =~ /^(@font[0-9]+)(c|l|k)$/
	  r.push(Tk_FontNameTBL[$1]) if $2 == 'c'
	else
	  r.push(f)
	end
      }
    end
    r
  end

  ###################################
  private
  ###################################
  def initialize(ltn=nil, knj=nil, keys=nil)
    @id = format("@font%.4d", Tk_FontID[0])
    Tk_FontID[0] += 1
    Tk_FontNameTBL[@id] = self

    ltn = DEFAULT_LATIN_FONT_NAME unless ltn
    create_latinfont(ltn)

    knj = DEFAULT_KANJI_FONT_NAME unless knj
    create_kanjifont(knj)

    create_compoundfont(keys)
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

    Array([foundry, family, weight, slant, swidth, adstyle, 
	    pixels, points, resx, resy, space, avgWidth, charset, encoding])
  end

  def create_latinfont_tk4x(font=nil)
    if font.kind_of? Hash
      @latinfont = '-' + _get_font_info_from_hash(font).join('-') + '-'

    elsif font.kind_of? Array
      finfo = {}
      finfo['family'] = font[0].to_s
      if font[1] && font[1] != '0' && font[1] =~ /^(|\+|-)([0-9]+)$/
	if $1 == '-'
	  finfo['pixels'] = font[1].to_s
	else
	  finfo['points'] = font[1].to_s
	end
      end
      finfo[2..-1].each{|style|
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
      @latinfont = font

    end
  end

  def create_kanjifont_tk4x(font=nil)
    if font.kind_of? Hash
      @kanjifont = '-' + _get_font_info_from_hash(font).join('-') + '-'

    elsif font.kind_of? Array
      finfo = {}
      finfo['family'] = font[0].to_s
      if font[1] && font[1] != '0' && font[1] =~ /^(|\+|-)([0-9]+)$/
	if $1 == '-'
	  finfo['pixels'] = $2
	else
	  finfo['points'] = $2
	end
      else
	finfo['points'] = '13'
      end
      finfo[2..-1].each{|style|
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
      @kanjifont = font

    end
  end

  def create_compoundfont_tk4x(keys)
    @compoundfont = [[@latinfont], [@kanjifont]]
    @fontslot = {'font'=>@latinfont, 'kanjifont'=>@kanjifont}
  end

  def create_latinfont_tk80(font=nil)
    @latinfont = @id + 'l'

    if font.kind_of? Hash
      tk_call('font', 'create', @latinfont, *hash_kv(font))
    elsif font.kind_of? Array
      tk_call('font', 'create', @latinfont, '-copy', array2tk_list(font))
    elsif font.kind_of? TkFont
      tk_call('font', 'create', @latinfont, '-copy', font.latin_font)
    else
      tk_call('font', 'create', @latinfont, '-copy', font)
    end
  end

  def create_kanjifont_tk80(font=nil)
    @kanjifont = @id + 'k'

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

    else
      tk_call('font', 'create', @kanjifont, '-copy', font, 
	      '-charset', 'jisx0208.1983')

    end
  end

  def create_compoundfont_tk80(keys)
    @compoundfont = @id + 'c'
    @fontslot = {'font'=>@compoundfont}
    tk_call('font', 'create', @compoundfont, 
	    '-compound', "#{@latinfont} #{@kanjifont}", *hash_kv(keys))
  end

  def set_font_core_tk4x(window)
    Tk_FontUseTBL[window.path] = @id
    window.configure(@fontslot)
  end

  def set_font_core_tk80(window)
    window.configure(@fontslot)
  end

  def actual_core_tk4x(font, window=nil, option=nil)
    # dummy
    if option
      ""
    else
      Array([ ['family',[]], ['size',[]], ['weight',[]], ['slant',[]], 
	      ['underline',[]], ['overstrike',[]], ['charset',[]], 
	      ['pointadjust',[]] ])
    end
  end

  def actual_core_tk80(font, window=nil, option=nil)
    if option == 'compound'
      ""
    elsif option
      if window
	tk_call('font', 'actual', font, "-#{option}")
      else
	tk_call('font', 'actual', font, "-displayof", window, "-#{option}")
      end
    else
      l = tk_split_list(if window
			  tk_call('font', 'actual', font, "-displayof", window)
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
      Array([ ['family',[]], ['size',[]], ['weight',[]], ['slant',[]], 
	      ['underline',[]], ['overstrike',[]], ['charset',[]], 
	      ['pointadjust',[]] ])
    end
  end

  def configure_core_tk80(font, slot, value=None)
    if slot.kind_of? Hash
      tk_call 'font', 'configure', font, *hash_kv(slot)
    else
      tk_call 'font', 'configure', font, "-#{slot}", value
    end
  end

  def configinfo_core_tk80(font, option=nil)
    if option == 'compound'
      ""
    elsif option
      tk_call('font', 'configure', font, "-#{option}")
    else
      l = tk_split_list(tk_call('font', 'configure', font))
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

  def latin_replace_core_tk4x(ltn)
    create_latinfont_tk4x(ltn)
    @compoundfont[0] = [@latinfont]
    @fontslot['font'] = @latinfont
    Tk_FontUseTBL.dup.each{|w, id|
      if id == @id
	begin
	  w.configure('font', @latinfont)
	rescue
	  Tk_FontUseTBL[w] = nil
	end
      end
    }
    self
  end

  def kanji_replace_core_tk4x(knj)
    create_kanjifont_tk4x(knj)
    @compoundfont[1] = [@kanjifont]
    @fontslot['kanjifont'] = @kanjifont
    Tk_FontUseTBL.dup.each{|w, id|
      if id == @id
	begin
	  w.configure('kanjifont', @kanjifont)
	rescue
	  Tk_FontUseTBL[w] = nil
	end
      end
    }
    self
  end

  def latin_replace_core_tk80(ltn)
    tk_call('font', 'delete', @latinfont)
    create_latinfont_tk80(ltn)
    self
  end

  def kanji_replace_core_tk80(knj)
    tk_call('font', 'delete', @kanjifont)
    create_kanjifont_tk80(knj)
    self
  end

  def measure_core_tk4x(window, text)
    0
  end

  def measure_core_tk80(window, text)
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
      Array([ ['ascent',[]], ['descent',[]], ['linespace',[]], ['fixed',[]] ])
    end
  end

  def metrics_core_tk80(font, window, option=nil)
    if option
      if window
	number(tk_call('font', 'metrics', font, "-#{option}"))
      else
	number(tk_call('font', 'metrics', font, 
		       "-displayof", window, "-#{option}"))
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
  when /^4.*/
    alias create_latinfont    create_latinfont_tk4x
    alias create_kanjifont    create_kanjifont_tk4x
    alias create_compoundfont create_compoundfont_tk4x
    alias set_font_core       set_font_core_tk4x
    alias actual_core         actual_core_tk4x
    alias configure_core      configure_core_tk4x
    alias configinfo_core     configinfo_core_tk4x
    alias latin_replace_core  latin_replace_core_tk4x
    alias kanji_replace_core  kanji_replace_core_tk4x
    alias measure_core        measure_core_tk4x
    alias metrics_core        metrics_core_tk4x

  when /^8\.0/
    alias create_latinfont    create_latinfont_tk80
    alias create_kanjifont    create_kanjifont_tk80
    alias create_compoundfont create_compoundfont_tk80
    alias set_font_core       set_font_core_tk80
    alias actual_core         actual_core_tk80
    alias configure_core      configure_core_tk80
    alias configinfo_core     configinfo_core_tk80
    alias latin_replace_core  latin_replace_core_tk80
    alias kanji_replace_core  kanji_replace_core_tk80
    alias measure_core        measure_core_tk80
    alias metrics_core        metrics_core_tk80

  end

  ###################################
  public
  ###################################
  def set_font(window)
    set_font_core(window)
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
    actual_core(@kanjifont, nil, option)
  end

  def kanji_actual_displayof(window, option=nil)
    window = '.' unless window
    actual_core(@kanjifont, window, option)
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

  def latin_configure(slot, value=None)
    configure_core(@latinfont, slot, value)
  end

  def latin_configinfo(slot=nil)
    configinfo_core(@latinfont, slot)
  end

  def kanji_configure(slot, value=None)
    configure_core(@kanjifont, slot, value)
  end

  def kanji_configinfo(slot=nil)
    configinfo_core(@kanjifont, slot)
  end

  def replace(ltn, knj)
    latin_replace(ltn)
    kanji_replace(ltn)
  end

  def latin_replace(ltn)
    latin_replace_core(ltn)
  end

  def kanji_replace(knj)
    kanji_replace_core(knj)
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
    metrics_core(@kanjifont, nil, option)
  end

  def kanji_metrics_displayof(window, option=nil)
    window = '.' unless window
    metrics_core(@kanjifont, window, option)
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
