#
#  tk/font.rb - the class to treat fonts on Ruby/Tk
#
#                               by  Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

class TkFont
  include Tk
  extend TkCore

  TkCommandNames = ['font'.freeze].freeze

  Tk_FontID = ["@font".freeze, "00000".taint].freeze
  Tk_FontNameTBL = TkCore::INTERP.create_table
  Tk_FontUseTBL  = TkCore::INTERP.create_table

  TkCore::INTERP.init_ip_env{ 
    Tk_FontNameTBL.clear
    Tk_FontUseTBL.clear
  }

  # option_type : default => string
  OptionType = Hash.new(?s)
  OptionType['size'] = ?n
  OptionType['pointadjust'] = ?n
  OptionType['underline'] = ?b
  OptionType['overstrike'] = ?b

  # metric_type : default => num_or_str
  MetricType = Hash.new(?n)
  MetricType['fixed'] = ?b

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
        when /Mincho:Helvetica-Bold-12/
          # Tcl/Tk-JP for UNIX/X
          ltn, knj = tk_split_simplelist(tk_call('font', 'configure', 
                                                 'Mincho:Helvetica-Bold-12', 
                                                 '-compound'))
        else
          # unknown Tcl/Tk-JP
          #platform = tk_call('set', 'tcl_platform(platform)')
          platform = Tk::PLATFORM['platform']
          case platform
          when 'unix'
            ltn = {'family'=>'Helvetica'.freeze, 
                   'size'=>-12, 'weight'=>'bold'.freeze}
            #knj = 'k14'
            #knj = '-misc-fixed-medium-r-normal--14-*-*-*-c-*-jisx0208.1983-0'
            knj = '-*-fixed-bold-r-normal--12-*-*-*-c-*-jisx0208.1983-0'
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
        #platform = tk_call('set', 'tcl_platform(platform)')
        platform = Tk::PLATFORM['platform']
        case platform
        when 'unix'
          ltn = {'family'=>'Helvetica'.freeze, 
                 'size'=>-12, 'weight'=>'bold'.freeze}
        when 'windows'
          ltn = {'family'=>'MS Sans Serif'.freeze, 'size'=>8}
        when 'macintosh'
          ltn = 'system'
        else # unknown
          ltn = 'Helvetica'
        end
      rescue
        ltn = 'Helvetica'
      end

      knj = ltn.dup
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
  class DescendantFont
    def initialize(compound, type)
      unless compound.kind_of?(TkFont)
        fail ArgumentError, "a TkFont object is expected for the 1st argument"
      end
      @compound = compound
      case type
      when 'kanji', 'latin', 'ascii'
        @type = type
      when :kanji, :latin, :ascii
        @type = type.to_s
      else
        fail ArgumentError, "unknown type '#{type}'"
      end
    end

    def dup
      fail RuntimeError, "cannot dupulicate a descendant font"
    end
    def clone
      fail RuntimeError, "cannot clone a descendant font"
    end

    def to_eval
      @compound.__send__(@type + '_font_id')
    end
    def font
      @compound.__send__(@type + '_font_id')
    end

    def [](slot)
      @compound.__send__(@type + '_configinfo', slot)
    end
    def []=(slot, value)
      @compound.__send__(@type + '_configure', slot, value)
      value
    end

    def method_missing(id, *args)
      @compound.__send__(@type + '_' + id.id2name, *args)
    end
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
    fail 'source-font must be a TkFont object' unless font.kind_of? TkFont
    if TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      keys = {}
      font.configinfo.each{|key,value| keys[key] = value }
      TkFont.new(font.latin_font_id, font.kanji_font_id, keys)
    else # ! TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      TkFont.new(font.latin_font_id, font.kanji_font_id, font.configinfo)
    end
  end

  def TkFont.get_obj(name)
    if name =~ /^(@font[0-9]+)(|c|l|k)$/
      Tk_FontNameTBL[$1]
    else
      nil
    end
  end

  def TkFont.init_widget_font(pathname, *args)
    win, tag, key = pathname.split(';')
    key = 'font' if key == nil || key == ''
    path = [win, tag, key].join(';')

    case (Tk::TK_VERSION)
    when /^4\.*/
      regexp = /^-(|kanji)#{key} /

      conf_list = tk_split_simplelist(tk_call(*args)).
        find_all{|prop| prop =~ regexp}.
        collect{|prop| tk_split_simplelist(prop)}

      if conf_list.size == 0
        raise RuntimeError, "the widget may not support 'font' option"
      end

      args << {}

      ltn_key = "-#{key}"
      knj_key = "-kanji#{key}"

      ltn_info = conf_list.find{|conf| conf[0] == ltn_key}
      ltn = ltn_info[-1]
      ltn = nil if ltn == [] || ltn == ""

      knj_info = conf_list.find{|conf| conf[0] == knj_key}
      knj = knj_info[-1]
      knj = nil if knj == [] || knj == ""

      TkFont.new(ltn, knj).call_font_configure([path, key], *args)

    when /^8\.*/
      regexp = /^-#{key} /

      conf_list = tk_split_simplelist(tk_call(*args)).
        find_all{|prop| prop =~ regexp}.
        collect{|prop| tk_split_simplelist(prop)}

      if conf_list.size == 0
        raise RuntimeError, "the widget may not support 'font' option"
      end

      args << {}

      optkey = "-#{key}"

      info = conf_list.find{|conf| conf[0] == optkey}
      fnt = info[-1]
      fnt = nil if fnt == [] || fnt == ""

      unless fnt
        TkFont.new(nil, nil).call_font_configure([path, key], *args)
      else
        begin
          compound = tk_split_simplelist(
              Hash[*tk_split_simplelist(tk_call('font', 'configure', 
                                                fnt))].collect{|key,value|
                [key[1..-1], value]
              }.assoc('compound')[1])
        rescue
          compound = []
        end
        if compound == []
          TkFont.new(fnt).call_font_configure([path, key], *args)
        else
          TkFont.new(compound[0], 
                     compound[1]).call_font_configure([path, key], *args)
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
  # instance methods
  ###################################
  private
  ###################################
  def initialize(ltn=nil, knj=nil, keys=nil)
    # @id = Tk_FontID.join('')
    @id = Tk_FontID.join(TkCore::INTERP._ip_id_)
    Tk_FontID[1].succ!
    Tk_FontNameTBL[@id] = self

    @latin_desscendant = nil
    @kanji_desscendant = nil

    if knj.kind_of?(Hash) && !keys
      keys = knj
      knj = nil
    end

    # compound font check
    if Tk::TK_VERSION == '8.0' && JAPANIZED_TK
      begin
        compound = tk_split_simplelist(tk_call('font', 'configure', 
                                               ltn, '-compound'))
        if knj == nil
          if compound != []
            ltn, knj = compound
          end
        else
          if compound != []
            ltn = compound[0]
          end
          compound = tk_split_simplelist(tk_call('font', 'configure', 
                                                 knj, '-compound'))
          if compound != []
            knj = compound[1]
          end
        end
      rescue
      end
    end

    if ltn
      if JAPANIZED_TK && !knj
        if Tk::TK_VERSION =~ /^4.*/
          knj = DEFAULT_KANJI_FONT_NAME
        else
          knj = ltn 
        end
      end
    else
      ltn = DEFAULT_LATIN_FONT_NAME
      knj = DEFAULT_KANJI_FONT_NAME if JAPANIZED_TK && !knj
    end

    create_compoundfont(ltn, knj, keys)
  end

  def _get_font_info_from_hash(font)
    font = _symbolkey2str(font)
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
      @kanjifont = font.kanji_font_id
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
        if font[:charset] || font['charset']
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
        if font[:charset] || font['charset']
          tk_call('font', 'create', @kanjifont, *hash_kv(font))
        else
          tk_call('font', 'create', @kanjifont, 
                  '-charset', 'jisx0208.1983', *hash_kv(font))
        end
      elsif font.kind_of? Array
        tk_call('font', 'create', @kanjifont, '-copy', array2tk_list(font))
        tk_call('font', 'configure', @kanjifont, '-charset', 'jisx0208.1983')
      elsif font.kind_of? TkFont
        tk_call('font', 'create', @kanjifont, '-copy', font.kanji_font_id)
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
          actual_core(font.kanji_font_id).each{|key,val| keys[key] = val}
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
      unless keys
        keys = {}
      else
        keys = keys.dup
      end
      if (tk_call('font', 'configure', @latinfont, '-underline') == '1' &&
          tk_call('font', 'configure', @kanjifont, '-underline') == '1' &&
          !keys.key?('underline'))
        keys['underline'] = true
      end
      if (tk_call('font', 'configure', @latinfont, '-overstrike') == '1' &&
          tk_call('font', 'configure', @kanjifont, '-overstrike') == '1' &&
          !keys.key?('overstrike'))
        keys['overstrike'] = true
      end

      @fontslot = {'font'=>@compoundfont}
      begin
        tk_call('font', 'create', @compoundfont, 
                '-compound', [@latinfont, @kanjifont], *hash_kv(keys))
      rescue RuntimeError => e
        if ltn == knj
          if e.message =~ /kanji font .* specified/
            tk_call('font', 'delete', @latinfont)
            create_latinfont(DEFAULT_LATIN_FONT_NAME)
            opts = []
            Hash[*(tk_split_simplelist(tk_call('font', 'configure', 
                                               @kanjifont)))].each{|k,v|
              case k
              when '-size', '-weight', '-slant', '-underline', '-overstrike'
                opts << k << v
              end
            }
            tk_call('font', 'configure', @latinfont, *opts)
            tk_call('font', 'create', @compoundfont, 
                    '-compound', [@latinfont, @kanjifont], *hash_kv(keys))

          elsif e.message =~ /ascii font .* specified/
            tk_call('font', 'delete', @kanjifont)
            create_kanjifont(DEFAULT_KANJI_FONT_NAME)
            opts = []
            Hash[*(tk_split_simplelist(tk_call('font', 'configure', 
                                               @latinfont)))].each{|k,v|
              case k
              when '-size', '-weight', '-slant', '-underline', '-overstrike'
                opts << k << v
              end
            }
            tk_call('font', 'configure', @kanjifont, *opts)
            tk_call('font', 'create', @compoundfont, 
                    '-compound', [@latinfont, @kanjifont], *hash_kv(keys))

          else
            raise e
          end
        else
          raise e
        end
      end
    else
      tk_call('font', 'create', @compoundfont)

      latinkeys = {}
      begin
        actual_core(@latinfont).each{|key,val| latinkeys[key] = val}
      rescue
        latinkeys = {}
      end
      if latinkeys != {}
        tk_call('font', 'configure', @compoundfont, *hash_kv(latinkeys))
      end

      if knj
        kanjikeys = {}
        begin
          actual_core(@kanjifont).each{|key,val| kanjikeys[key] = val}
        rescue
          kanjikeys = {}
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
    if option == 'pointadjust' || option == :pointadjust
        1.0
    elsif option
      case OptionType[option.to_s]
      when ?n
        0
      when ?b
        false
      else
        ''
      end
    else
      [['family',''], ['size',0], ['weight',''], ['slant',''], 
        ['underline',false], ['overstrike',false], ['charset',''], 
        ['pointadjust',0]]
    end
  end

  def actual_core_tk8x(font, window=nil, option=nil)
    if option == 'compound' || option == :compound
      ""
    elsif option
      if window
        val = tk_call('font', 'actual', font, 
                      "-displayof", window, "-#{option}")
      else
        val = tk_call('font', 'actual', font, "-#{option}")
      end
      case OptionType[option.to_s]
      when ?n
        num_or_str(val)
      when ?b
        bool(val)
      else
        val
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
          key = key[1..-1]
          val = l.shift
          case OptionType[key]
          when ?n
            r.push [key, num_or_str(val)]
          when ?b
            r.push [key, bool(val)]
          else
            r.push [key, val]
          end
        end
      end
      r
    end
  end

  def configure_core_tk4x(font, slot, value=None)
    #""
    self
  end

  def configinfo_core_tk4x(font, option=nil)
    # dummy
    if TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      if option == 'pointadjust' || option == :pointadjust
        1.0
      elsif option
        case OptionType[option.to_s]
        when ?n
          0
        when ?b
          false
        else
          ''
        end
      else
        [['family',''], ['size',0], ['weight',''], ['slant',''], 
          ['underline',false], ['overstrike',false], ['charset',''], 
          ['pointadjust',1.0]]
      end
    else # ! TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      current_configinfo_core_tk4x(font, option)
    end
  end

  def current_configinfo_core_tk4x(font, option=nil)
    if option
      case OptionType[option.to_s]
      when ?n
        0
      when ?b
        false
      else
        ''
      end
    else
      {'family'=>'', 'size'=>0, 'weight'=>'', 'slant'=>'', 
        'underline'=>false, 'overstrike'=>false, 
        'charset'=>false, 'pointadjust'=>1.0}
    end
  end

  def configure_core_tk8x(font, slot, value=None)
    if JAPANIZED_TK
      begin
        padjust = tk_call('font', 'configure', font, '-pointadjust')
      rescue
        padjust = nil
      end
    else
      padjust = nil
    end
    if slot.kind_of? Hash
      if JAPANIZED_TK && (slot.key?('family') || slot.key?(:family))
        slot = _symbolkey2str(slot)
        configure_core_tk8x(font, 'family', slot.delete('family'))
      end

      if ((slot.key?('size') || slot.key?(:size)) && 
          padjust && !slot.key?('pointadjust') && !slot.key?(:pointadjust))
        tk_call('font', 'configure', font, 
                '-pointadjust', padjust, *hash_kv(slot))
      else
        tk_call('font', 'configure', font, *hash_kv(slot))
      end
    elsif (slot == 'size' || slot == :size) && padjust != nil
      tk_call('font', 'configure', font, 
              "-#{slot}", value, '-pointadjust', padjust)
    elsif JAPANIZED_TK && (slot == 'family' || slot == :family)
      # coumpund font?
      begin
        compound = tk_split_simplelist(tk_call('font', 'configure', 
                                               font, '-compound'))
      rescue
        tk_call('font', 'configure', font, '-family', value)
        return self
      end
      if compound == []
        tk_call('font', 'configure', font, '-family', value)
        return self
      end
      ltn, knj = compound

      lfnt = tk_call('font', 'create', '-copy', ltn)
      begin
        tk_call('font', 'configure', lfnt, '-family', value)
        latin_replace_core_tk8x(lfnt)
      rescue RuntimeError => e
        fail e if $DEBUG
      ensure
        tk_call('font', 'delete', lfnt) if lfnt != ''
      end

      kfnt = tk_call('font', 'create', '-copy', knj)
      begin
        tk_call('font', 'configure', kfnt, '-family', value)
        kanji_replace_core_tk8x(lfnt)
      rescue RuntimeError => e
        fail e if $DEBUG
      ensure
        tk_call('font', 'delete', kfnt) if kfnt != ''
      end
      
    else
      tk_call('font', 'configure', font, "-#{slot}", value)
    end
    self
  end

  def configinfo_core_tk8x(font, option=nil)
    if TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      if option == 'compound' || option == :compound
        ""
      elsif option
        val = tk_call('font', 'configure', font, "-#{option}")
        case OptionType[option.to_s]
        when ?n
          num_or_str(val)
        when ?b
          bool(val)
        else
          val
        end
      else
        l = tk_split_simplelist(tk_call('font', 'configure', font))
        r = []
        while key=l.shift
          if key == '-compound'
            l.shift
          else
            key = key[1..-1]
            val = l.shift
            case OptionType[key]
            when ?n
              r.push [key, num_or_str(val)]
            when ?b
              r.push [key, bool(val)]
            else
              r.push [key, val]
            end
          end
        end
        r
      end
    else # ! TkComm::GET_CONFIGINFOwoRES_AS_ARRAY
      current_configinfo_core_tk8x(font, option)
    end
  end

  def current_configinfo_core_tk8x(font, option=nil)
    if option == 'compound'
      ""
    elsif option
      val = tk_call('font', 'configure', font, "-#{option}")
      case OptionType[option.to_s]
      when ?n
        num_or_str(val)
      when ?b
        bool(val)
      else
        val
      end
    else
      l = tk_split_simplelist(tk_call('font', 'configure', font))
      r = {}
      while key=l.shift
        if key == '-compound'
          l.shift
        else
          key = key[1..-1]
          val = l.shift
          case OptionType[key]
          when ?n
            r.push [key, num_or_str(val)]
          when ?b
            r.push [key, bool(val)]
          else
            r.push [key, val]
          end
        end
      end
      r
    end
  end

  def delete_core_tk4x
    Tk_FontNameTBL.delete(@id)
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
    Tk_FontNameTBL.delete(@id)
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
            win, tag, optkey = w.split(';')
            optkey = 'font' if optkey == nil || optkey == ''
            winobj = tk_tcl2ruby(win)
