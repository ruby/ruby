#
# tk/bind.rb : control event binding
#
require 'tk'

class TkBindTag
  include TkBindCore

  #BTagID_TBL = {}
  BTagID_TBL = TkCore::INTERP.create_table
  Tk_BINDTAG_ID = ["btag".freeze, "00000".taint].freeze

  TkCore::INTERP.init_ip_env{ BTagID_TBL.clear }

  def TkBindTag.id2obj(id)
    BTagID_TBL[id]? BTagID_TBL[id]: id
  end

  def TkBindTag.new_by_name(name, *args, &b)
    return BTagID_TBL[name] if BTagID_TBL[name]
    self.new.instance_eval{
      BTagID_TBL.delete @id
      @id = name
      BTagID_TBL[@id] = self
      bind(*args, &b) if args != []
    }
  end

  def initialize(*args, &b)
    # @id = Tk_BINDTAG_ID.join('')
    @id = Tk_BINDTAG_ID.join(TkCore::INTERP._ip_id_)
    Tk_BINDTAG_ID[1].succ!
    BTagID_TBL[@id] = self
    bind(*args, &b) if args != []
  end

  ALL = self.new_by_name('all')

  def name
    @id
  end

  def to_eval
    @id
  end

  def inspect
    #Kernel.format "#<TkBindTag: %s>", @id
    '#<TkBindTag: ' + @id + '>'
  end
end


class TkBindTagAll<TkBindTag
  def TkBindTagAll.new(*args, &b)
    $stderr.puts "Warning: TkBindTagALL is obsolete. Use TkBindTag::ALL\n"

    TkBindTag::ALL.bind(*args, &b) if args != []
    TkBindTag::ALL
  end
end


class TkDatabaseClass<TkBindTag
  def self.new(name, *args, &b)
    return BTagID_TBL[name] if BTagID_TBL[name]
    super(name, *args, &b)
  end

  def initialize(name, *args, &b)
    @id = name
    BTagID_TBL[@id] = self
    bind(*args, &b) if args != []
  end

  def inspect
    #Kernel.format "#<TkDatabaseClass: %s>", @id
    '#<TkDatabaseClass: ' + @id + '>'
  end
end
