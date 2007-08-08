# sentence generator

class SentGen
  def SentGen.each_tree(syntax, sym, limit, &b)
    SentGen.new(syntax).each_tree(sym, limit, &b)
  end

  def SentGen.each_string(syntax, sym, limit, &b)
    SentGen.new(syntax).each_string(sym, limit, &b)
  end

  def initialize(syntax)
    @syntax = syntax
  end

  def self.expand_syntax(syntax)
    syntax = remove_underivable_rules(syntax)
    syntax = expand_justempty_rules(syntax)
    syntax = remove_emptyable_rules(syntax)
    syntax = expand_channel_rules(syntax)

    syntax = expand_noalt_rules(syntax)
    syntax = reorder_rules(syntax)
  end

  def self.remove_underivable_rules(syntax)
    deribable_syms = {}
    changed = true
    while changed
      changed = false
      syntax.each {|sym, rules|
        next if deribable_syms[sym]
        rules.each {|rhs|
          if rhs.all? {|e| String === e || deribable_syms[e] }
            deribable_syms[sym] = true
            changed = true
            break
          end
        }
      }
    end
    result = {}
    syntax.each {|sym, rules|
      next if !deribable_syms[sym]
      rules2 = []
      rules.each {|rhs|
        rules2 << rhs if rhs.all? {|e| String === e || deribable_syms[e] }
      }
      result[sym] = rules2.uniq
    }
    result
  end

  def self.expand_justempty_rules(syntax)
    justempty_syms = {}
    changed = true
    while changed
      changed = false
      syntax.each {|sym, rules|
        next if justempty_syms[sym]
        if rules.all? {|rhs| rhs.all? {|e| justempty_syms[e] } }
          justempty_syms[sym] = true
          changed = true
        end
      }
    end
    result = {}
    syntax.each {|sym, rules|
      result[sym] = rules.map {|rhs| rhs.reject {|e| justempty_syms[e] } }.uniq
    }
    result
  end

  def self.expand_emptyable_syms(rhs, emptyable_syms)
    if rhs.empty?
    elsif rhs.length == 1
      if emptyable_syms[rhs[0]]
        yield rhs
        yield []
      else
        yield rhs
      end
    else
      butfirst = rhs[1..-1]
      if emptyable_syms[rhs[0]]
        expand_emptyable_syms(butfirst, emptyable_syms) {|rhs2| 
          yield [rhs[0]] + rhs2
          yield rhs2
        }
      else
        expand_emptyable_syms(butfirst, emptyable_syms) {|rhs2|
          yield [rhs[0]] + rhs2
        }
      end
    end
  end

  def self.remove_emptyable_rules(syntax)
    emptyable_syms = {}
    changed = true
    while changed
      changed = false
      syntax.each {|sym, rules|
        next if emptyable_syms[sym]
        rules.each {|rhs|
          if rhs.all? {|e| emptyable_syms[e] }
            emptyable_syms[sym] = true
            changed = true
            break
          end
        }
      }
    end
    result = {}
    syntax.each {|sym, rules|
      rules2 = []
      rules.each {|rhs|
        expand_emptyable_syms(rhs, emptyable_syms) {|rhs2|
          rules2 << rhs2
        }
      }
      result[sym] = rules2.uniq
    }
    result
  end

  def self.expand_channel_rules(syntax)
    channel_rules = {}
    syntax.each {|sym, rules|
      channel_rules[sym] = {sym=>true}
      rules.each {|rhs|
        if rhs.length == 1 && Symbol === rhs[0]
          channel_rules[sym][rhs[0]] = true
        end
      }
    }
    changed = true
    while changed
      changed = false 
      channel_rules.each {|sym, set|
        n1 = set.size
        set.keys.each {|s|
          set.update(channel_rules[s])
        }
        n2 = set.size
        changed = true if n1 < n2
      }
    end
    result = {}
    syntax.each {|sym, rules|
      rules2 = []
      channel_rules[sym].each_key {|s|
        syntax[s].each {|rhs|
          unless rhs.length == 1 && Symbol === rhs[0]
            rules2 << rhs
          end
        }
      }
      result[sym] = rules2.uniq
    }
    result
  end

  def self.expand_noalt_rules(syntax)
    noalt_syms = {}
    syntax.each {|sym, rules|
      if rules.length == 1
        noalt_syms[sym] = true
      end
    }
    result = {}
    syntax.each {|sym, rules|
      rules2 = []
      rules.each {|rhs|
        rhs2 = []
        rhs.each {|e|
          if noalt_syms[e]
            rhs2.concat syntax[e][0]
          else
            rhs2 << e
          end
        }
        rules2 << rhs2
      }
      result[sym] = rules2.uniq
    }
    result
  end

  def self.reorder_rules(syntax)
    result = {}
    syntax.each {|sym, rules|
      result[sym] = rules.sort_by {|rhs|
        [rhs.find_all {|e| Symbol === e }.length, rhs.length]
      }
    }
    result
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
      raise "undefined rule: #{sym}" if !rules
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

  def SentGen.subst(obj, target, &b)
    if obj.respond_to? :to_ary
      a = []
      obj.each {|e| a << subst(e, target, &b) }
      a
    elsif target === obj
      yield obj
    else
      obj
    end
  end
end

