#
#		tktext.rb - Tk text classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require 'tk.rb'

class TkText<TkTextWin
  WidgetClassName = 'Text'.freeze
  TkClassBind::WidgetClassNameTBL[WidgetClassName] = self
  def self.to_eval
    WidgetClassName
  end
  include Scrollable
  def create_self
    tk_call 'text', @path
    @tags = {}
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
  def tag_names(index=None)
    tk_split_list(tk_send('tag', 'names', index)).collect{|elt|
      if not @tags[elt]
	elt
      else
	@tags[elt]
      end
    }
  end
  def window_names
    tk_send('window', 'names').collect{|elt|
      if not @tags[elt]
	elt
      else
	@tags[elt]
      end
    }
  end
  def image_names
    tk_send('image', 'names').collect{|elt|
      if not @tags[elt]
	elt
      else
	@tags[elt]
      end
    }
  end

  def set_insert(index)
    tk_send 'mark', 'set', 'insert', index
  end
  def set_current(index)
    tk_send 'mark', 'set', 'current', index
  end

  def insert(index, chars, *tags)
    super index, chars, tags.collect{|x|_get_eval_string(x)}.join(' ')
  end

  def destroy
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
  end

  def bbox(index)
    inf = tk_send('bbox', index)
    (inf == "")?  [0,0,0,0]: inf
  end
  def dlineinfo(index)
    inf = tk_send('dlineinfo', index)
    (inf == "")?  [0,0,0,0,0]: inf
  end

  def yview(*what)
    tk_send 'yview', *what
  end
  def yview_pickplace(*what)
    tk_send 'yview', '-pickplace', *what
  end

  def xview(*what)
    tk_send 'xview', *what
  end
  def xview_pickplace(*what)
    tk_send 'xview', '-pickplace', *what
  end

  def tag_add(tag,index1,index2=None)
    tk_send 'tag', 'add', tag, index1, index2
  end

  def _tag_bind_core(mode, tag, seq, cmd=Proc.new, args=nil)
    id = install_bind(cmd, args)
    tk_send 'tag', 'bind', tag, "<#{tk_event_sequence(seq)}>", mode + id
    # _addcmd cmd
  end
  private :_tag_bind_core

  def tag_bind(tag, seq, cmd=Proc.new, args=nil)
    _tag_bind_core('', tag, seq, cmd=Proc.new, args=nil)
  end

  def tag_bind_append(tag, seq, cmd=Proc.new, args=nil)
    _tag_bind_core('+', tag, seq, cmd=Proc.new, args=nil)
  end

  def tag_bindinfo(tag, context=nil)
    if context
      (tk_send('tag', 'bind', tag, 
	       "<#{tk_event_sequence(context)}>")).collect{|cmdline|
	if cmdline =~ /^rb_out (c\d+)\s+(.*)$/
	  [Tk_CMDTBL[$1], $2]
	else
	  cmdline
	end
      }
    else
      tk_split_list(tk_send('tag', 'bind', tag)).filter{|seq|
	seq[1..-2].gsub(/></,',')
      }
    end
  end

  def tag_cget(tag, key)
    tk_call @t.path, 'tag', 'cget', tag, "-#{key}"
  end

  def tag_configure(tag, key, val=None)
    if key.kind_of? Hash
      tk_send 'tag', 'configure', tag, *hash_kv(key)
    else
      tk_send 'tag', 'configure', tag, "-#{key}", val
    end
  end

  def configinfo(tag, key=nil)
    if key
      conf = tk_split_list(tk_send('tag','configure',tag,"-#{key}"))
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_send('tag', 'configure', tag)).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end

  def tag_raise(tag, above=None)
    tk_send 'tag', 'raise', tag, above
  end

  def tag_lower(tag, below=None)
    tk_send 'tag', 'lower', tag, below
  end

  def tag_remove(tag, *index)
    tk_send 'tag', 'remove', tag, *index
  end

  def tag_ranges(tag)
    l = tk_split_list(tk_send('tag', 'ranges', tag))
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

  def search_with_length(pat,start,stop=None)
    pat = pat.char if pat.kind_of? Integer
    if stop != None
      return ["", 0] if compare(start,'>=',stop)
      txt = get(start,stop)
      if (pos = txt.index(pat))
	pos = txt[0..(pos-1)].split('').length if pos > 0
	if pat.kind_of? String
	  return [index(start + " + #{pos} chars"), pat.split('').length]
	else
	  return [index(start + " + #{pos} chars"), $&.split('').length]
	end
      else
	return ["", 0]
      end
    else
      txt = get(start,'end - 1 char')
      if (pos = txt.index(pat))
	pos = txt[0..(pos-1)].split('').length if pos > 0
	if pat.kind_of? String
	  return [index(start + " + #{pos} chars"), pat.split('').length]
	else
	  return [index(start + " + #{pos} chars"), $&.split('').length]
	end
      else
	txt = get('1.0','end - 1 char')
	if (pos = txt.index(pat))
	  pos = txt[0..(pos-1)].split('').length if pos > 0
	  if pat.kind_of? String
	    return [index("1.0 + #{pos} chars"), pat.split('').length]
	  else
	    return [index("1.0 + #{pos} chars"), $&.split('').length]
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
    pat = pat.char if pat.kind_of? Integer
    if stop != None
      return ["", 0] if compare(start,'<=',stop)
      txt = get(stop,start)
      if (pos = txt.rindex(pat))
	pos = txt[0..(pos-1)].split('').length if pos > 0
	if pat.kind_of? String
	  return [index(stop + " + #{pos} chars"), pat.split('').length]
	else
	  return [index(stop + " + #{pos} chars"), $&.split('').length]
	end
      else
	return ["", 0]
      end
    else
      txt = get('1.0',start)
      if (pos = txt.rindex(pat))
	pos = txt[0..(pos-1)].split('').length if pos > 0
	if pat.kind_of? String
	  return [index("1.0 + #{pos} chars"), pat.split('').length]
	else
	  return [index("1.0 + #{pos} chars"), $&.split('').length]
	end
      else
	txt = get('1.0','end - 1 char')
	if (pos = txt.rindex(pat))
	  pos = txt[0..(pos-1)].split('').length if pos > 0
	  if pat.kind_of? String
	    return [index("1.0 + #{pos} chars"), pat.split('').length]
	  else
	    return [index("1.0 + #{pos} chars"), $&.split('').length]
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
end

