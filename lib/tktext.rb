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

  def configure(keys)
    tk_call @t.path, 'tag', 'configure', @id, *hash_kv(keys)
  end

  def bind(seq, cmd=Proc.new, args=nil)
    id = install_bind(cmd, args)
    tk_call @t, 'tag', 'bind', @id, "<#{seq}>", id
    @t._addcmd cmd
  end

  def lower(below=None)
    tk_call @t.path, 'tag', 'lower', below
  end

  def destroy
    tk_call @t.path, 'tag', 'delete', @id
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
end

class TkTextWindow<TkObject
  def initialize(parent, index, *args)
    if not parent.kind_of?(TkText)
      fail format("%s need to be TkText", parent.inspect)
    end
    @t = parent
    @path = @index = index
    tk_call @t.path, 'window', 'create', index, *args
  end

  def configure(slot, value)
    tk_call @t.path, 'window', 'configure', @index, "-#{slot}", value
  end
end
