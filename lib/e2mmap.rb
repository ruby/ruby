#
#   e2mmap.rb - for ruby 1.1
#   	$Release Version: 2.0$
#   	$Revision: 1.10 $
#   	$Date: 1999/02/17 12:33:17 $
#   	by Keiju ISHITSUKA
#
# --
#   Usage:
#
# U1)
#   class Foo
#     extend Exception2MassageMapper
#     def_e2message ExistingExceptionClass, "message..."
#     def_exception :NewExceptionClass, "message..."[, superclass]
#     ...
#   end
#
# U2)
#   module Error
#     extend Exception2MassageMapper
#     def_e2meggage ExistingExceptionClass, "message..."
#     def_exception :NewExceptionClass, "message..."[, superclass]
#     ...
#   end
#   class Foo
#     include Exp
#     ...
#   end
#
#   foo = Foo.new
#   foo.Fail ....
#
# U3)
#   module Error
#     extend Exception2MassageMapper
#     def_e2message ExistingExceptionClass, "message..."
#     def_exception :NewExceptionClass, "message..."[, superclass]
#     ...
#   end
#   class Foo
#     extend Exception2MessageMapper
#     include Error
#     ...
#   end
#
#   Foo.Fail NewExceptionClass, arg...
#   Foo.Fail ExistingExceptionClass, arg...
#
#
fail "Use Ruby 1.1" if VERSION < "1.1"

module Exception2MessageMapper
  @RCS_ID='-$Id: e2mmap.rb,v 1.10 1999/02/17 12:33:17 keiju Exp keiju $-'

  E2MM = Exception2MessageMapper

  def E2MM.extend_object(cl)
    super
    cl.bind(self) unless cl == E2MM
  end
  
  # 以前との互換性のために残してある.
  def E2MM.extend_to(b)
    c = eval("self", b)
    c.extend(self)
  end

  def bind(cl)
    self.module_eval %[
      def Raise(err = nil, *rest)
	Exception2MessageMapper.Raise(self.type, err, *rest)
      end
      alias Fail Raise

      def self.append_features(mod)
	super
	mod.extend Exception2MessageMapper
      end
    ]
  end

  # Fail(err, *rest)
  #	err:	例外
  #	rest:	メッセージに渡すパラメータ
  #
  def Raise(err = nil, *rest)
    E2MM.Raise(self, err, *rest)
  end
  alias Fail Raise

  # 過去の互換性のため
  alias fail! fail
  def fail(err = nil, *rest)
    begin 
      E2MM.Fail(self, err, *rest)
    rescue E2MM::ErrNotRegisteredException
      super
    end
  end
  class << self
    public :fail
  end

  
  # def_e2message(c, m)
  #	    c:  exception
  #	    m:  message_form
  #	例外cのメッセージをmとする.
  #
  def def_e2message(c, m)
    E2MM.def_e2message(self, c, m)
  end
  
  # def_exception(c, m)
  #	    n:  exception_name
  #	    m:  message_form
  #	    s:	例外スーパークラス(デフォルト: StandardError)
  #	例外名``c''をもつ例外を定義し, そのメッセージをmとする.
  #
  def def_exception(n, m, s = StandardError)
    E2MM.def_exception(self, n, m, s)
  end

  #
  # Private definitions.
  #
  # {[class, exp] => message, ...}
  @MessageMap = {}

  # E2MM.def_exception(k, e, m)
  #	    k:  例外を定義するクラス
  #	    e:  exception
  #	    m:  message_form
  #	例外cのメッセージをmとする.
  #
  def E2MM.def_e2message(k, c, m)
    E2MM.instance_eval{@MessageMap[[k, c]] = m}
    c
  end
  
  # E2MM.def_exception(k, c, m)
  #	    k:  例外を定義するクラス
  #	    n:  exception_name
  #	    m:  message_form
  #	    s:	例外スーパークラス(デフォルト: StandardError)
  #	例外名``c''をもつ例外を定義し, そのメッセージをmとする.
  #
  def E2MM.def_exception(k, n, m, s = StandardError)
    n = n.id2name if n.kind_of?(Fixnum)
    e = Class.new(s)
    E2MM.instance_eval{@MessageMap[[k, e]] = m}
    k.const_set(n, e)
  end

  # Fail(klass, err, *rest)
  #     klass:  例外の定義されているクラス
  #	err:	例外
  #	rest:	メッセージに渡すパラメータ
  #
  def E2MM.Raise(klass = E2MM, err = nil, *rest)
    if form = e2mm_message(klass, err)
      $! = err.new(sprintf(form, *rest))
      $@ = caller(1) if $@.nil?
      #p $@
      #p __FILE__
      $@.shift if $@[0] =~ /^#{Regexp.quote(__FILE__)}:/
      raise
    else
      E2MM.Fail E2MM, ErrNotRegisteredException, err.inspect
    end
  end
  class <<E2MM
    alias Fail Raise
  end

  def E2MM.e2mm_message(klass, exp)
    for c in klass.ancestors
      if mes = @MessageMap[[c,exp]]
	p mes
	m = klass.instance_eval('"' + mes + '"')
	return m
      end
    end
    nil
  end
  class <<self
    alias message e2mm_message
  end

  E2MM.def_exception(E2MM, 
		     :ErrNotRegisteredException, 
		     "not registerd exception(%s)")
end


