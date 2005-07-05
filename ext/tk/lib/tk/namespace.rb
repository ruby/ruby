#
#   tk/namespace.rb : methods to manipulate Tcl/Tk namespace
#                           by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
require 'tk'

class TkNamespace < TkObject
  extend Tk

  TkCommandNames = [
    'namespace'.freeze, 
  ].freeze

  Tk_Namespace_ID_TBL = TkCore::INTERP.create_table
  Tk_Namespace_ID = ["ns".freeze, "00000".taint].freeze

  class Ensemble < TkObject
    def __cget_cmd
      ['namespace', 'ensemble', 'configure', self.path]
    end
    private :__cget_cmd

    def __config_cmd
      ['namespace', 'ensemble', 'configure', self.path]
    end
    private :__config_cmd

    def __configinfo_struct
      {:key=>0, :alias=>nil, :db_name=>nil, :db_class=>nil, 
        :default_value=>nil, :current_value=>2}
    end
    private :__configinfo_struct

    def __boolval_optkeys
      ['prefixes']
    end
    private :__boolval_optkeys

    def __listval_optkeys
      ['map', 'subcommands', 'unknown']
    end
    private :__listval_optkeys

    def self.exist?(ensemble)
      bool(tk_call('namespace', 'ensemble', 'exists', ensemble))
    end

    def initialize(keys = {})
      @ensemble = @path = tk_call('namespace', 'ensemble', 'create', keys)
    end

    def cget(slot)
      if slot == :namespace || slot == 'namespace'
        ns = super(slot)
        if TkNamespace::Tk_Namespace_ID_TBL.key?(ns)
          TkNamespace::Tk_Namespace_ID_TBL[ns]
        else
          ns
        end
      else
        super(slot)
      end
    end

    def configinfo(slot = nil)
      if slot
        if slot == :namespace || slot == 'namespace'
          val = super(slot)
          if TkNamespace::Tk_Namespace_ID_TBL.key?(val)
            val = TkNamespace::Tk_Namespace_ID_TBL[val]
          end
        else
          val = super(slot)
        end

        if TkComm::GET_CONFIGINFO_AS_ARRAY
          [slot.to_s, val]
        else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
          {slot.to_s => val}
        end

      else
        info = super()

        if TkComm::GET_CONFIGINFO_AS_ARRAY
          info.map!{|inf| 
            if inf[0] == 'namespace' && 
                TkNamespace::Tk_Namespace_ID_TBL.key?(inf[-1])
              [inf[0], TkNamespace::Tk_Namespace_ID_TBL[inf[-1]]]
            else
              inf
            end
          }
        else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
          val = info['namespace']
          if TkNamespace::Tk_Namespace_ID_TBL.key?(val)
            info['namespace'] = TkNamespace::Tk_Namespace_ID_TBL[val]
          end
        end

        info
      end
    end

    def exists?
      bool(tk_call('namespace', 'ensemble', 'exists', @path))
    end
  end

  class ScopeArgs < Array
    include Tk

    # alias __tk_call             tk_call
    # alias __tk_call_without_enc tk_call_without_enc
    # alias __tk_call_with_enc    tk_call_with_enc
    def tk_call(*args)
      #super('namespace', 'eval', @namespace, *args)
      args = args.collect{|arg| (s = _get_eval_string(arg, true))? s: ''}
      super('namespace', 'eval', @namespace, 
            TkCore::INTERP._merge_tklist(*args))
    end
    def tk_call_without_enc(*args)
      #super('namespace', 'eval', @namespace, *args)
      args = args.collect{|arg| (s = _get_eval_string(arg, true))? s: ''}
      super('namespace', 'eval', @namespace, 
            TkCore::INTERP._merge_tklist(*args))
    end
    def tk_call_with_enc(*args)
      #super('namespace', 'eval', @namespace, *args)
      args = args.collect{|arg| (s = _get_eval_string(arg, true))? s: ''}
      super('namespace', 'eval', @namespace, 
            TkCore::INTERP._merge_tklist(*args))
    end

    def initialize(namespace, *args)
      @namespace = namespace
      super(args.size)
      self.replace(args)
    end
  end

  class NsCode < TkObject
    def initialize(scope)
      @scope = scope + ' '
    end
    def path
      @scope
    end
    def to_eval
      @scope
    end
    def call(*args)
      TkCore::INTERP._eval_without_enc(@scope + array2tk_list(args))
    end
  end

  alias __tk_call             tk_call
  alias __tk_call_without_enc tk_call_without_enc
  alias __tk_call_with_enc    tk_call_with_enc
  def tk_call(*args)
    #super('namespace', 'eval', @fullname, *args)
    args = args.collect{|arg| (s = _get_eval_string(arg, true))? s: ''}
    super('namespace', 'eval', @fullname, 
          TkCore::INTERP._merge_tklist(*args))
  end
  def tk_call_without_enc(*args)
    #super('namespace', 'eval', @fullname, *args)
    args = args.collect{|arg| (s = _get_eval_string(arg, true))? s: ''}
    super('namespace', 'eval', @fullname,  
          TkCore::INTERP._merge_tklist(*args))
  end
  def tk_call_with_enc(*args)
    #super('namespace', 'eval', @fullname, *args)
    args = args.collect{|arg| (s = _get_eval_string(arg, true))? s: ''}
    super('namespace', 'eval', @fullname, 
          TkCore::INTERP._merge_tklist(*args))
  end
  alias ns_tk_call             tk_call
  alias ns_tk_call_without_enc tk_call_without_enc
  alias ns_tk_call_with_enc    tk_call_with_enc

  def initialize(name = nil, parent = nil)
    unless name
      # name = Tk_Namespace_ID.join('')
      name = Tk_Namespace_ID.join(TkCore::INTERP._ip_id_)
      Tk_Namespace_ID[1].succ!
    end
    name = __tk_call('namespace', 'current') if name == ''
    if parent
      if parent =~ /^::/
        if name =~ /^::/
          @fullname = parent + name
        else
          @fullname = parent +'::'+ name
        end
      else
        ancestor = __tk_call('namespace', 'current')
        ancestor = '' if ancestor == '::'
        if name =~ /^::/
          @fullname = ancestor + '::' + parent + name
        else
          @fullname = ancestor + '::'+ parent +'::'+ name
        end
      end
    else # parent == nil
      ancestor = __tk_call('namespace', 'current')
      ancestor = '' if ancestor == '::'
      if name =~ /^::/
        @fullname = name
      else
        @fullname = ancestor + '::' + name
      end
    end
    @path = @fullname
    @parent = __tk_call('namespace', 'qualifiers', @fullname)
    @name = __tk_call('namespace', 'tail', @fullname)

    # create namespace
    __tk_call('namespace', 'eval', @fullname, '')

    Tk_Namespace_ID_TBL[@fullname] = self
  end

  def self.children(*args)
    # args ::= [<namespace>] [<pattern>]
    # <pattern> must be glob-style pattern
    tk_split_simplelist(tk_call('namespace', 'children', *args)).collect{|ns|
      # ns is fullname
      if Tk_Namespace_ID_TBL.key?(ns)
        Tk_Namespace_ID_TBL[ns]
      else
        ns
      end
    }
  end
  def children(pattern=None)
    TkNamespace.children(@fullname, pattern)
  end

  def self.code(script = Proc.new)
    TkNamespace.new('').code(script)
  end
  def code(script = Proc.new)
    if script.kind_of?(String)
      cmd = proc{|*args| ScopeArgs.new(@fullname,*args).instance_eval(script)}
    elsif script.kind_of?(Proc)
      cmd = proc{|*args| ScopeArgs.new(@fullname,*args).instance_eval(&script)}
    else
      fail ArgumentError, "String or Proc is expected"
    end
    TkNamespace::NsCode.new(tk_call_without_enc('namespace', 'code', 
                                                _get_eval_string(cmd, false)))
  end

  def self.current
    tk_call('namespace', 'current')
  end
  def current_namespace
    # ns_tk_call('namespace', 'current')
    @fullname
  end
  alias current current_namespace

  def self.delete(*ns_list)
    tk_call('namespace', 'delete', *ns_list)
  end
  def delete
    TkNamespece.delete(@fullname)
  end

  def self.ensemble_create(*keys)
    tk_call('namespace', 'ensemble', 'create', *hash_kv(keys))
  end
  def self.ensemble_configure(cmd, slot, value=None)
    if slot.kind_of?(Hash)
      tk_call('namespace', 'ensemble', 'configure', cmd, *hash_kv(slot))
    else
      tk_call('namespace', 'ensemble', 'configure', cmd, '-'+slot.to_s, value)
    end
  end
  def self.ensemble_configinfo(cmd, slot = nil)
    if slot
      tk_call('namespace', 'ensemble', 'configure', cmd, '-' + slot.to_s)
    else
      inf = {}
      Hash(*tk_split_simplelist(tk_call('namespace', 'ensemble', 'configure', cmd))).each{|k, v| inf[k[1..-1]] = v}
      inf
    end
  end
  def self.ensemble_exist?(cmd)
    bool(tk_call('namespace', 'ensemble', 'exists', cmd))
  end

  def self.eval(namespace, cmd = Proc.new, *args)
    #tk_call('namespace', 'eval', namespace, cmd, *args)
    TkNamespace.new(namespece).eval(cmd, *args)
  end
  def eval(cmd = Proc.new, *args)
    #TkNamespace.eval(@fullname, cmd, *args)
    #ns_tk_call(cmd, *args)
    code_obj = code(cmd)
    ret = code_obj.call(*args)
    # uninstall_cmd(TkCore::INTERP._split_tklist(code_obj.path)[-1])
    uninstall_cmd(_fromUTF8(TkCore::INTERP._split_tklist(_toUTF8(code_obj.path))[-1]))
    ret
  end

  def self.exist?(ns)
    bool(tk_call('namespace', 'exists', ns))
  end
  def exist?
    TkNamespece.delete(@fullname)
  end

  def self.export(*patterns)
    tk_call('namespace', 'export', *patterns)
  end
  def self.export_with_clear(*patterns)
    tk_call('namespace', 'export', '-clear', *patterns)
  end
  def export
    TkNamespace.export(@fullname)
  end
  def export_with_clear
    TkNamespace.export_with_clear(@fullname)
  end

  def self.forget(*patterns)
    tk_call('namespace', 'forget', *patterns)
  end
  def forget
    TkNamespace.forget(@fullname)
  end

  def self.import(*patterns)
    tk_call('namespace', 'import', *patterns)
  end
  def self.force_import(*patterns)
    tk_call('namespace', 'import', '-force', *patterns)
  end
  def import
    TkNamespace.import(@fullname)
  end
  def force_import
    TkNamespace.force_import(@fullname)
  end

  def self.inscope(namespace, script, *args)
    tk_call('namespace', 'inscope', namespace, script, *args)
  end
  def inscope(script, *args)
    TkNamespace(@fullname, script, *args)
  end

  def self.origin(cmd)
    tk_call('namespace', 'origin', cmd)
  end

  def self.parent(namespace=None)
    ns = tk_call('namespace', 'parent', namespace)
    if Tk_Namespace_ID_TBL.key?(ns)
      Tk_Namespace_ID_TBL[ns]
    else
      ns
    end
  end
  def parent
    tk_call('namespace', 'parent', @fullname)
  end

  def self.get_path
    tk_call('namespace', 'path')
  end
  def self.set_path(*namespace_list)
    tk_call('namespace', 'path', array2tk_list(namespace_list))
  end
  def set_path
    tk_call('namespace', 'path', @fullname)
  end

  def self.qualifiers(str)
    tk_call('namespace', 'qualifiers', str)
  end

  def self.tail(str)
    tk_call('namespace', 'tail', str)
  end

  def self.which(name)
    tk_call('namespace', 'which', name)
  end
  def self.which_command(name)
    tk_call('namespace', 'which', '-command', name)
  end
  def self.which_variable(name)
    tk_call('namespace', 'which', '-variable', name)
  end
end
