#
#   e2mmap.rb - for ruby 1.1
#   	$Release Version: 1.1$
#   	$Revision: 1.4 $
#   	$Date: 1997/08/18 07:12:12 $
#   	by Keiju ISHITSUKA
#
# --
#
#
if VERSION < "1.1"
  require "e2mmap1_0.rb"
else  
  
  module Exception2MessageMapper
    RCS_ID='-$Header: /home/keiju/var/src/var.lib/ruby/RCS/e2mmap.rb,v 1.4 1997/08/18 07:12:12 keiju Exp keiju $-'
    
    E2MM = Exception2MessageMapper
    
    def E2MM.extend_object(cl)
      super
      cl.bind(self)
    end
    
    # 以前との互換性のために残してある.
    def E2MM.extend_to(b)
      c = eval("self", b)
      c.extend(self)
    end
    
#    public :fail
    #    alias e2mm_fail fail

    def fail(err = nil, *rest)
      Exception2MessageMapper.fail Exception2MessageMapper::ErrNotRegisteredException, err.to_s
    end
    
    def bind(cl)
      self.module_eval %q^
	E2MM_ErrorMSG = {}
	# fail(err, *rest)
	#	err:	例外
	#	rest:	メッセージに渡すパラメータ
	#
	def self.fail(err = nil, *rest)
	  $@ = caller(0) if $@.nil?
	  $@.shift
	  if form = E2MM_ErrorMSG[err]
	    $! = err.new(sprintf(form, *rest))
	    # e2mm_fail()
	    raise()
#	  elsif self == Exception2MessageMapper
#	    fail Exception2MessageMapper::ErrNotRegisteredException, err.to_s
	  else
#	    print "super\n"
	    super
	  end
	end
	class << self
	  public :fail
	end
	
	# def_exception(c, m)
	#	    c:  exception
	#	    m:  message_form
	#	例外cのメッセージをmとする.
	#
	def self.def_e2message(c, m)
	  E2MM_ErrorMSG[c] = m
	end
	
	# def_exception(c, m)
	#	    n:  exception_name
	#	    m:  message_form
	#	    s:	例外スーパークラス(デフォルト: StandardError)
	#	例外名``c''をもつ例外を定義し, そのメッセージをmとする.
	#
	#def def_exception(n, m)
	def self.def_exception(n, m, s = StandardError)
	  n = n.id2name if n.kind_of?(Fixnum)
	  e = Class.new(s)
	  const_set(n, e)
	  E2MM_ErrorMSG[e] = m
	  #	const_get(:E2MM_ErrorMSG)[e] = m
	end
      ^
      end
      
      extend E2MM
      def_exception(:ErrNotClassOrModule, "Not Class or Module")
      def_exception(:ErrNotRegisteredException, "not registerd exception(%s)")
    end
end

