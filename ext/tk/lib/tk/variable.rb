#
# tk/variable.rb : treat Tk variable object
#
require 'tk'

class TkVariable
  include Tk
  extend TkCore

  include Comparable

  #TkCommandNames = ['tkwait'.freeze].freeze
  TkCommandNames = ['vwait'.freeze].freeze

  #TkVar_CB_TBL = {}
  #TkVar_ID_TBL = {}
  TkVar_CB_TBL = TkCore::INTERP.create_table
  TkVar_ID_TBL = TkCore::INTERP.create_table
  Tk_VARIABLE_ID = ["v".freeze, "00000".taint].freeze

  #TkCore::INTERP.add_tk_procs('rb_var', 'args', 
  #     "ruby [format \"TkVariable.callback %%Q!%s!\" $args]")
TkCore::INTERP.add_tk_procs('rb_var', 'args', <<-'EOL')
    if {[set st [catch {eval {ruby_cmd TkVariable callback} $args} ret]] != 0} {
       set idx [string first "\n\n" $ret]
       if {$idx > 0} {
          global errorInfo
          set tcl_backtrace $errorInfo
          set errorInfo [string range $ret [expr $idx + 2] \
                                           [string length $ret]]
          append errorInfo "\n" $tcl_backtrace
          bgerror [string range $ret 0 [expr $idx - 1]]
       } else {
          bgerror $ret
       }
       return ""
       #return -code $st $ret
    } else {
        return $ret
    }
  EOL

  #def TkVariable.callback(args)
  def TkVariable.callback(name1, name2, op)
    #name1,name2,op = tk_split_list(args)
    #name1,name2,op = tk_split_simplelist(args)
    if TkVar_CB_TBL[name1]
      #_get_eval_string(TkVar_CB_TBL[name1].trace_callback(name2,op))
      begin
        _get_eval_string(TkVar_CB_TBL[name1].trace_callback(name2, op))
      rescue SystemExit
        exit(0)
      rescue Interrupt
        exit!(1)
      rescue Exception => e
        begin
          msg = _toUTF8(e.class.inspect) + ': ' + 
                _toUTF8(e.message) + "\n" + 
                "\n---< backtrace of Ruby side >-----\n" + 
                _toUTF8(e.backtrace.join("\n")) + 
                "\n---< backtrace of Tk side >-------"
          msg.instance_variable_set(:@encoding, 'utf-8')
        rescue Exception
          msg = e.class.inspect + ': ' + e.message + "\n" + 
                "\n---< backtrace of Ruby side >-----\n" + 
                e.backtrace.join("\n") + 
                "\n---< backtrace of Tk side >-------"
        end
        fail(e, msg)
      end
=begin
      begin
        raise 'check backtrace'
      rescue
        # ignore backtrace before 'callback'
        pos = -($!.backtrace.size)
      end
      begin
        _get_eval_string(TkVar_CB_TBL[name1].trace_callback(name2,op))
      rescue
        trace = $!.backtrace
        raise $!, "\n#{trace[0]}: #{$!.message} (#{$!.class})\n" + 
                  "\tfrom #{trace[1..pos].join("\n\tfrom ")}"
      end
=end
    else
      ''
    end
  end

  def self.new_hash(val = {})
    if val.kind_of?(Hash)
      self.new(val)
    else
      fail ArgumentError, 'Hash is expected'
    end
  end

  #
  # default_value is available only when the variable is an assoc array. 
  #
  def default_value(val=nil, &b)
    if b
      @def_default = :proc
      @default_val = proc(&b)
    else
      @def_default = :val
      @default_val = val
    end
    self
  end
  def default_value=(val)
    @def_default = :val
    @default_val = val
    self
  end
  def default_proc(cmd = Proc.new)
    @def_default = :proc
    @default_val = cmd
    self
  end

  def undef_default
    @default_val = nil
    @def_default = false
    self
  end

  def initialize(val="")
    # @id = Tk_VARIABLE_ID.join('')
    @id = Tk_VARIABLE_ID.join(TkCore::INTERP._ip_id_)
    Tk_VARIABLE_ID[1].succ!
    TkVar_ID_TBL[@id] = self

    @def_default = false
    @default_val = nil

    @trace_var  = nil
    @trace_elem = nil
    @trace_opts = nil

    begin
      INTERP._unset_global_var(@id)
    rescue
    end

    # teach Tk-ip that @id is global var
    INTERP._invoke_without_enc('global', @id)
    #INTERP._invoke('global', @id)

    # create and init
    if val.kind_of?(Hash)
      # assoc-array variable
      self[''] = 0
      self.clear
    end
    self.value = val

