=begin
 This script shows how to deal with C++ classes using Ruby/DL.
 You must build a dynamic loadable library using "c++sample.C"
 to run this script as follows:
   $ g++ -o libsample.so -shared c++sample.C
=end

require 'dl'
require 'dl/import'
require 'dl/struct'

# Give a name of dynamic loadable library
LIBNAME = ARGV[0] || "libsample.so"

class Person
  module Core
    extend DL::Importable

    dlload LIBNAME

    # mangled symbol names
    extern "void __6PersonPCci(void *, const char *, int)"
    extern "const char *get_name__6Person(void *)"
    extern "int get_age__6Person(void *)"
    extern "void set_age__6Personi(void *, int)"

    Data = struct [
      "char *name",
      "int age",
    ]
  end

  def initialize(name, age)
    @ptr = Core::Data.alloc
    Core::__6PersonPCci(@ptr, name, age)
  end

  def get_name()
    str = Core::get_name__6Person(@ptr)
    if( str )
      str.to_s
    else
      nil
    end
  end

  def get_age()
    Core::get_age__6Person(@ptr)
  end

  def set_age(age)
    Core::set_age__6Personi(@ptr, age)
  end
end

obj = Person.new("ttate", 1)
p obj.get_name()
p obj.get_age()
obj.set_age(10)
p obj.get_age()