class TkTextTag<TkObject
  $tk_text_tag = 'tag0000'
  def initialize(parent, keys=nil)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    @path = @id = $tk_text_tag
    $tk_text_tag = $tk_text_tag.succ
    tk_call @t.path, "tag", "configure", @id, *hash_kv(keys)
    @t._addtag id, self
  end
  def id
    return @id
  end

  def add(*index)
    tk_call @t.path, 'tag', 'add', @id, *index
  end

  def remove(*index)
    tk_call @t.path, 'tag', 'remove', @id, *index
  end

  def ranges
    l = tk_split_list(tk_call(@t.path, 'tag', 'ranges', @id))
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
    tk_call @t.path, 'tag', 'cget', @id, "-#{key}"
  end

  def configure(key, val=None)
    if key.kind_of? Hash
      tk_call @t.path, 'tag', 'configure', @id, *hash_kv(key)
    else
      tk_call @t.path, 'tag', 'configure', @id, "-#{key}", val
    end
  end
#  def configure(key, value)
#    if value == FALSE
#      value = "0"
#    elsif value.kind_of? Proc
#      value = install_cmd(value)
#    end
#    tk_call @t.path, 'tag', 'configure', @id, "-#{key}", value
#  end

  def configinfo(key=nil)
    if key
      conf = tk_split_list(tk_call(@t.path, 'tag','configure',@id,"-#{key}"))
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_call(@t.path, 'tag', 'configure', @id)).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end

  def bind(seq, cmd=Proc.new, args=nil)
    id = install_bind(cmd, args)
    tk_call @t.path, 'tag', 'bind', @id, "<#{tk_event_sequence(seq)}>", id
    # @t._addcmd cmd
  end

  def bindinfo(context=nil)
    if context
      (tk_call(@t.path, 'tag', 'bind', @id, 
	       "<#{tk_event_sequence(context)}>")).collect{|cmdline|
	if cmdline =~ /^rb_out (c\d+)\s+(.*)$/
	  [Tk_CMDTBL[$1], $2]
	else
	  cmdline
	end
      }
    else
      tk_split_list(tk_call(@t.path, 'tag', 'bind', @id)).filter{|seq|
	seq[1..-2].gsub(/></,',')
      }
    end
  end

  def raise(above=None)
    tk_call @t.path, 'tag', 'raise', @id, above
  end

  def lower(below=None)
    tk_call @t.path, 'tag', 'lower', @id, below
  end

  def destroy
    tk_call @t.path, 'tag', 'delete', @id
  end