=begin
    if val == []
      # INTERP._eval(format('global %s; set %s(0) 0; unset %s(0)', 
      #                     @id, @id, @id))
    elsif val.kind_of?(Array)
      a = []
      # val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e))}
      # s = '"' + a.join(" ").gsub(/[\[\]$"]/, '\\\\\&') + '"'
      val.each_with_index{|e,i| a.push(i); a.push(e)}
      #s = '"' + array2tk_list(a).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + array2tk_list(a).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    elsif  val.kind_of?(Hash)
      #s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
      #             .gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                   .gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; array set %s %s', @id, @id, s))
    else
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(format('global %s; set %s %s', @id, @id, s))
    end
=end
=begin
    if  val.kind_of?(Hash)
      #s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
      #             .gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                   .gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; array set %s %s', @id, @id, s))
    else
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
    end
=end
  end

  def wait(on_thread = false, check_root = false)
    if $SAFE >= 4
      fail SecurityError, "can't wait variable at $SAFE >= 4"
    end
    on_thread &= (Thread.list.size != 1)
    if on_thread
      if check_root
        INTERP._thread_tkwait('variable', @id)
      else
        INTERP._thread_vwait(@id)
      end
    else 
      if check_root
        INTERP._invoke_without_enc('tkwait', 'variable', @id)
      else
        INTERP._invoke_without_enc('vwait', @id)
      end
    end
  end
  def eventloop_wait(check_root = false)
    wait(false, check_root)
  end
  def thread_wait(check_root = false)
    wait(true, check_root)
  end
  def tkwait(on_thread = true)
    wait(on_thread, true)
  end
  def eventloop_tkwait
    wait(false, true)
  end
  def thread_tkwait
    wait(true, true)
  end

  def id
    @id
  end

  def ref(*idxs)
    # "#{@id}(#{idxs.collect{|idx| _get_eval_string(idx)}.join(',')})"
    TkVarAccess.new("#{@id}(#{idxs.collect{|idx| _get_eval_string(idx)}.join(',')})")
  end

  def is_hash?
    #ITNERP._eval("global #{@id}; array exist #{@id}") == '1'
    INTERP._invoke_without_enc('global', @id)
    INTERP._invoke_without_enc('array', 'exist', @id) == '1'
  end

  def is_scalar?
    ! is_hash?
  end

  def keys
    if (is_scalar?)
      fail RuntimeError, 'cannot get keys from a scalar variable'
    end
    #tk_split_simplelist(INTERP._eval("global #{@id}; array get #{@id}"))
    INTERP._invoke_without_enc('global', @id)
    tk_split_simplelist(INTERP._fromUTF8(INTERP._invoke_without_enc('array', 'names', @id)))
  end

  def clear
    if (is_scalar?)
      fail RuntimeError, 'cannot clear a scalar variable'
    end
    keys.each{|k| unset(k)}
    self
  end

  def update(hash)
    if (is_scalar?)
      fail RuntimeError, 'cannot update a scalar variable'
    end
    hash.each{|k,v| self[k] = v}
    self
  end


unless const_defined?(:USE_TCLs_SET_VARIABLE_FUNCTIONS)
  USE_TCLs_SET_VARIABLE_FUNCTIONS = true
end

