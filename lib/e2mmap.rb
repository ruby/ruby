#
#   e2mmap.rb - for ruby 1.1
#   	$Release Version: 1.2$
#   	$Revision: 1.8 $
#   	$Date: 1998/08/19 15:22:22 $
#   	by Keiju ISHITSUKA
#
# --
#   Usage:
#
#   class Foo
#     extend Exception2MassageMapper
#     def_exception :NewExceptionClass, "message..."[, superclass]
#     def_e2meggage ExistingExceptionClass, "message..."
#     ...
#   end
#
#   Foo.Fail NewExceptionClass, arg...
#   Foo.Fail ExistingExceptionClass, arg...
#
#
if VERSION < "1.1"
  require "e2mmap1_0.rb"
else  
  
  module Exception2MessageMapper
    @RCS_ID='-$Id: e2mmap.rb,v 1.8 1998/08/19 15:22:22 keiju Exp keiju $-'
    
    E2MM = Exception2MessageMapper

    def E2MM.extend_object(cl)
      super
      cl.bind(self)
    end
    
    # backward compatibility
    def E2MM.extend_to(b)
      c = eval("self", b)
      c.extend(self)
    end
    
    #    public :fail
    alias fail! fail

    #def fail(err = nil, *rest)
    #  super
    #end

    def Fail(err = nil, *rest)
      Exception2MessageMapper.Fail Exception2MessageMapper::ErrNotRegisteredException, err.inspect
    end
    
    def bind(cl)
      self.module_eval %q^
	E2MM_ErrorMSG = {} unless self.const_defined?(:E2MM_ErrorMSG)
	# fail(err, *rest)
	#	err:	Exception
	#	rest:	Parameter accompanied with the exception
	#
	def self.Fail(err = nil, *rest)
	  if form = E2MM_ErrorMSG[err]
	    $! = err.new(sprintf(form, *rest))
	    $@ = caller(0) if $@.nil?
	    $@.shift
	    # e2mm_fail()
	    raise()
#	  elsif self == Exception2MessageMapper
#	    fail Exception2MessageMapper::ErrNotRegisteredException, err.to_s
	  else
#	    print "super\n"
	    super
	  end
	end

	# backward compatibility
	def self.fail(err = nil, *rest)
	  if form = E2MM_ErrorMSG[err]
	    $! = err.new(sprintf(form, *rest))
	    $@ = caller(0) if $@.nil?
	    $@.shift
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
	#
	def self.def_e2message(c, m)
	  E2MM_ErrorMSG[c] = m
	end
	
	# def_exception(c, m)
	#	    n:  exception_name
	#	    m:  message_form
	#	    s:	superclass_of_exception (default: Exception)
	#	defines excaption named ``c'', whose message is ``m''.
	#
	#def def_exception(n, m)
	def self.def_exception(n, m, s = nil)
	  n = n.id2name if n.kind_of?(Fixnum)
	  unless s
	    if defined?(StandardError)
	      s = StandardError
	    else
	      s = Exception
	    end
	  end
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
