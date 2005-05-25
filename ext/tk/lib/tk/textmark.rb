#
# tk/textmark.rb - methods for treating text marks
#
require 'tk'
require 'tk/text'

class TkTextMark<TkObject
  include TkText::IndexModMethods

  TMarkID_TBL = TkCore::INTERP.create_table
  Tk_TextMark_ID = ['mark'.freeze, '00000'.taint].freeze

  TkCore::INTERP.init_ip_env{ TMarkID_TBL.clear }

  def TkTextMark.id2obj(text, id)
    tpath = text.path
    return id unless TMarkID_TBL[tpath]
    TMarkID_TBL[tpath][id]? TMarkID_TBL[tpath][id]: id
  end

  def initialize(parent, index)
    #unless parent.kind_of?(TkText)
    #  fail ArgumentError, "expect TkText for 1st argument"
    #end
    @parent = @t = parent
    @tpath = parent.path
    # @path = @id = Tk_TextMark_ID.join('')
    @path = @id = Tk_TextMark_ID.join(TkCore::INTERP._ip_id_).freeze
    TMarkID_TBL[@id] = self
    TMarkID_TBL[@tpath] = {} unless TMarkID_TBL[@tpath]
    TMarkID_TBL[@tpath][@id] = self
    Tk_TextMark_ID[1].succ!
    tk_call_without_enc(@t.path, 'mark', 'set', @id, 
                        _get_eval_enc_str(index))
    @t._addtag id, self
  end

  def id
    TkText::IndexString.new(@id)
  end

  def exist?
    #if ( tk_split_simplelist(_fromUTF8(tk_call_without_enc(@t.path, 'mark', 'names'))).find{|id| id == @id } )
    if ( tk_split_simplelist(tk_call_without_enc(@t.path, 'mark', 'names'), false, true).find{|id| id == @id } )
      true
    else
      false
    end
  end

=begin
  # move to TkText::IndexModMethods module
  def +(mod)
    return chars(mod) if mod.kind_of?(Numeric)

    mod = mod.to_s
    if mod =~ /^\s*[+-]?\d/
      TkText::IndexString.new(@id + ' + ' + mod)
    else
      TkText::IndexString.new(@id + ' ' + mod)
    end
  end

  def -(mod)
    return chars(-mod) if mod.kind_of?(Numeric)

    mod = mod.to_s
    if mod =~ /^\s*[+-]?\d/
      TkText::IndexString.new(@id + ' - ' + mod)
    elsif mod =~ /^\s*[-]\s+(\d.*)$/
      TkText::IndexString.new(@id + ' - -' + $1)
    else
      TkText::IndexString.new(@id + ' ' + mod)
    end
  end
=end

  def pos
    @t.index(@id)
  end

  def pos=(where)
    set(where)
  end

  def set(where)
    tk_call_without_enc(@t.path, 'mark', 'set', @id, 
                        _get_eval_enc_str(where))
    self
  end

  def unset
    tk_call_without_enc(@t.path, 'mark', 'unset', @id)
    self
  end
  alias destroy unset

  def gravity
    tk_call_without_enc(@t.path, 'mark', 'gravity', @id)
  end

  def gravity=(direction)
    tk_call_without_enc(@t.path, 'mark', 'gravity', @id, direction)
    #self
    direction
  end

  def next(index = nil)
    if index
      @t.tagid2obj(_fromUTF8(tk_call_without_enc(@t.path, 'mark', 'next', _get_eval_enc_str(index))))
    else
      @t.tagid2obj(_fromUTF8(tk_call_without_enc(@t.path, 'mark', 'next', @id)))
    end
  end

  def previous(index = nil)
    if index
      @t.tagid2obj(_fromUTF8(tk_call_without_enc(@t.path, 'mark', 'previous', _get_eval_enc_str(index))))
    else
      @t.tagid2obj(_fromUTF8(tk_call_without_enc(@t.path, 'mark', 'previous', @id)))
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
    #unless parent.kind_of?(TkText)
    #  fail ArgumentError, "expect TkText for 1st argument"
    #end
    @parent = @t = parent
    @tpath = parent.path
    @path = @id = name
    TMarkID_TBL[@id] = self
    TMarkID_TBL[@tpath] = {} unless TMarkID_TBL[@tpath]
    TMarkID_TBL[@tpath][@id] = self unless TMarkID_TBL[@tpath][@id]
    tk_call_without_enc(@t.path, 'mark', 'set', @id, 
                        _get_eval_enc_str(index)) if index
    @t._addtag id, self
  end
end

class TkTextMarkInsert<TkTextNamedMark
  def self.new(parent,*args)
    super(parent, 'insert', *args)
  end
end

class TkTextMarkCurrent<TkTextNamedMark
  def self.new(parent,*args)
    super(parent, 'current', *args)
  end
end

class TkTextMarkAnchor<TkTextNamedMark
  def self.new(parent,*args)
    super(parent, 'anchor', *args)
  end
end