if USE_TCLs_SET_VARIABLE_FUNCTIONS
  ###########################################################################
  # use Tcl function version of set tkvariable
  ###########################################################################

  def value
    #if INTERP._eval("global #{@id}; array exist #{@id}") == '1'
    INTERP._invoke_without_enc('global', @id)
    if INTERP._invoke('array', 'exist', @id) == '1'
      #Hash[*tk_split_simplelist(INTERP._eval("global #{@id}; array get #{@id}"))]
      Hash[*tk_split_simplelist(INTERP._invoke('array', 'get', @id))]
    else
      _fromUTF8(INTERP._get_global_var(@id))
    end
  end

  def value=(val)
    if val.kind_of?(Hash)
      self.clear
      val.each{|k, v|
        #INTERP._set_global_var2(@id, _toUTF8(_get_eval_string(k)), 
        #                       _toUTF8(_get_eval_string(v)))
        INTERP._set_global_var2(@id, _get_eval_string(k, true), 
                                _get_eval_string(v, true))
      }
      self.value
    elsif val.kind_of?(Array)
      INTERP._set_global_var(@id, '')
      val.each{|v|
        #INTERP._set_variable(@id, _toUTF8(_get_eval_string(v)), 
        INTERP._set_variable(@id, _get_eval_string(v, true), 
                             TclTkLib::VarAccessFlag::GLOBAL_ONLY   | 
                             TclTkLib::VarAccessFlag::LEAVE_ERR_MSG |
                             TclTkLib::VarAccessFlag::APPEND_VALUE  | 
                             TclTkLib::VarAccessFlag::LIST_ELEMENT)
      }
      self.value
    else
      #_fromUTF8(INTERP._set_global_var(@id, _toUTF8(_get_eval_string(val))))
      _fromUTF8(INTERP._set_global_var(@id, _get_eval_string(val, true)))
    end
  end

  def [](*idxs)
    index = idxs.collect{|idx| _get_eval_string(idx, true)}.join(',')
    begin
      _fromUTF8(INTERP._get_global_var2(@id, index))
    rescue => e
      case @def_default
      when :proc
        @default_val.call(self, *idxs)
      when :val
        @default_val
      else
        fail e
      end
    end
    #_fromUTF8(INTERP._get_global_var2(@id, index))
    #_fromUTF8(INTERP._get_global_var2(@id, _toUTF8(_get_eval_string(index))))
    #_fromUTF8(INTERP._get_global_var2(@id, _get_eval_string(index, true)))
  end

  def []=(*args)
    val = args.pop
    index = args.collect{|idx| _get_eval_string(idx, true)}.join(',')
    _fromUTF8(INTERP._set_global_var2(@id, index, _get_eval_string(val, true)))
    #_fromUTF8(INTERP._set_global_var2(@id, _toUTF8(_get_eval_string(index)), 
    #                                 _toUTF8(_get_eval_string(val))))
    #_fromUTF8(INTERP._set_global_var2(@id, _get_eval_string(index, true), 
    #                                 _get_eval_string(val, true)))
  end

  def unset(elem=nil)
    if elem
      INTERP._unset_global_var2(@id, _get_eval_string(elem, true))
    else
      INTERP._unset_global_var(@id)
    end
  end
  alias remove unset

