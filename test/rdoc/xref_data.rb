# frozen_string_literal: true
XREF_DATA = <<-XREF_DATA
class C1

  attr :attr

  # :section: separate

  attr_reader :attr_reader
  attr_writer :attr_writer

  # :section:
  attr_accessor :attr_accessor

  CONST = :const

  def self.m
  end

  def m foo
  end

  def +
  end
end

class C2
  def b
  end

  alias a b

  class C3
    def m
    end

    class H1
      def m?
      end
    end
  end
end

class C3
  class H1
  end

  class H2 < H1
  end
end

class C4
  class C4
  end
end

class C5
  class C1
  end
end

class C6
  private def priv1() end
  def pub1() end
  protected def prot1() end
  def pub2() end
  public def pub3() end
  def pub4() end

  private
  private def priv2() end
  def priv3() end
  protected def prot2() end
  def priv4() end
  public def pub5() end
  def priv5() end

  protected
  private def priv6() end
  def prot3() end
  protected def prot4() end
  def prot5() end
  public def pub6() end
  def prot6() end
end

class C7
  attr_reader :attr_reader
  attr_reader :attr_reader_nodoc # :nodoc:
  attr_writer :attr_writer
  attr_writer :attr_writer_nodoc # :nodoc:
  attr_accessor :attr_accessor
  attr_accessor :attr_accessor_nodoc # :nodoc:

  CONST = :const
  CONST_NODOC = :const_nodoc # :nodoc:
end

class C8
  class << self
    class S1
    end
  end
end

class C9
  class A
    def foo() end
    def self.bar() end
  end

  class B < A
    def self.foo() end
    def bar() end
  end
end

module M1
  def m
  end
end

module M1::M2
end

class Parent
  def m() end
  def self.m() end
end

class Child < Parent
end

XREF_DATA