#           winobj.tagfont_configure(tag, {'font'=>@latinfont})
            if winobj.kind_of? TkText
              tk_call(win, 'tag', 'configure', tag, "-#{optkey}", @latinfont)
            elsif winobj.kind_of? TkCanvas
              tk_call(win, 'itemconfigure', tag, "-#{optkey}", @latinfont)
            elsif winobj.kind_of? TkMenu
              tk_call(win, 'entryconfigure', tag, "-#{optkey}", @latinfont)
            else
              raise RuntimeError, "unknown widget type"
            end
          else
#           tk_tcl2ruby(w).font_configure('font'=>@latinfont)
            tk_call(w, 'configure', '-font', @latinfont)
          end
        rescue
          Tk_FontUseTBL.delete(w)
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
            win, tag, optkey = w.split(';')
            optkey = 'kanjifont' unless optkey
            winobj = tk_tcl2ruby(win)
#           winobj.tagfont_configure(tag, {'kanjifont'=>@kanjifont})
            if winobj.kind_of? TkText
              tk_call(win, 'tag', 'configure', tag, "-#{optkey}", @kanjifont)
            elsif winobj.kind_of? TkCanvas
              tk_call(win, 'itemconfigure', tag, "-#{optkey}", @kanjifont)
            elsif winobj.kind_of? TkMenu
              tk_call(win, 'entryconfigure', tag, "-#{optkey}", @latinfont)
            else
              raise RuntimeError, "unknown widget type"
            end
          else