else
  ###########################################################################
  # use Ruby script version of set tkvariable (traditional methods)
  ###########################################################################

  def value
    begin
      INTERP._eval(Kernel.format('global %s; set %s', @id, @id))
      #INTERP._eval(Kernel.format('set %s', @id))
      #INTERP._invoke_without_enc('set', @id)
    rescue
      if INTERP._eval(Kernel.format('global %s; array exists %s', 
                            @id, @id)) != "1"
      #if INTERP._eval(Kernel.format('array exists %s', @id)) != "1"
      #if INTERP._invoke_without_enc('array', 'exists', @id) != "1"
        fail
      else
        Hash[*tk_split_simplelist(INTERP._eval(Kernel.format('global %s; array get %s', @id, @id)))]
        #Hash[*tk_split_simplelist(_fromUTF8(INTERP._invoke_without_enc('array', 'get', @id)))]
      end
    end
  end

  def value=(val)
    begin
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"'
      s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
      INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
      #INTERP._eval(Kernel.format('set %s %s', @id, s))
      #_fromUTF8(INTERP._invoke_without_enc('set', @id, _toUTF8(s)))
    rescue
      if INTERP._eval(Kernel.format('global %s; array exists %s', 
                            @id, @id)) != "1"
      #if INTERP._eval(Kernel.format('array exists %s', @id)) != "1"
      #if INTERP._invoke_without_enc('array', 'exists', @id) != "1"
        fail
      else
        if val == []
          INTERP._eval(Kernel.format('global %s; unset %s; set %s(0) 0; unset %s(0)', @id, @id, @id, @id))
          #INTERP._eval(Kernel.format('unset %s; set %s(0) 0; unset %s(0)', 
          #                          @id, @id, @id))
          #INTERP._invoke_without_enc('unset', @id)
          #INTERP._invoke_without_enc('set', @id+'(0)', 0)
          #INTERP._invoke_without_enc('unset', @id+'(0)')
        elsif val.kind_of?(Array)
          a = []
          val.each_with_index{|e,i| a.push(i); a.push(array2tk_list(e))}
          #s = '"' + a.join(" ").gsub(/[\[\]$"]/, '\\\\\&') + '"'
          s = '"' + a.join(" ").gsub(/[\[\]$"\\]/, '\\\\\&') + '"'
          INTERP._eval(Kernel.format('global %s; unset %s; array set %s %s', 
                                     @id, @id, @id, s))
          #INTERP._eval(Kernel.format('unset %s; array set %s %s', 
          #                          @id, @id, s))
          #INTERP._invoke_without_enc('unset', @id)
          #_fromUTF8(INTERP._invoke_without_enc('array','set', @id, _toUTF8(s)))
        elsif  val.kind_of?(Hash)
          #s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
          #                      .gsub(/[\[\]$"]/, '\\\\\&') + '"'
          s = '"' + val.to_a.collect{|e| array2tk_list(e)}.join(" ")\
                                .gsub(/[\[\]$\\"]/, '\\\\\&') + '"'
          INTERP._eval(Kernel.format('global %s; unset %s; array set %s %s', 
                                     @id, @id, @id, s))
          #INTERP._eval(Kernel.format('unset %s; array set %s %s', 
          #                          @id, @id, s))
          #INTERP._invoke_without_enc('unset', @id)
          #_fromUTF8(INTERP._invoke_without_enc('array','set', @id, _toUTF8(s)))
        else
          fail
        end
      end
    end
  end

  def [](*idxs)
    index = idxs.collect{|idx| _get_eval_string(idx)}.join(',')
    begin
      INTERP._eval(Kernel.format('global %s; set %s(%s)', @id, @id, index))
    rescue => e
      case @def_default
      when :proc
        @default_val.call(self, *idxs)
      when :val
        @default_val
      else
        fail e
      end
    end
    #INTERP._eval(Kernel.format('global %s; set %s(%s)', @id, @id, index))
    #INTERP._eval(Kernel.format('global %s; set %s(%s)', 
    #                           @id, @id, _get_eval_string(index)))
    #INTERP._eval(Kernel.format('set %s(%s)', @id, _get_eval_string(index)))
    #INTERP._eval('set ' + @id + '(' + _get_eval_string(index) + ')')
  end

  def []=(*args)
    val = args.pop
    index = args.collect{|idx| _get_eval_string(idx)}.join(',')
    INTERP._eval(Kernel.format('global %s; set %s(%s) %s', @id, @id, 
                              index, _get_eval_string(val)))
    #INTERP._eval(Kernel.format('global %s; set %s(%s) %s', @id, @id, 
    #                          _get_eval_string(index), _get_eval_string(val)))
    #INTERP._eval(Kernel.format('set %s(%s) %s', @id, 
    #                          _get_eval_string(index), _get_eval_string(val)))
    #INTERP._eval('set ' + @id + '(' + _get_eval_string(index) + ') ' + 
    #            _get_eval_string(val))
  end

  def unset(elem=nil)
    if elem
      INTERP._eval(Kernel.format('global %s; unset %s(%s)', 
                                 @id, @id, _get_eval_string(elem)))
      #INTERP._eval(Kernel.format('unset %s(%s)', @id, tk_tcl2ruby(elem)))
      #INTERP._eval('unset ' + @id + '(' + _get_eval_string(elem) + ')')
    else
      INTERP._eval(Kernel.format('global %s; unset %s', @id, @id))
      #INTERP._eval(Kernel.format('unset %s', @id))
      #INTERP._eval('unset ' + @id)
    end
  end
  alias remove unset

end

  def numeric
    number(value)
  end
  def numeric=(val)
    case val
    when Numeric
      self.value=(val)
    when TkVariable
      self.value=(val.numeric)
    else
      raise ArgumentError, "Numeric is expected"
    end
    val
  end

  def bool
    # see Tcl_GetBoolean man-page
    case value.downcase
    when '0', 'false', 'no', 'off'
      false
    else
      true
    end
  end

  def bool=(val)
    if ! val
      self.value = '0'
    else
      case val.to_s.downcase
      when 'false', '0', 'no', 'off'
        self.value = '0'
      else
        self.value = '1'
      end
    end
  end

  def to_i
    number(value).to_i
  end

  def to_f
    number(value).to_f
  end

  def to_s
    #string(value).to_s
    value
  end

  def to_sym
    value.intern
  end

  def list
    #tk_split_list(value)
    tk_split_simplelist(value)
  end
  alias to_a list

  def list=(val)
    case val
    when Array
      self.value=(val)
    when TkVariable
      self.value=(val.list)
    else
      raise ArgumentError, "Array is expected"
    end
    val
  end

  def inspect
    #Kernel.format "#<TkVariable: %s>", @id
    '#<TkVariable: ' + @id + '>'
  end

  def coerce(other)
    case other
    when TkVariable
      [other.value, self.value]
    when String
      [other, self.to_s]
    when Symbol
      [other, self.to_sym]
    when Integer
      [other, self.to_i]
    when Float
      [other, self.to_f]
    when Array
      [other, self.to_a]
    else
      [other, self.value]
    end
  end

  def &(other)
    if other.kind_of?(Array)
      self.to_a & other.to_a
    else
      self.to_i & other.to_i
    end
  end
  def |(other)
    if other.kind_of?(Array)
      self.to_a | other.to_a
    else
      self.to_i | other.to_i
    end
  end
  def +(other)
    case other
    when Array
      self.to_a + other
    when String
      self.value + other
    else
      begin
        number(self.value) + other
      rescue
        self.value + other.to_s
      end
    end
  end
  def -(other)
    if other.kind_of?(Array)
      self.to_a - other
    else
      number(self.value) - other
    end
  end
  def *(other)
    begin
      number(self.value) * other
    rescue
      self.value * other
    end
  end
  def /(other)
    number(self.value) / other
  end
  def %(other)
    begin
      number(self.value) % other
    rescue
      self.value % other
    end
  end
  def **(other)
    number(self.value) ** other
  end
  def =~(other)
    self.value =~ other
  end

  def ==(other)
    case other
    when TkVariable
      self.equal?(other)
    when String
      self.to_s == other
    when Symbol
      self.to_sym == other
    when Integer
      self.to_i == other
    when Float
      self.to_f == other
    when Array
      self.to_a == other
    when Hash
      self.value == other
    else
      false
    end
  end

  def zero?
    numeric.zero?
  end
  def nonzero?
    !(numeric.zero?)
  end

  def <=>(other)
    if other.kind_of?(TkVariable)
      begin
        val = other.numeric
        other = val
      rescue
        other = other.value
      end
    end
    if other.kind_of?(Numeric)
      begin
        return self.numeric <=> other
      rescue
        return self.value <=> other.to_s
      end
    else
      return self.value <=> other
    end
  end

  def to_eval
    @id
  end

  def trace_callback(elem, op)
    if @trace_var.kind_of? Array
      @trace_var.each{|m,e| e.call(self,elem,op) if m.index(op)}
    end
    if elem.kind_of?(String) && elem != ''
      if @trace_elem.kind_of?(Hash) && @trace_elem[elem].kind_of?(Array)
        @trace_elem[elem].each{|m,e| e.call(self,elem,op) if m.index(op)}
      end
    end
  end

  def trace(opts, cmd = Proc.new)
    @trace_var = [] if @trace_var == nil
    #opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    opts = ['r','w','u'].find_all{|c| opts.to_s.index(c)}.join('')
    @trace_var.unshift([opts,cmd])
    if @trace_opts == nil
      TkVar_CB_TBL[@id] = self
      @trace_opts = opts.dup
      Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'add', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
      end
=end
    else
      newopts = @trace_opts.dup
      #opts.each_byte{|c| newopts += c.chr unless newopts.index(c)}
      opts.each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      if newopts != @trace_opts
        Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 'rb_var')
        @trace_opts.replace(newopts)
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'vdelete', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        end
=end
      end
    end
    self
  end

  def trace_element(elem, opts, cmd = Proc.new)
    @trace_elem = {} if @trace_elem == nil
    @trace_elem[elem] = [] if @trace_elem[elem] == nil
    #opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    opts = ['r','w','u'].find_all{|c| opts.to_s.index(c)}.join('')
    @trace_elem[elem].unshift([opts,cmd])
    if @trace_opts == nil
      TkVar_CB_TBL[@id] = self
      @trace_opts = opts.dup
      Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'add', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'variable', 
                               @id, @trace_opts, 'rb_var')
      end
=end
    else
      newopts = @trace_opts.dup
      # opts.each_byte{|c| newopts += c.chr unless newopts.index(c)}
      opts.each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      if newopts != @trace_opts
        Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 'rb_var')
        @trace_opts.replace(newopts)
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'vdelete', 
                                 @id, @trace_opts, 'rb_var')
          @trace_opts.replace(newopts)
          Tk.tk_call_without_enc('trace', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        end
=end
      end
    end
    self
  end

  def trace_vinfo
    return [] unless @trace_var
    @trace_var.dup
  end
  def trace_vinfo_for_element(elem)
    return [] unless @trace_elem
    return [] unless @trace_elem[elem]
    @trace_elem[elem].dup
  end

  def trace_vdelete(opts,cmd)
    return self unless @trace_var.kind_of? Array
    #opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    opts = ['r','w','u'].find_all{|c| opts.to_s.index(c)}.join('')
    idx = -1
    newopts = ''
    @trace_var.each_with_index{|e,i| 
      if idx < 0 && e[0] == opts && e[1] == cmd
        idx = i
        next
      end
      # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
      e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
    }
    if idx >= 0
      @trace_var.delete_at(idx) 
    else
      return self
    end

    @trace_elem.each{|elem|
      @trace_elem[elem].each{|e|
        # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
        e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      }
    }

    #newopts = ['r','w','u'].find_all{|c| newopts.index(c)}.join('')
    newopts = ['r','w','u'].find_all{|c| newopts.to_s.index(c)}.join('')
    if newopts != @trace_opts
      Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 'rb_var')
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'vdelete', 
                               @id, @trace_opts, 'rb_var')
      end
