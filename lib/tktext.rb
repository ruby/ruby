#
#		tktext.rb - Tk text classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>

require 'tk.rb'

class TkText<TkTextWin
  include Scrollable
  def create_self
    tk_call 'text', @path
    @tags = {}
  end
  def index(index)
    tk_send 'index', index
  end
  def value
    tk_send 'get', "1.0", "end"
  end
  def value= (val)
    tk_send 'delete', "1.0", 'end'
    tk_send 'insert', "1.0", val
  end
  def _addcmd(cmd)
    @cmdtbl.push id
  end
  def _addtag(name, obj)
    @tags[name] = obj
  end
  def tag_names(index=nil)
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

  def nextrange(first, last=nil)
    tk_split_list(tk_call(@t.path, 'tag', 'nextrange', @id, first, last))
  end

  def prevrange(first, last=nil)
    tk_split_list(tk_call(@t.path, 'tag', 'prevrange', @id, first, last))
    l = tk_split_list(tk_call(@t.path, 'tag', 'prevrange', @id, first, last))
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

  def configure(key, val=nil)
    if key.kind_of? Hash
      tk_call @t.path, 'tag', 'configure', @id, *hash_kv(key)
    else
      tk_call @t.path, 'tag', 'configure', @id, "-#{key}", val
    end
  end

  def configinfo
    tk_split_list(tk_call(@t.path, 'tag', 'configure', @id))
  end

  def bind(seq, cmd=Proc.new, args=nil)
    id = install_bind(cmd, args)
    tk_call @t.path, 'tag', 'bind', @id, "<#{seq}>", id
    @t._addcmd cmd
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

  def configure(slot, value)
    @id = value if slot == 'window'
    if slot == 'create'
      self.create=value
    else
      tk_call @t.path, 'window', 'configure', @index, "-#{slot}", value
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

  def configure(slot, value)
    tk_call @t.path, 'image', 'configure', @index, "-#{slot}", value
  end

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