#           tk_tcl2ruby(w).font_configure('kanjifont'=>@kanjifont)
            tk_call(w, 'configure', '-kanjifont', @kanjifont)
          end
        rescue
          Tk_FontUseTBL.delete(w)
        end
      end
    }
    self
  end

  def latin_replace_core_tk8x(ltn)
    if JAPANIZED_TK
      begin
        tk_call('font', 'delete', '@font_tmp')
      rescue
      end
      begin
        fnt_bup = tk_call('font', 'create', '@font_tmp', '-copy', @latinfont)
      rescue
        #fnt_bup = ''
        fnt_bup = DEFAULT_LATIN_FONT_NAME
      end
    end

    begin
      tk_call('font', 'delete', @latinfont)
    rescue
    end
    create_latinfont(ltn)

    if JAPANIZED_TK
      keys = self.configinfo
      tk_call('font', 'delete', @compoundfont)
      begin
        tk_call('font', 'create', @compoundfont, 
                '-compound', [@latinfont, @kanjifont], *hash_kv(keys))
=begin
        latinkeys = {}
        begin
          actual_core(@latinfont).each{|key,val| latinkeys[key] = val}
        rescue
          latinkeys = {}
        end
        if latinkeys != {}
          tk_call('font', 'configure', @compoundfont, *hash_kv(latinkeys))
        end