=end
      @trace_opts.replace(newopts)
      if @trace_opts != ''
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        end
=end
      end
    end

    self
  end

  def trace_vdelete_for_element(elem,opts,cmd)
    return self unless @trace_elem.kind_of? Hash
    return self unless @trace_elem[elem].kind_of? Array
    # opts = ['r','w','u'].find_all{|c| opts.index(c)}.join('')
    opts = ['r','w','u'].find_all{|c| opts.to_s.index(c)}.join('')
    idx = -1
    @trace_elem[elem].each_with_index{|e,i| 
      if idx < 0 && e[0] == opts && e[1] == cmd
        idx = i
        next
      end
    }
    if idx >= 0
      @trace_elem[elem].delete_at(idx)
    else
      return self
    end

    newopts = ''
    @trace_var.each{|e| 
      # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
      e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
    }
    @trace_elem.each{|elem|
      @trace_elem[elem].each{|e|
        # e[0].each_byte{|c| newopts += c.chr unless newopts.index(c)}
        e[0].each_byte{|c| newopts.concat(c.chr) unless newopts.index(c)}
      }
    }

    #newopts = ['r','w','u'].find_all{|c| newopts.index(c)}.join('')
    newopts = ['r','w','u'].find_all{|c| newopts.to_s.index(c)}.join('')
    if newopts != @trace_opts
      Tk.tk_call_without_enc('trace', 'vdelete', @id, @trace_opts, 'rb_var')
