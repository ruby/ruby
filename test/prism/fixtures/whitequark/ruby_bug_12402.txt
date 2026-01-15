foo += raise bar rescue nil

foo += raise(bar) rescue nil

foo = raise bar rescue nil

foo = raise(bar) rescue nil

foo.C += raise bar rescue nil

foo.C += raise(bar) rescue nil

foo.m += raise bar rescue nil

foo.m += raise(bar) rescue nil

foo::C ||= raise bar rescue nil

foo::C ||= raise(bar) rescue nil

foo::m += raise bar rescue nil

foo::m += raise(bar) rescue nil

foo[0] += raise bar rescue nil

foo[0] += raise(bar) rescue nil