=end
      rescue RuntimeError => e
        tk_call('font', 'delete', @latinfont)
        if fnt_bup && fnt_bup != ''
          tk_call('font', 'create', @latinfont, '-copy', fnt_bup)
          tk_call('font', 'create', @compoundfont, 
                  '-compound', [@latinfont, @kanjifont], *hash_kv(keys))
          tk_call('font', 'delete', fnt_bup)
        else
          fail e
        end
      end

    else
      latinkeys = {}
      begin
        actual_core(@latinfont).each{|key,val| latinkeys[key] = val}
      rescue
        latinkeys = {}
      end
      if latinkeys != {}
        tk_call('font', 'configure', @compoundfont, *hash_kv(latinkeys))
      end
    end    
    self
  end

  def kanji_replace_core_tk8x(knj)
    if JAPANIZED_TK
      begin
        tk_call('font', 'delete', '@font_tmp')
      rescue
      end
      begin
        fnt_bup = tk_call('font', 'create', '@font_tmp', '-copy', @kanjifont)
      rescue
        #fnt_bup = ''
        fnt_bup = DEFAULT_KANJI_FONT_NAME
      end
    end

    begin
      tk_call('font', 'delete', @kanjifont)
    rescue
    end
    create_kanjifont(knj)

    if JAPANIZED_TK
      keys = self.configinfo
      tk_call('font', 'delete', @compoundfont)
      begin
        tk_call('font', 'create', @compoundfont, 
                '-compound', [@latinfont, @kanjifont], *hash_kv(keys))
      rescue RuntimeError => e
        tk_call('font', 'delete', @kanjifont)
        if fnt_bup && fnt_bup != ''
          tk_call('font', 'create', @kanjifont, '-copy', fnt_bup)
          tk_call('font', 'create', @compoundfont, 
                  '-compound', [@latinfont, @kanjifont], *hash_kv(keys))
          tk_call('font', 'delete', fnt_bup)
        else
          fail e
        end
      end
    end    
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
    alias create_latinfont        create_latinfont_tk4x
    alias create_kanjifont        create_kanjifont_tk4x
    alias create_compoundfont     create_compoundfont_tk4x
    alias actual_core             actual_core_tk4x
    alias configure_core          configure_core_tk4x
    alias configinfo_core         configinfo_core_tk4x
    alias current_configinfo_core current_configinfo_core_tk4x
    alias delete_core             delete_core_tk4x
    alias latin_replace_core      latin_replace_core_tk4x
    alias kanji_replace_core      kanji_replace_core_tk4x
    alias measure_core            measure_core_tk4x
    alias metrics_core            metrics_core_tk4x

  when /^8\.[0-5]/
    alias create_latinfont        create_latinfont_tk8x
    alias create_kanjifont        create_kanjifont_tk8x
    alias create_compoundfont     create_compoundfont_tk8x
    alias actual_core             actual_core_tk8x
    alias configure_core          configure_core_tk8x
    alias configinfo_core         configinfo_core_tk8x
    alias current_configinfo_core current_configinfo_core_tk8x
    alias delete_core             delete_core_tk8x
    alias latin_replace_core      latin_replace_core_tk8x
    alias kanji_replace_core      kanji_replace_core_tk8x
    alias measure_core            measure_core_tk8x
    alias metrics_core            metrics_core_tk8x

  else
    alias create_latinfont        create_latinfont_tk8x
    alias create_kanjifont        create_kanjifont_tk8x
    alias create_compoundfont     create_compoundfont_tk8x
    alias actual_core             actual_core_tk8x
    alias configure_core          configure_core_tk8x
    alias configinfo_core         configinfo_core_tk8x
    alias current_configinfo_core current_configinfo_core_tk8x
    alias delete_core             delete_core_tk8x
    alias latin_replace_core      latin_replace_core_tk8x
    alias kanji_replace_core      kanji_replace_core_tk8x
    alias measure_core            measure_core_tk8x
    alias metrics_core            metrics_core_tk8x

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
    if path.kind_of?(Array)
      # [path, optkey]
      win, tag = path[0].split(';')
      optkey = path[1].to_s
    else
      win, tag, optkey = path.split(';')
    end

    fontslot = _symbolkey2str(@fontslot)
    if optkey && optkey != ""
      ltn = fontslot.delete('font')
      knj = fontslot.delete('kanjifont')
      fontslot[optkey] = ltn if ltn
      fontslot["kanji#{optkey}"] = knj if knj
    end

    keys = _symbolkey2str(args.pop).update(fontslot)
    args.concat(hash_kv(keys))
    tk_call(*args)
    Tk_FontUseTBL[[win, tag, optkey].join(';')] = self
    self
  end

  def used
    ret = []
    Tk_FontUseTBL.each{|key,value|
      next unless self == value
      if key.include?(';')
        win, tag, optkey = key.split(';')
        winobj = tk_tcl2ruby(win)
        if winobj.kind_of? TkText
          if optkey
            ret.push([winobj, winobj.tagid2obj(tag), optkey])
          else
            ret.push([winobj, winobj.tagid2obj(tag)])
          end
        elsif winobj.kind_of? TkCanvas
          if (tagobj = TkcTag.id2obj(winobj, tag)).kind_of? TkcTag
            if optkey
              ret.push([winobj, tagobj, optkey])
            else
              ret.push([winobj, tagobj])
            end
          elsif (tagobj = TkcItem.id2obj(winobj, tag)).kind_of? TkcItem
            if optkey
              ret.push([winobj, tagobj, optkey])
            else
              ret.push([winobj, tagobj])
            end
          else
            if optkey
              ret.push([winobj, tag, optkey])
            else
              ret.push([winobj, tag])
            end
          end
        elsif winobj.kind_of? TkMenu
          if optkey
            ret.push([winobj, tag, optkey])
          else
            ret.push([winobj, tag])
          end
        else
          if optkey
            ret.push([win, tag, optkey])
          else
            ret.push([win, tag])
          end
        end
      else
        ret.push(tk_tcl2ruby(key))
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
  alias font_id font

  def latin_font_id
    @latinfont
  end

  def latin_font
    # @latinfont
    if @latin_descendant
      @latin_descendant
    else
      @latin_descendant = DescendantFont.new(self, 'latin')
    end
  end
  alias latinfont latin_font

  def kanji_font_id
    @kanjifont
  end

  def kanji_font
    # @kanjifont
    if @kanji_descendant
      @kanji_descendant
    else
      @kanji_descendant = DescendantFont.new(self, 'kanji')
    end
  end
  alias kanjifont kanji_font

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
    val
  end

  def configure(slot, value=None)
    configure_core(@compoundfont, slot, value)
    self
  end

  def configinfo(slot=nil)
    configinfo_core(@compoundfont, slot)
  end

  def current_configinfo(slot=nil)
    current_configinfo_core(@compoundfont, slot)
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
    self
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
    self
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

  def replace(ltn, knj=None)
    knj = ltn if knj == None
    latin_replace(ltn)
    kanji_replace(knj)
    self
  end

  def latin_replace(ltn)
    latin_replace_core(ltn)
    reset_pointadjust
    self
  end

  def kanji_replace(knj)
    kanji_replace_core(knj)
    reset_pointadjust
    self
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
  alias asciifont              latinfont
  alias create_asciifont       create_latinfont
  alias ascii_actual           latin_actual
  alias ascii_actual_displayof latin_actual_displayof
  alias ascii_configure        latin_configure
  alias ascii_configinfo       latin_configinfo
  alias ascii_replace          latin_replace
  alias ascii_metrics          latin_metrics

  ###################################
  def dup
    src = self
    obj = super()
    obj.instance_eval{ initialize(src) }
    obj
  end
  def clone
    src = self
    obj = super()
    obj.instance_eval{ initialize(src) }
    obj
  end
end
