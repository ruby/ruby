require 'dl'

module LIBC
  begin
    LIB = DL.dlopen('libc.so.6')
  rescue RuntimeError
    LIB = DL.dlopen('libc.so.5')
  end

  SYM = {
    :atoi    => LIB['atoi', 'IS'],
    :isdigit => LIB['isdigit', 'II'],
  }

  def atoi(str)
    r,rs = SYM[:atoi].call(str)
    return r
  end

  def isdigit(c)
    r,rs = SYM[:isdigit].call(c)
    return (r != 0)
  end
end

module LIBC
  SYM[:strcat] = LIB['strcat', 'SsS']
  def strcat(str1,str2)
    r,rs = SYM[:strcat].call(str1 + "\0#{str2}",str2)
    return rs[0]
  end
end

module LIBC
  SYM[:fopen] = LIB['fopen', 'PSS']
  SYM[:fclose] = LIB['fclose', '0P']
  SYM[:fgetc] = LIB['fgetc', 'IP']

  def fopen(filename, mode)
    r,rs = SYM[:fopen].call(filename, mode)
    return r
  end

  def fclose(ptr)
    SYM[:fclose].call(ptr)
    return nil
  end

  def fgetc(ptr)
    r,rs = SYM[:fgetc].call(ptr)
    return r
  end
end

module LIBC
  SYM[:strlen] = LIB['strlen', 'IP']
  def strlen(str)
    r,rs = SYM[:strlen].call(str)
    return r
  end
end

$cb1 = DL.set_callback('IPP', 0){|ptr1, ptr2|
  str1 = ptr1.ptr.to_s
  str2 = ptr2.ptr.to_s
  str1 <=> str2
}

module LIBC
  SYM[:qsort] = LIB['qsort', '0aIIP']
  def qsort(ary, comp)
    len = ary.length
    r,rs = SYM[:qsort].call(ary, len, DL.sizeof('P'), comp)
    return rs[0].to_a('S', len)
  end
end

include LIBC

p atoi("10")
p isdigit(?1)
p isdigit(?a)
p strcat("a", "b")
p qsort(["a","c","b"],$cb1)
