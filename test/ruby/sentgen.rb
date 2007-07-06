# sentence generator

class SentGen
  def initialize(syntax)
    @syntax = syntax
  end

  def each_tree(sym, limit)
    generate_from_sym(sym, limit) {|_, tree|
      yield tree
    }
    nil
  end

  def each_string(sym, limit)
    generate_from_sym(sym, limit) {|_, tree|
      yield [tree].join('')
    }
    nil
  end

  def generate_from_sym(sym, limit, &b)
    return if limit < 0
    if String === sym
      yield limit, sym
    else
      rules = @syntax[sym]
      rules.each {|rhs|
        if rhs.length == 1 || rules.length == 1
          limit1 = limit
        else
          limit1 = limit-1
        end
        generate_from_rhs(rhs, limit1, &b)
      }
    end
    nil
  end

  def generate_from_rhs(rhs, limit)
    return if limit < 0
    if rhs.empty?
      yield limit, []
    else
      generate_from_sym(rhs[0], limit) {|limit1, child|
        generate_from_rhs(rhs[1..-1], limit1) {|limit2, arr|
          yield limit2, [child, *arr]
        }
      }
    end
    nil
  end
end

