#
#   e2mmap.rb - 
#   	$Release Version: 1.0$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA
#
# --
#
#

module Exception2MessageMapper
  RCS_ID='-$Header$-'
  E2MM = Exception2MessageMapper
  
  def E2MM.extend_to(b)
    c = eval("self", b)
    c.extend(self)
    c.bind(b)
  end
  
  def bind(b)
    eval "
  @binding = binding
  E2MM_ErrorMSG = Hash.new
  
  # fail(err, *rest)
  #	err:	�㳰
  #	rest:	��å��������Ϥ��ѥ�᡼��
  #
  def fail!(*rest)
    super
  end
  
  def fail(err, *rest)
    $! = err.new(sprintf(E2MM_ErrorMSG[err], *rest))
    super()
  end

  public :fail
  # def_exception(c, m)
  #	    c:  exception
  #	    m:  message_form
  #	�㳰c�Υ�å�������m�Ȥ���.
  #
  def def_e2message(c, m)
    E2MM_ErrorMSG[c] = m
  end
  
  # def_exception(c, m)
  #	    c:  exception_name
  #	    m:  message_form
  #	    s:	�㳰�����ѡ����饹(�ǥե����: Exception)
  #	�㳰̾``c''�����㳰�������, ���Υ�å�������m�Ȥ���.
  #
  def def_exception(c, m)

    c = c.id2name if c.kind_of?(Fixnum)
    eval \"class \#{c} < Exception
           end
           E2MM_ErrorMSG[\#{c}] = '\#{m}'
           \", @binding
  end
", b
    
  end
  
  E2MM.extend_to(binding)
  def_exception("ErrNotClassOrModule", "Not Class or Module")
end

