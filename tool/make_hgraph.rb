#
# Make dot file of internal class/module hierarchy graph.
#

require 'objspace'

module ObjectSpace
  def self.object_id_of obj
    if obj.kind_of?(ObjectSpace::InternalObjectWrapper)
      obj.internal_object_id
    else
      obj.object_id
    end
  end

  T_ICLASS_NAME = {}

  def self.class_name_of klass
    case klass
    when Class, Module
      # (singleton class).name returns nil
      klass.name || klass.inspect
    when InternalObjectWrapper # T_ICLASS
      if klass.type == :T_ICLASS
        "#<I:#{class_name_of(ObjectSpace.internal_class_of(klass))}>"
      else
        klass.inspect
      end
    else
      klass.inspect
    end
  end

  def self.module_refenreces klass
    h = {} # object_id -> [klass, class_of, super]
    stack = [klass]
    while klass = stack.pop
      obj_id = ObjectSpace.object_id_of(klass)
      next if h.has_key?(obj_id)
      cls = ObjectSpace.internal_class_of(klass)
      sup = ObjectSpace.internal_super_of(klass)
      stack << cls if cls
      stack << sup if sup
      h[obj_id] = [klass, cls, sup].map{|e| ObjectSpace.class_name_of(e)}
    end
    h.values
  end

  def self.module_refenreces_dot klass
    result = []
    rank_set = {}

    result << "digraph mod_h {"
    # result << "  rankdir=LR;"
    module_refenreces(klass).each{|(m, k, s)|
      # next if /singleton/ =~ m
      result << "#{m.dump} -> #{s.dump} [label=\"super\"];"
      result << "#{m.dump} -> #{k.dump} [label=\"klass\"];"

      unless rank = rank_set[m]
        rank = rank_set[m] = 0
      end
      unless rank_set[s]
        rank_set[s] = rank + 1
      end
      unless rank_set[k]
        rank_set[k] = rank
      end
    }

    rs = [] # [[mods...], ...]
    rank_set.each{|m, r|
      rs[r] = [] unless rs[r]
      rs[r] << m
    }

    rs.each{|ms|
      result << "{rank = same; #{ms.map{|m| m.dump}.join(", ")}};"
    }
    result << "}"
    result.join("\n")
  end

  def self.module_refenreces_image klass, file
    dot = module_refenreces_dot(klass)
    img = IO.popen(%W"dot -Tpng", 'r+b') {|io|
      #
      io.puts dot
      io.close_write
      io.read
    }
    File.binwrite(file, img)
  end
end