end

class TkTextTagSel<TkTextTag
  def initialize(parent, keys=nil)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    @path = @id = 'sel'
    tk_call @t.path, "tag", "configure", @id, *hash_kv(keys)
    @t._addtag id, self
  end
end

class TkTextMark<TkObject
  $tk_text_mark = 'mark0000'
  def initialize(parent, index)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    @path = @id = $tk_text_mark
    $tk_text_mark = $tk_text_mark.succ
    tk_call @t.path, 'mark', 'set', @id, index
    @t._addtag id, self
  end
  def id
    return @id
  end

  def set(where)
    tk_call @t.path, 'mark', 'set', @id, where
  end

  def unset
    tk_call @t.path, 'mark', 'unset', @id
  end
  alias destroy unset

  def gravity
    tk_call @t.path, 'mark', 'gravity', @id
  end

  def gravity=(direction)
    tk_call @t.path, 'mark', 'gravity', @id, direction
  end
end

class TkTextMarkInsert<TkTextMark
  def initialize(parent, index=nil)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    @path = @id = 'insert'
    tk_call @t.path, 'mark', 'set', @id, index if index
    @t._addtag id, self
  end
end

class TkTextMarkCurrent<TkTextMark
  def initialize(parent,index=nil)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    @path = @id = 'current'
    tk_call @t.path, 'mark', 'set', @id, index if index
    @t._addtag id, self
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
    tk_call @t.path, 'window', 'cget', @index, "-#{slot}"
  end

  def configure(slot, value=None)
    if slot.kind_of? Hash
      @id = slot['window'] if slot['window']
      if slot['create']
	self.create=value
	slot['create']=nil
      end
      if slot.size > 0
	tk_call @t.path, 'window', 'configure', @index, *hash_kv(slot)
      end
    else
      @id = value if slot == 'window'
      if slot == 'create'
	self.create=value
      else
	tk_call @t.path, 'window', 'configure', @index, "-#{slot}", value
      end
    end
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

  def configinfo(slot = nil)
    if slot
      conf = tk_split_list(tk_call @t.path, 'window', 'configure', 
			   @index, "-#{slot}")
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_call @t.path, 'window', 'configure', 
		    @index).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
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
    tk_call @t.path, 'image', 'cget', @index, "-#{slot}"
  end

  def configure(slot, value=None)
    if slot.kind_of? Hash
      tk_call @t.path, 'image', 'configure', @index, *hash_kv(slot)
    else
      tk_call @t.path, 'image', 'configure', @index, "-#{slot}", value
    end
  end
#  def configure(slot, value)
#    tk_call @t.path, 'image', 'configure', @index, "-#{slot}", value
#  end

  def image
    tk_call @t.path, 'image', 'configure', @index, '-image'
  end

  def image=(value)
    tk_call @t.path, 'image', 'configure', @index, '-image', value
  end

  def configinfo(slot = nil)
    if slot
      conf = tk_split_list(tk_call @t.path, 'image', 'configure', 
			   @index, "-#{slot}")
      conf[0] = conf[0][1..-1]
      conf
    else
      tk_split_list(tk_call @t.path, 'image', 'configure', 
		    @index).collect{|conf|
	conf[0] = conf[0][1..-1]
	conf
      }
    end
  end
end
