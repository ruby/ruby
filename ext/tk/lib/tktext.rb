#
#		tktext.rb - Tk text classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require 'tk.rb'
require 'tkfont'

module TkTreatTextTagFont
  include TkTreatItemFont

  ItemCMD = ['tag'.freeze, 'configure'.freeze].freeze
  def __conf_cmd(idx)
    ItemCMD[idx]
  end

  def __item_pathname(tagOrId)
    if tagOrId.kind_of?(TkTextTag)
      self.path + ';' + tagOrId.id
    else
      self.path + ';' + tagOrId
    end
  end
end

class TkText<TkTextWin
  ItemConfCMD = ['tag'.freeze, 'configure'.freeze].freeze
  include TkTreatTextTagFont
  include Scrollable

  TkCommandNames = ['text'.freeze].freeze
  WidgetClassName = 'Text'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.new(*args, &block)
    obj = super(*args){}
    obj.init_instance_variable
    obj.instance_eval(&block) if defined? yield
    obj
  end

  def init_instance_variable
    @cmdtbl = []
    @tags = {}
  end

  def __destroy_hook__
    TTagID_TBL.delete(@path)
    TMarkID_TBL.delete(@path)
  end

  def create_self(keys)
    if keys and keys != None
      tk_call 'text', @path, *hash_kv(keys)
    else
      tk_call 'text', @path
    end
    init_instance_variable
  end

  def index(index)
    tk_send 'index', index
  end

  def value
    tk_send 'get', "1.0", "end - 1 char"
  end

  def value= (val)
    tk_send 'delete', "1.0", 'end'
    tk_send 'insert', "1.0", val
  end

  def _addcmd(cmd)
    @cmdtbl.push cmd
  end

  def _addtag(name, obj)
    @tags[name] = obj
  end

  def tagid2obj(tagid)
    if @tags[tagid]
      @tags[tagid]
    else
      tagid
    end
  end

  def tag_names(index=None)
    tk_split_simplelist(tk_send('tag', 'names', index)).collect{|elt|
      tagid2obj(elt)
    }
  end

  def mark_names
    tk_split_simplelist(tk_send('mark', 'names')).collect{|elt|
      tagid2obj(elt)
    }
  end

  def mark_gravity(mark, direction=nil)
    if direction
      tk_send 'mark', 'gravity', mark, direction
      self
    else
      tk_send 'mark', 'gravity', mark
    end
  end

  def mark_set(mark, index)
    tk_send 'mark', 'set', mark, index
    self
  end
  alias set_mark mark_set

  def mark_unset(*marks)
    tk_send 'mark', 'unset', *marks
    self
  end
  alias unset_mark mark_unset

  def mark_next(index)
    tagid2obj(tk_send('mark', 'next', index))
  end
  alias next_mark mark_next

  def mark_previous(index)
    tagid2obj(tk_send('mark', 'previous', index))
  end
  alias previous_mark mark_previous

  def image_cget(index, slot)
    case slot.to_s
    when 'text', 'label', 'show', 'data', 'file'
      tk_send('image', 'cget', index, "-#{slot}")
    else
      tk_tcl2ruby(tk_send('image', 'cget', index, "-#{slot}"))
    end
  end

  def image_configure(index, slot, value=None)
    if slot.kind_of? Hash
      tk_send('image', 'configure', index, *hash_kv(slot))
    else
      tk_send('image', 'configure', index, "-#{slot}", value)
    end
    self
  end

  def image_configinfo(index, slot = nil)
    if slot
      case slot.to_s
      when 'text', 'label', 'show', 'data', 'file'
	conf = tk_split_simplelist(tk_send('image', 'configure', 
					   index, "-#{slot}"))
      else
	conf = tk_split_list(tk_send('image', 'configure', 
				     index, "-#{slot}"))
      end
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_simplelist(tk_send('image', 'configure', 
				  index)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	case conf[0]
	when 'text', 'label', 'show', 'data', 'file'
	else
	  if conf[3]
	    if conf[3].index('{')
	      conf[3] = tk_split_list(conf[3]) 
	    else
	      conf[3] = tk_tcl2ruby(conf[3]) 
	    end
	  end
	  if conf[4]
	    if conf[4].index('{')
	      conf[4] = tk_split_list(conf[4]) 
	    else
	      conf[4] = tk_tcl2ruby(conf[4]) 
	    end
	  end
	end
	conf
      }
    end
  end

  def image_names
    tk_split_simplelist(tk_send('image', 'names')).collect{|elt|
      tagid2obj(elt)
    }
  end

  def set_insert(index)
    tk_send 'mark', 'set', 'insert', index
    self
  end

  def set_current(index)
    tk_send 'mark', 'set', 'current', index
    self
  end

  def insert(index, chars, *tags)
    if tags[0].kind_of? Array
      # multiple chars-taglist argument
      args = [chars]
      while tags.size > 0
	tags.shift.collect{|x|_get_eval_string(x)}.join(' ')  # taglist
	args << tags.shift if tags.size > 0                   # chars
      end
      super index, *args
    else
      # single chars-taglist argument
      super index, chars, tags.collect{|x|_get_eval_string(x)}.join(' ')
    end
  end

  def destroy
    @tags = {} unless @tags
    @tags.each_value do |t|
      t.destroy
    end
    super
  end

  def backspace
    self.delete 'insert'
  end

  def compare(idx1, op, idx2)
    bool(tk_send('compare', idx1, op, idx2))
  end

  def debug
    bool(tk_send('debug'))
  end
  def debug=(boolean)
    tk_send 'debug', boolean
    self
  end
  def bbox(index)
    list(tk_send('bbox', index))
  end

  def dlineinfo(index)
    list(tk_send('dlineinfo', index))
  end

  def modified?
    bool(tk_send('edit', 'modified'))
  end
  def modified(mode)
    tk_send('edit', 'modified', mode)
    self
  end
  def edit_redo
    tk_send('edit', 'redo')
    self
  end
  def edit_reset
    tk_send('edit', 'reset')
    self
  end
  def edit_separator
    tk_send('edit', 'separator')
    self
  end
  def edit_undo
    tk_send('edit', 'undo')
    self
  end

  def yview_pickplace(*what)
    tk_send 'yview', '-pickplace', *what
    self
  end

  def xview_pickplace(*what)
    tk_send 'xview', '-pickplace', *what
    self
  end

  def tag_add(tag, index1, index2=None)
    tk_send 'tag', 'add', tag, index1, index2
    self
  end
  alias addtag tag_add
  alias add_tag tag_add

  def tag_delete(*tags)
    tk_send 'tag', 'delete', *tags
    if TkTextTag::TTagID_TBL[@path]
      tags.each{|tag|
	if tag.kind_of? TkTextTag
	  TTagID_TBL[@path].delete(tag.id) 
	else
	  TTagID_TBL[@path].delete(tag) 
	end
      }
    end
    self
  end
  alias deltag tag_delete
  alias delete_tag tag_delete

  def tag_bind(tag, seq, cmd=Proc.new, args=nil)
    _bind([@path, 'tag', 'bind', tag], seq, cmd, args)
    self
  end

  def tag_bind_append(tag, seq, cmd=Proc.new, args=nil)
    _bind_append([@path, 'tag', 'bind', tag], seq, cmd, args)
    self
  end

  def tag_bind_remove(tag, seq)
    _bind_remove([@path, 'tag', 'bind', tag], seq)
    self
  end

  def tag_bindinfo(tag, context=nil)
    _bindinfo([@path, 'tag', 'bind', tag], context)
  end

  def tag_cget(tag, key)
    case key.to_s
    when 'text', 'label', 'show', 'data', 'file'
      tk_call(@path, 'tag', 'cget', tag, "-#{key}")
    when 'font', 'kanjifont'
      fnt = tk_tcl2ruby(tk_send('tag', 'cget', tag, "-#{key}"))
      unless fnt.kind_of?(TkFont)
	fnt = tagfontobj(tag, fnt)
      end
      fnt
    else
      tk_tcl2ruby(tk_call(@path, 'tag', 'cget', tag, "-#{key}"))
    end
  end

  def tag_configure(tag, key, val=None)
    if key.kind_of? Hash
      key = _symbolkey2str(key)
      if ( key['font'] || key['kanjifont'] \
	  || key['latinfont'] || key['asciifont'] )
	tagfont_configure(tag, key)
      else
	tk_send 'tag', 'configure', tag, *hash_kv(key)
      end

    else
      if  key == 'font' || key == :font || 
          key == 'kanjifont' || key == :kanjifont ||
	  key == 'latinfont' || key == :latinfont || 
          key == 'asciifont' || key == :asciifont
	tagfont_configure(tag, {key=>val})
      else
	tk_send 'tag', 'configure', tag, "-#{key}", val
      end
    end
    self
  end

  def tag_configinfo(tag, key=nil)
    if key
      case key.to_s
      when 'text', 'label', 'show', 'data', 'file'
	conf = tk_split_simplelist(tk_send('tag','configure',tag,"-#{key}"))
      when 'font', 'kanjifont'
	conf = tk_split_simplelist(tk_send('tag','configure',tag,"-#{key}") )
	conf[4] = tagfont_configinfo(tag, conf[4])
      else
	conf = tk_split_list(tk_send('tag','configure',tag,"-#{key}"))
      end
      conf[0] = conf[0][1..-1]
      conf
    else
      ret = tk_split_simplelist(tk_send('tag', 'configure', 
					tag)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	case conf[0]
	when 'text', 'label', 'show', 'data', 'file'
	else
	  if conf[3]
	    if conf[3].index('{')
	      conf[3] = tk_split_list(conf[3]) 
	    else
	      conf[3] = tk_tcl2ruby(conf[3]) 
	    end
	  end
	  if conf[4]
	    if conf[4].index('{')
	      conf[4] = tk_split_list(conf[4]) 
	    else
	      conf[4] = tk_tcl2ruby(conf[4]) 
	    end
	  end
	end
	conf
      }
      fontconf = ret.assoc('font')
      if fontconf
	ret.delete_if{|item| item[0] == 'font' || item[0] == 'kanjifont'}
	fontconf[4] = tagfont_configinfo(tag, fontconf[4])
	ret.push(fontconf)
      else
	ret
      end
    end
  end

  def tag_raise(tag, above=None)
    tk_send 'tag', 'raise', tag, above
    self
  end

  def tag_lower(tag, below=None)
    tk_send 'tag', 'lower', tag, below
    self
  end

  def tag_remove(tag, *index)
    tk_send 'tag', 'remove', tag, *index
    self
  end

  def tag_ranges(tag)
    l = tk_split_simplelist(tk_send('tag', 'ranges', tag))
    r = []
    while key=l.shift
      r.push [key, l.shift]
    end
    r
  end

  def tag_nextrange(tag, first, last=None)
    tk_split_list(tk_send('tag', 'nextrange', tag, first, last))
  end

  def tag_prevrange(tag, first, last=None)
    tk_split_list(tk_send('tag', 'prevrange', tag, first, last))
  end

  def window_cget(index, slot)
    case slot.to_s
    when 'text', 'label', 'show', 'data', 'file'
      tk_send('window', 'cget', index, "-#{slot}")
    when 'font', 'kanjifont'
      fnt = tk_tcl2ruby(tk_send('window', 'cget', index, "-#{slot}"))
      unless fnt.kind_of?(TkFont)
	fnt = tagfontobj(index, fnt)
      end
      fnt
    else
      tk_tcl2ruby(tk_send('window', 'cget', index, "-#{slot}"))
    end
  end

  def window_configure(index, slot, value=None)
    if index.kind_of? TkTextWindow
      index.configure(slot, value)
    else
      if slot.kind_of? Hash
	tk_send('window', 'configure', index, *hash_kv(slot))
      else
	tk_send('window', 'configure', index, "-#{slot}", value)
      end
    end
    self
  end

  def window_configinfo(win, slot = nil)
    if slot
      case slot.to_s
      when 'text', 'label', 'show', 'data', 'file'
	conf = tk_split_simplelist(tk_send('window', 'configure', 
					   win, "-#{slot}"))
      else
	conf = tk_split_list(tk_send('window', 'configure', 
				     win, "-#{slot}"))
      end
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_simplelist(tk_send('window', 'configure', 
				  win)).collect{|conflist|
	conf = tk_split_simplelist(conflist)
	conf[0] = conf[0][1..-1]
	case conf[0]
	when 'text', 'label', 'show', 'data', 'file'
	else
	  if conf[3]
	    if conf[3].index('{')
	      conf[3] = tk_split_list(conf[3]) 
	    else
	      conf[3] = tk_tcl2ruby(conf[3]) 
	    end
	  end
	  if conf[4]
	    if conf[4].index('{')
	      conf[4] = tk_split_list(conf[4]) 
	    else
	      conf[4] = tk_tcl2ruby(conf[4]) 
	    end
	  end
	end
	conf
      }
    end
  end

  def window_names
    tk_split_simplelist(tk_send('window', 'names')).collect{|elt|
      tagid2obj(elt)
    }
  end

  def _ktext_length(txt)
    if $KCODE !~ /n/i
      return txt.gsub(/[^\Wa-zA-Z_\d]/, ' ').length
    end

    # $KCODE == 'NONE'
    if JAPANIZED_TK
      tk_call('kstring', 'length', txt).to_i
    else
      begin
	tk_call('encoding', 'convertto', 'ascii', txt).length
      rescue StandardError, NameError
	# sorry, I have no plan
	txt.length
      end
    end
  end
  private :_ktext_length

  def search_with_length(pat,start,stop=None)
    pat = pat.chr if pat.kind_of? Integer
    if stop != None
      return ["", 0] if compare(start,'>=',stop)
      txt = get(start,stop)
      if (pos = txt.index(pat))
	match = $&
	#pos = txt[0..(pos-1)].split('').length if pos > 0
	pos = _ktext_length(txt[0..(pos-1)]) if pos > 0
	if pat.kind_of? String
	  #return [index(start + " + #{pos} chars"), pat.split('').length]
	  return [index(start + " + #{pos} chars"), 
		  _ktext_length(pat), pat.dup]
	else
	  #return [index(start + " + #{pos} chars"), $&.split('').length]
	  return [index(start + " + #{pos} chars"), 
		  _ktext_length(match), match]
	end
      else
	return ["", 0]
      end
    else
      txt = get(start,'end - 1 char')
      if (pos = txt.index(pat))
	match = $&
	#pos = txt[0..(pos-1)].split('').length if pos > 0
	pos = _ktext_length(txt[0..(pos-1)]) if pos > 0
	if pat.kind_of? String
	  #return [index(start + " + #{pos} chars"), pat.split('').length]
	  return [index(start + " + #{pos} chars"), 
		  _ktext_length(pat), pat.dup]
	else
	  #return [index(start + " + #{pos} chars"), $&.split('').length]
	  return [index(start + " + #{pos} chars"), 
		  _ktext_length(match), match]
	end
      else
	txt = get('1.0','end - 1 char')
	if (pos = txt.index(pat))
	  match = $&
	  #pos = txt[0..(pos-1)].split('').length if pos > 0
	  pos = _ktext_length(txt[0..(pos-1)]) if pos > 0
	  if pat.kind_of? String
	    #return [index("1.0 + #{pos} chars"), pat.split('').length]
	    return [index("1.0 + #{pos} chars"), 
		    _ktext_length(pat), pat.dup]
	  else
	    #return [index("1.0 + #{pos} chars"), $&.split('').length]
	    return [index("1.0 + #{pos} chars"), _ktext_length(match), match]
	  end
	else
	  return ["", 0]
	end
      end
    end
  end

  def search(pat,start,stop=None)
    search_with_length(pat,start,stop)[0]
  end

  def rsearch_with_length(pat,start,stop=None)
    pat = pat.chr if pat.kind_of? Integer
    if stop != None
      return ["", 0] if compare(start,'<=',stop)
      txt = get(stop,start)
      if (pos = txt.rindex(pat))
	match = $&
	#pos = txt[0..(pos-1)].split('').length if pos > 0
	pos = _ktext_length(txt[0..(pos-1)]) if pos > 0
	if pat.kind_of? String
	  #return [index(stop + " + #{pos} chars"), pat.split('').length]
	  return [index(stop + " + #{pos} chars"), _ktext_length(pat), pat.dup]
	else
	  #return [index(stop + " + #{pos} chars"), $&.split('').length]
	  return [index(stop + " + #{pos} chars"), _ktext_length(match), match]
	end
      else
	return ["", 0]
      end
    else
      txt = get('1.0',start)
      if (pos = txt.rindex(pat))
	match = $&
	#pos = txt[0..(pos-1)].split('').length if pos > 0
	pos = _ktext_length(txt[0..(pos-1)]) if pos > 0
	if pat.kind_of? String
	  #return [index("1.0 + #{pos} chars"), pat.split('').length]
	  return [index("1.0 + #{pos} chars"), _ktext_length(pat), pat.dup]
	else
	  #return [index("1.0 + #{pos} chars"), $&.split('').length]
	  return [index("1.0 + #{pos} chars"), _ktext_length(match), match]
	end
      else
	txt = get('1.0','end - 1 char')
	if (pos = txt.rindex(pat))
	  match = $&
	  #pos = txt[0..(pos-1)].split('').length if pos > 0
	  pos = _ktext_length(txt[0..(pos-1)]) if pos > 0
	  if pat.kind_of? String
	    #return [index("1.0 + #{pos} chars"), pat.split('').length]
	    return [index("1.0 + #{pos} chars"), _ktext_length(pat), pat.dup]
	  else
	    #return [index("1.0 + #{pos} chars"), $&.split('').length]
	    return [index("1.0 + #{pos} chars"), _ktext_length(match), match]
	  end
	else
	  return ["", 0]
	end
      end
    end
  end

  def rsearch(pat,start,stop=None)
    rsearch_with_length(pat,start,stop)[0]
  end

  def dump(type_info, *index, &block)
    args = type_info.collect{|inf| '-' + inf}
    args << '-command' << block if block
    str = tk_send('dump', *(args + index))
    result = []
    sel = nil
    i = 0
    while i < str.size
      # retrieve key
      idx = str.index(/ /, i)
      result.push str[i..(idx-1)]
      i = idx + 1
      
      # retrieve value
      case result[-1]
      when 'text'
	if str[i] == ?{
	  # text formed as {...}
	  val, i = _retrieve_braced_text(str, i)
	  result.push val
	else
	  # text which may contain backslahes
	  val, i = _retrieve_backslashed_text(str, i)
	  result.push val
	end
      else
	idx = str.index(/ /, i)
	val = str[i..(idx-1)]
	case result[-1]
	when 'mark'
	  case val
	  when 'insert'
	    result.push TkTextMarkInsert.new(self)
	  when 'current'
	    result.push TkTextMarkCurrent.new(self)
	  when 'anchor'
	    result.push TkTextMarkAnchor.new(self)
	  else
	    result.push tk_tcl2ruby(val)
	  end
	when 'tagon'
	  if val == 'sel'
	    if sel
	      result.push sel
	    else
	      result.push TkTextTagSel.new(self)
	    end
	  else
	    result.push tk_tcl2ruby(val)
	  end
	when 'tagoff'
	    result.push tk_tcl2ruby(val)
	when 'window'
	  result.push tk_tcl2ruby(val)
	end
	i = idx + 1
      end

      # retrieve index
      idx = str.index(/ /, i)
      if idx
	result.push str[i..(idx-1)]
	i = idx + 1
      else
	result.push str[i..-1]
	break
      end
    end
    
    kvis = []
    until result.empty?
      kvis.push [result.shift, result.shift, result.shift]
    end
    kvis  # result is [[key1, value1, index1], [key2, value2, index2], ...]
  end

  def _retrieve_braced_text(str, i)
    cnt = 0
    idx = i
    while idx < str.size
      case str[idx]
      when ?{
	cnt += 1
      when ?}
	cnt -= 1
	if cnt == 0
	  break
	end
      end
      idx += 1
    end
    return str[i+1..idx-1], idx + 2
  end
  private :_retrieve_braced_text

  def _retrieve_backslashed_text(str, i)
    j = i
    idx = nil
    loop {
      idx = str.index(/ /, j)
      if str[idx-1] == ?\\
	j += 1
      else
	break
      end
    }
    val = str[i..(idx-1)]
    val.gsub!(/\\( |\{|\})/, '\1')
    return val, idx + 1
  end
  private :_retrieve_backslashed_text

  def dump_all(*index, &block)
    dump(['all'], *index, &block)
  end
  def dump_mark(*index, &block)
    dump(['mark'], *index, &block)
  end
  def dump_tag(*index, &block)
    dump(['tag'], *index, &block)
  end
  def dump_text(*index, &block)
    dump(['text'], *index, &block)
  end
  def dump_window(*index, &block)
    dump(['window'], *index, &block)
  end
  def dump_image(*index, &block)
    dump(['image'], *index, &block)
  end
end

class TkTextTag<TkObject
  include TkTreatTagFont

  TTagID_TBL = TkCore::INTERP.create_table
  Tk_TextTag_ID = ['tag'.freeze, '00000'].freeze

  TkCore::INTERP.init_ip_env{ TTagID_TBL.clear }

  def TkTextTag.id2obj(text, id)
    tpath = text.path
    return id unless TTagID_TBL[tpath]
    TTagID_TBL[tpath][id]? TTagID_TBL[tpath][id]: id
  end

  def initialize(parent, *args)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @parent = @t = parent
    @tpath = parent.path
    @path = @id = Tk_TextTag_ID.join
    TTagID_TBL[@id] = self
    TTagID_TBL[@tpath] = {} unless TTagID_TBL[@tpath]
    TTagID_TBL[@tpath][@id] = self
    Tk_TextTag_ID[1].succ!
    #tk_call @t.path, "tag", "configure", @id, *hash_kv(keys)
    if args != [] then
      keys = args.pop
      if keys.kind_of? Hash then
	add(*args) if args != []
	configure(keys)
      else
	args.push keys
	add(*args)
      end
    end
    @t._addtag id, self
  end

  def id
    @id
  end

  def first
    @id + '.first'
  end

  def last
    @id + '.last'
  end

  def add(*index)
    tk_call @t.path, 'tag', 'add', @id, *index
    self
  end

  def remove(*index)
    tk_call @t.path, 'tag', 'remove', @id, *index
    self
  end

  def ranges
    l = tk_split_simplelist(tk_call(@t.path, 'tag', 'ranges', @id))
    r = []
    while key=l.shift
      r.push [key, l.shift]
    end
    r
  end

  def nextrange(first, last=None)
    tk_split_list(tk_call(@t.path, 'tag', 'nextrange', @id, first, last))
  end

  def prevrange(first, last=None)
    tk_split_list(tk_call(@t.path, 'tag', 'prevrange', @id, first, last))
  end

  def [](key)
    cget key
  end

  def []=(key,val)
    configure key, val
  end

  def cget(key)
    case key.to_s
    when 'text', 'label', 'show', 'data', 'file'
      tk_call @t.path, 'tag', 'cget', @id, "-#{key}"
    when 'font', 'kanjifont'
      fnt = tk_tcl2ruby(tk_call(@t.path, 'tag', 'cget', @id, "-#{key}"))
      unless fnt.kind_of?(TkFont)
	fnt = tagfontobj(@id, fnt)
      end
      fnt
    else
      tk_tcl2ruby(tk_call(@t.path, 'tag', 'cget', @id, "-#{key}"))
    end
  end

  def configure(key, val=None)
    @t.tag_configure @id, key, val
  end
#  def configure(key, val=None)
#    if key.kind_of? Hash
#      tk_call @t.path, 'tag', 'configure', @id, *hash_kv(key)
#    else
#      tk_call @t.path, 'tag', 'configure', @id, "-#{key}", val
#    end
#  end
#  def configure(key, value)
#    if value == FALSE
#      value = "0"
#    elsif value.kind_of? Proc
#      value = install_cmd(value)
#    end
#    tk_call @t.path, 'tag', 'configure', @id, "-#{key}", value
#  end

  def configinfo(key=nil)
    @t.tag_configinfo @id, key
  end

  def bind(seq, cmd=Proc.new, args=nil)
    _bind([@t.path, 'tag', 'bind', @id], seq, cmd, args)
    self
  end

  def bind_append(seq, cmd=Proc.new, args=nil)
    _bind_append([@t.path, 'tag', 'bind', @id], seq, cmd, args)
    self
  end

  def bind_remove(seq)
    _bind_remove([@t.path, 'tag', 'bind', @id], seq)
    self
  end

  def bindinfo(context=nil)
    _bindinfo([@t.path, 'tag', 'bind', @id], context)
  end

  def raise(above=None)
    tk_call @t.path, 'tag', 'raise', @id, above
    self
  end

  def lower(below=None)
    tk_call @t.path, 'tag', 'lower', @id, below
    self
  end

  def destroy
    tk_call @t.path, 'tag', 'delete', @id
    TTagID_TBL[@tpath].delete(@id) if TTagID_TBL[@tpath]
    self
  end
end

class TkTextNamedTag<TkTextTag
  def self.new(parent, name, *args)
    if TTagID_TBL[parent.path] && TTagID_TBL[parent.path][name]
      tagobj = TTagID_TBL[parent.path][name]
      if args != [] then
	keys = args.pop
	if keys.kind_of? Hash then
	  tagobj.add(*args) if args != []
	  tagobj.configure(keys)
	else
	  args.push keys
	  tagobj.add(*args)
	end
      end
      return tagobj
    else
      super(parent, name, *args)
    end
  end

  def initialize(parent, name, *args)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @parent = @t = parent
    @tpath = parent.path
    @path = @id = name
    TTagID_TBL[@tpath] = {} unless TTagID_TBL[@tpath]
    TTagID_TBL[@tpath][@id] = self unless TTagID_TBL[@tpath][@id]
    #if mode
    #  tk_call @t.path, "addtag", @id, *args
    #end
    if args != [] then
      keys = args.pop
      if keys.kind_of? Hash then
	add(*args) if args != []
	configure(keys)
      else
	args.push keys
	add(*args)
      end
    end
    @t._addtag id, self
  end
end

class TkTextTagSel<TkTextNamedTag
  def self.new(parent, *args)
    super(parent, 'sel', *args)
  end
end

class TkTextMark<TkObject
  TMarkID_TBL = TkCore::INTERP.create_table
  Tk_TextMark_ID = ['mark'.freeze, '00000'].freeze

  TkCore::INTERP.init_ip_env{ TMarkID_TBL.clear }

  def TkTextMark.id2obj(text, id)
    tpath = text.path
    return id unless TMarkID_TBL[tpath]
    TMarkID_TBL[tpath][id]? TMarkID_TBL[tpath][id]: id
  end

  def initialize(parent, index)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @parent = @t = parent
    @tpath = parent.path
    @path = @id = Tk_TextMark_ID.join
    TMarkID_TBL[@id] = self
    TMarkID_TBL[@tpath] = {} unless TMarkID_TBL[@tpath]
    TMarkID_TBL[@tpath][@id] = self
    Tk_TextMark_ID[1].succ!
    tk_call @t.path, 'mark', 'set', @id, index
    @t._addtag id, self
  end

  def id
    @id
  end

  def +(mod)
    @id + ' + ' + mod
  end
  def -(mod)
    @id + ' - ' + mod
  end

  def set(where)
    tk_call @t.path, 'mark', 'set', @id, where
    self
  end

  def unset
    tk_call @t.path, 'mark', 'unset', @id
    self
  end
  alias destroy unset

  def gravity
    tk_call @t.path, 'mark', 'gravity', @id
  end

  def gravity=(direction)
    tk_call @t.path, 'mark', 'gravity', @id, direction
    self
  end

  def next(index = nil)
    if index
      @t.tagid2obj(tk_call(@t.path, 'mark', 'next', index))
    else
      @t.tagid2obj(tk_call(@t.path, 'mark', 'next', @id))
    end
  end

  def previous(index = nil)
    if index
      @t.tagid2obj(tk_call(@t.path, 'mark', 'previous', index))
    else
      @t.tagid2obj(tk_call(@t.path, 'mark', 'previous', @id))
    end
  end
end

class TkTextNamedMark<TkTextMark
  def self.new(parent, name, *args)
    if TMarkID_TBL[parent.path] && TMarkID_TBL[parent.path][name]
      return TMarkID_TBL[parent.path][name]
    else
      super(parent, name, *args)
    end
  end

  def initialize(parent, name, index=nil)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @parent = @t = parent
    @tpath = parent.path
    @path = @id = name
    TMarkID_TBL[@id] = self
    TMarkID_TBL[@tpath] = {} unless TMarkID_TBL[@tpath]
    TMarkID_TBL[@tpath][@id] = self unless TMarkID_TBL[@tpath][@id]
    tk_call @t.path, 'mark', 'set', @id, index if index
    @t._addtag id, self
  end
end

class TkTextMarkInsert<TkTextNamedMark
  def self.new(parent,*args)
    super(parent, 'insert', *args)
  end
end

class TkTextMarkCurrent<TkTextMark
  def self.new(parent,*args)
    super(parent, 'current', *args)
  end
end

class TkTextMarkAnchor<TkTextMark
  def self.new(parent,*args)
    super(parent, 'anchor', *args)
  end
end

class TkTextWindow<TkObject
  def initialize(parent, index, keys)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    if index == 'end'
      @path = TkTextMark.new(@t, tk_call(@t.path, 'index', 'end - 1 chars'))
    elsif index.kind_of? TkTextMark
      if tk_call(@t.path,'index',index.path) == tk_call(@t.path,'index','end')
	@path = TkTextMark.new(@t, tk_call(@t.path, 'index', 'end - 1 chars'))
      else
	@path = TkTextMark.new(@t, tk_call(@t.path, 'index', index.path))
      end
    else
      @path = TkTextMark.new(@t, tk_call(@t.path, 'index', index))
    end
    @path.gravity = 'left'
    @index = @path.path
    keys = _symbolkey2str(keys)
    @id = keys['window']
    if keys['create']
      @p_create = keys['create']
      if @p_create.kind_of? Proc
	keys['create'] = install_cmd(proc{@id = @p_create.call; @id.path})
      end
    end
    tk_call @t.path, 'window', 'create', @index, *hash_kv(keys)
  end

  def [](slot)
    cget(slot)
  end
  def []=(slot, value)
    configure(slot, value)
  end

  def cget(slot)
    @t.window_cget(@index, slot)
  end

  def configure(slot, value=None)
    if slot.kind_of? Hash
      slot = _symbolkey2str(slot)
      @id = slot['window'] if slot['window']
      if slot['create']
	self.create=value
	slot['create']=nil
      end
      if slot.size > 0
	tk_call(@t.path, 'window', 'configure', @index, *hash_kv(slot))
      end
    else
      @id = value if slot == 'window' || slot == :window
      if slot == 'create' || slot == :create
	self.create=value
      else
	tk_call(@t.path, 'window', 'configure', @index, "-#{slot}", value)
      end
    end
    self
  end

  def configinfo(slot = nil)
    @t.window_configinfo(@index, slot)
  end

  def window
    @id
  end

  def window=(value)
    tk_call @t.path, 'window', 'configure', @index, '-window', value
    @id = value
  end

  def create
    @p_create
  end

  def create=(value)
    @p_create = value
    if @p_create.kind_of? Proc
      value = install_cmd(proc{@id = @p_create.call})
    end
    tk_call @t.path, 'window', 'configure', @index, '-create', value
  end
end

class TkTextImage<TkObject
  def initialize(parent, index, keys)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    if index == 'end'
      @path = TkTextMark.new(@t, tk_call(@t.path, 'index', 'end - 1 chars'))
    elsif index.kind_of? TkTextMark
      if tk_call(@t.path,'index',index.path) == tk_call(@t.path,'index','end')
	@path = TkTextMark.new(@t, tk_call(@t.path, 'index', 'end - 1 chars'))
      else
	@path = TkTextMark.new(@t, tk_call(@t.path, 'index', index.path))
      end
    else
      @path = TkTextMark.new(@t, tk_call(@t.path, 'index', index))
    end
    @path.gravity = 'left'
    @index = @path.path
    @id = tk_call(@t.path, 'image', 'create', @index, *hash_kv(keys))
  end

  def [](slot)
    cget(slot)
  end
  def []=(slot, value)
    configure(slot, value)
  end

  def cget(slot)
    @t.image_cget(@index, slot)
  end

  def configure(slot, value=None)
    @t.image_configure(@index, slot, value)
    self
  end
#  def configure(slot, value)
#    tk_call @t.path, 'image', 'configure', @index, "-#{slot}", value
#  end

  def configinfo(slot = nil)
    @t.image_configinfo(@index, slot)
  end

  def image
    img = tk_call(@t.path, 'image', 'configure', @index, '-image')
    TkImage::Tk_IMGTBL[img]? TkImage::Tk_IMGTBL[img] : img
  end

  def image=(value)
    tk_call @t.path, 'image', 'configure', @index, '-image', value
    self
  end
end