=begin
      if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
        # TCL_VERSION >= 8.4
        Tk.tk_call_without_enc('trace', 'remove', 'variable', 
                               @id, @trace_opts, 'rb_var')
      else
        # TCL_VERSION <= 8.3
        Tk.tk_call_without_enc('trace', 'vdelete', 
                               @id, @trace_opts, 'rb_var')
      end
=end
      @trace_opts.replace(newopts)
      if @trace_opts != ''
        Tk.tk_call_without_enc('trace', 'variable', @id, @trace_opts, 'rb_var')
=begin
        if /^(8\.([4-9]|[1-9][0-9])|9\.|[1-9][0-9])/ =~ Tk::TCL_VERSION
          # TCL_VERSION >= 8.4
          Tk.tk_call_without_enc('trace', 'add', 'variable', 
                                 @id, @trace_opts, 'rb_var')
        else
          # TCL_VERSION <= 8.3
          Tk.tk_call_without_enc('trace', 'variable', @id, 
                                 @trace_opts, 'rb_var')
        end
=end
      end
    end

    self
  end
end


class TkVarAccess<TkVariable
  def self.new(name, *args)
    return TkVar_ID_TBL[name] if TkVar_ID_TBL[name]
    super(name, *args)
  end

  def self.new_hash(name, *args)
    return TkVar_ID_TBL[name] if TkVar_ID_TBL[name]
    INTERP._invoke_without_enc('global', name)
    if args.empty? && INTERP._invoke_without_enc('array', 'exist', name) == '0'
      self.new(name, {})  # force creating
    else
      self.new(name, *args)
    end
  end

  def initialize(varname, val=nil)
    @id = varname
    TkVar_ID_TBL[@id] = self

    @def_default = false
    @default_val = nil

    @trace_var  = nil
    @trace_elem = nil
    @trace_opts = nil

    # teach Tk-ip that @id is global var
    INTERP._invoke_without_enc('global', @id)

    if val
      if val.kind_of?(Hash)
        # assoc-array variable
        self[''] = 0
        self.clear
      end
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"]/, '\\\\\&') + '"' #"
      #s = '"' + _get_eval_string(val).gsub(/[\[\]$"\\]/, '\\\\\&') + '"' #"
      #INTERP._eval(Kernel.format('global %s; set %s %s', @id, @id, s))
      #INTERP._set_global_var(@id, _toUTF8(_get_eval_string(val)))
      self.value = val
    end
  end
end


module Tk
  begin
    auto_path = INTERP._invoke('set', 'auto_path')
  rescue
    begin
      auto_path = INTERP._invoke('set', 'env(TCLLIBPATH)')
    rescue
      auto_path = Tk::LIBRARY
    end
  end

  AUTO_PATH = TkVarAccess.new('auto_path', auto_path)

=begin
  AUTO_OLDPATH = tk_split_simplelist(INTERP._invoke('set', 'auto_oldpath'))
  AUTO_OLDPATH.each{|s| s.freeze}
  AUTO_OLDPATH.freeze
=end

  TCL_PACKAGE_PATH = TkVarAccess.new('tcl_pkgPath')
  PACKAGE_PATH = TCL_PACKAGE_PATH

  TCL_LIBRARY_PATH = TkVarAccess.new('tcl_libPath')
  LIBRARY_PATH = TCL_LIBRARY_PATH

  TCL_PRECISION = TkVarAccess.new('tcl_precision')
end
