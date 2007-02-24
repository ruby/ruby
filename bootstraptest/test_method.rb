# regular argument
assert_equal '1',       'def m() 1 end; m()'
assert_equal '1',       'def m(a) a end; m(1)'
assert_equal '1',       'def m(a,b) a end; m(1,7)'
assert_equal '1',       'def m(a,b) b end; m(7,1)'
assert_equal '1',       'def m(a,b,c) a end; m(1,7,7)'
assert_equal '1',       'def m(a,b,c) b end; m(7,1,7)'
assert_equal '1',       'def m(a,b,c) c end; m(7,7,1)'

# default argument
assert_equal '1',       'def m(x=1) x end; m()'
assert_equal '1',       'def m(x=7) x end; m(1)'
assert_equal '1',       'def m(a,x=1) x end; m(7)'
assert_equal '1',       'def m(a,x=7) x end; m(7,1)'
assert_equal '1',       'def m(a,b,x=1) x end; m(7,7)'
assert_equal '1',       'def m(a,b,x=7) x end; m(7,7,1)'
assert_equal '1',       'def m(a,x=1,y=1) x end; m(7)'
assert_equal '1',       'def m(a,x=1,y=1) y end; m(7)'
assert_equal '1',       'def m(a,x=7,y=1) x end; m(7,1)'
assert_equal '1',       'def m(a,x=7,y=1) y end; m(7,1)'
assert_equal '1',       'def m(a,x=7,y=7) x end; m(7,1,1)'
assert_equal '1',       'def m(a,x=7,y=7) y end; m(7,1,1)'

# rest argument
assert_equal '[]',      'def m(*a) a end; m().inspect'
assert_equal '[1]',     'def m(*a) a end; m(1).inspect'
assert_equal '[1, 2]',  'def m(*a) a end; m(1,2).inspect'
assert_equal '[]',      'def m(x,*a) a end; m(7).inspect'
assert_equal '[1]',     'def m(x,*a) a end; m(7,1).inspect'
assert_equal '[1, 2]',  'def m(x,*a) a end; m(7,1,2).inspect'
assert_equal '[]',      'def m(x,y,*a) a end; m(7,7).inspect'
assert_equal '[1]',     'def m(x,y,*a) a end; m(7,7,1).inspect'
assert_equal '[1, 2]',  'def m(x,y,*a) a end; m(7,7,1,2).inspect'
assert_equal '[]',      'def m(x,y=7,*a) a end; m(7).inspect'
assert_equal '[]',      'def m(x,y,z=7,*a) a end; m(7,7).inspect'
assert_equal '[]',      'def m(x,y,z=7,*a) a end; m(7,7,7).inspect'
assert_equal '[]',      'def m(x,y,z=7,zz=7,*a) a end; m(7,7,7).inspect'
assert_equal '[]',      'def m(x,y,z=7,zz=7,*a) a end; m(7,7,7,7).inspect'
assert_equal '1',       'def m(x,y,z=7,zz=1,*a) zz end; m(7,7,7).inspect'
assert_equal '1',       'def m(x,y,z=7,zz=1,*a) zz end; m(7,7,7).inspect'
assert_equal '1',       'def m(x,y,z=7,zz=7,*a) zz end; m(7,7,7,1).inspect'

# block argument
assert_equal 'Proc',    'def m(&block) block end; m{}.class'
assert_equal 'nil',     'def m(&block) block end; m().inspect'
assert_equal 'Proc',    'def m(a,&block) block end; m(7){}.class'
assert_equal 'nil',     'def m(a,&block) block end; m(7).inspect'
assert_equal '1',       'def m(a,&block) a end; m(1){}'
assert_equal 'Proc',    'def m(a,b=nil,&block) block end; m(7){}.class'
assert_equal 'nil',     'def m(a,b=nil,&block) block end; m(7).inspect'
assert_equal 'Proc',    'def m(a,b=nil,&block) block end; m(7,7){}.class'
assert_equal '1',       'def m(a,b=nil,&block) b end; m(7,1){}'
assert_equal 'Proc',    'def m(a,b=nil,*c,&block) block end; m(7){}.class'
assert_equal 'nil',     'def m(a,b=nil,*c,&block) block end; m(7).inspect'
assert_equal '1',       'def m(a,b=nil,*c,&block) a end; m(1).inspect'
assert_equal '1',       'def m(a,b=1,*c,&block) b end; m(7).inspect'
assert_equal '1',       'def m(a,b=7,*c,&block) b end; m(7,1).inspect'
assert_equal '[1]',     'def m(a,b=7,*c,&block) c end; m(7,7,1).inspect'

# splat
assert_equal '1',       'def m(a) a end; m(*[1])'
assert_equal '1',       'def m(x,a) a end; m(7,*[1])'
assert_equal '1',       'def m(x,y,a) a end; m(7,7,*[1])'
assert_equal '1',       'def m(a,b) a end; m(*[1,7])'
assert_equal '1',       'def m(a,b) b end; m(*[7,1])'
assert_equal '1',       'def m(x,a,b) b end; m(7,*[7,1])'
assert_equal '1',       'def m(x,y,a,b) b end; m(7,7,*[7,1])'
assert_equal '1',       'def m(a,b,c) a end; m(*[1,7,7])'
assert_equal '1',       'def m(a,b,c) b end; m(*[7,1,7])'
assert_equal '1',       'def m(a,b,c) c end; m(*[7,7,1])'
assert_equal '1',       'def m(x,a,b,c) a end; m(7,*[1,7,7])'
assert_equal '1',       'def m(x,y,a,b,c) a end; m(7,7,*[1,7,7])'

# hash argument
assert_equal '1',       'def m(h) h end; m(7=>1)[7]'
assert_equal '1',       'def m(h) h end; m(7=>1).size'
assert_equal '1',       'def m(h) h end; m(7=>1, 8=>7)[7]'
assert_equal '2',       'def m(h) h end; m(7=>1, 8=>7).size'
assert_equal '1',       'def m(h) h end; m(7=>1, 8=>7, 9=>7)[7]'
assert_equal '3',       'def m(h) h end; m(7=>1, 8=>7, 9=>7).size'
assert_equal '1',       'def m(x,h) h end; m(7, 7=>1)[7]'
assert_equal '1',       'def m(x,h) h end; m(7, 7=>1, 8=>7)[7]'
assert_equal '1',       'def m(x,h) h end; m(7, 7=>1, 8=>7, 9=>7)[7]'
assert_equal '1',       'def m(x,y,h) h end; m(7,7, 7=>1)[7]'
assert_equal '1',       'def m(x,y,h) h end; m(7,7, 7=>1, 8=>7)[7]'
assert_equal '1',       'def m(x,y,h) h end; m(7,7, 7=>1, 8=>7, 9=>7)[7]'

# block argument
assert_equal '1',       %q(def m(&block) mm(&block) end
                           def mm() yield 1 end
                           m {|a| a })
assert_equal '1',       %q(def m(x,&block) mm(x,&block) end
                           def mm(x) yield 1 end
                           m(7) {|a| a })
assert_equal '1',       %q(def m(x,y,&block) mm(x,y,&block) end
                           def mm(x,y) yield 1 end
                           m(7,7) {|a| a })

# recursive call
assert_equal '1',       %q(def m(n) n == 0 ? 1 : m(n-1) end; m(5))

# instance method
assert_equal '1',       %q(class C; def m() 1 end end;  C.new.m)
assert_equal '1',       %q(class C; def m(a) a end end;  C.new.m(1))
assert_equal '1',       %q(class C; def m(a = 1) a end end;  C.new.m)
assert_equal '[1]',     %q(class C; def m(*a) a end end;  C.new.m(1).inspect)
assert_equal '1',       %q( class C
                              def m() mm() end
                              def mm() 1 end
                            end
                            C.new.m )

# singleton method (const)
assert_equal '1',       %q(class C; def C.m() 1 end end;  C.m)
assert_equal '1',       %q(class C; def C.m(a) a end end;  C.m(1))
assert_equal '1',       %q(class C; def C.m(a = 1) a end end;  C.m)
assert_equal '[1]',     %q(class C; def C.m(*a) a end end;  C.m(1).inspect)
assert_equal '1',       %q(class C; end; def C.m() 1 end;  C.m)
assert_equal '1',       %q(class C; end; def C.m(a) a end;  C.m(1))
assert_equal '1',       %q(class C; end; def C.m(a = 1) a end;  C.m)
assert_equal '[1]',     %q(class C; end; def C.m(*a) a end;  C.m(1).inspect)
assert_equal '1',       %q(class C; def m() 7 end end; def C.m() 1 end;  C.m)
assert_equal '1',       %q( class C
                              def C.m() mm() end
                              def C.mm() 1 end
                            end
                            C.m )

# singleton method (lvar)
assert_equal '1',       %q(obj = Object.new; def obj.m() 1 end;  obj.m)
assert_equal '1',       %q(obj = Object.new; def obj.m(a) a end;  obj.m(1))
assert_equal '1',       %q(obj = Object.new; def obj.m(a=1) a end;  obj.m)
assert_equal '[1]',     %q(obj = Object.new; def obj.m(*a) a end;  obj.m(1))
assert_equal '1',       %q(class C; def m() 7 end; end
                           obj = C.new
                           def obj.m() 1 end
                           obj.m)

# inheritance
assert_equal '1',       %q(class A; def m(a) a end end
                           class B < A; end
                           B.new.m(1))
assert_equal '1',       %q(class A; end
                           class B < A; def m(a) a end end
                           B.new.m(1))
assert_equal '1',       %q(class A; def m(a) a end end
                           class B < A; end
                           class C < B; end
                           C.new.m(1))

# include
assert_equal '1',       %q(class A; def m(a) a end end
                           module M; end
                           class B < A; include M; end
                           B.new.m(1))
assert_equal '1',       %q(class A; end
                           module M; def m(a) a end end
                           class B < A; include M; end
                           B.new.m(1))

# alias
assert_equal '1',       %q( def a() 1 end
                            alias m a
                            m() )
assert_equal '1',       %q( class C
                              def a() 1 end
                              alias m a
                            end
                            C.new.m )
assert_equal '1',       %q( class C
                              def a() 1 end
                              alias :m a
                            end
                            C.new.m )
assert_equal '1',       %q( class C
                              def a() 1 end
                              alias m :a
                            end
                            C.new.m )
assert_equal '1',       %q( class C
                              def a() 1 end
                              alias :m :a
                            end
                            C.new.m )
assert_equal '1',       %q( class C
                              def a() 1 end
                              alias m a
                              undef a
                            end
                            C.new.m )

# undef
assert_equal '1',       %q( class C
                              def m() end
                              undef m
                            end
                            begin C.new.m; rescue NoMethodError; 1 end )
assert_equal '1',       %q( class A
                              def m() end
                            end
                            class C < A
                              def m() end
                              undef m
                            end
                            begin C.new.m; rescue NoMethodError; 1 end )
assert_equal '1',       %q( class A; def a() end end   # [yarv-dev:999]
                            class B < A
                              def b() end
                              undef a, b
                            end
                            begin B.new.a; rescue NoMethodError; 1 end )
assert_equal '1',       %q( class A; def a() end end   # [yarv-dev:999]
                            class B < A
                              def b() end
                              undef a, b
                            end
                            begin B.new.b; rescue NoMethodError; 1 end )

# private
assert_equal '1',       %q( class C
                              def m() mm() end
                              def mm() 1 end
                              private :mm
                            end
                            C.new.m )
assert_equal '1',       %q( class C
                              def m() 7 end
                              private :m
                            end
                            begin C.m; rescue NoMethodError; 1 end )
assert_equal '1',       %q( class C
                              def C.m() mm() end
                              def C.mm() 1 end
                              private_class_method :mm
                            end
                            C.m )
assert_equal '1',       %q( class C
                              def C.m() 7 end
                              private_class_method :m
                            end
                            begin C.m; rescue NoMethodError; 1 end )
assert_equal '1',       %q( class C; def m() 1 end end
                            C.new.m   # cache
                            class C
                              alias mm m; private :mm
                            end
                            C.new.m
                            begin C.new.mm; 7; rescue NoMethodError; 1 end )

# nested method
assert_equal '1',       %q( class C
                              def m
                                def mm() 1 end
                              end
                            end
                            C.new.m
                            C.new.mm )
assert_equal '1',       %q( class C
                              def m
                                def mm() 1 end
                              end
                            end
                            instance_eval "C.new.m; C.new.mm" )

# method_missing
assert_equal ':m',      %q( class C
                              def method_missing(mid, *args) mid end
                            end
                            C.new.m.inspect )
assert_equal ':mm',     %q( class C
                              def method_missing(mid, *args) mid end
                            end
                            C.new.mm.inspect )
assert_equal '[1, 2]',  %q( class C
                              def method_missing(mid, *args) args end
                            end
                            C.new.m(1,2).inspect )
assert_equal '1',       %q( class C
                              def method_missing(mid, *args) yield 1 end
                            end
                            C.new.m {|a| a })
assert_equal 'nil',     %q( class C
                              def method_missing(mid, *args, &block) block end
                            end
                            C.new.m.inspect )

# send
assert_equal '1',       %q( class C; def m() 1 end end;
                            C.new.__send__(:m) )
assert_equal '1',       %q( class C; def m() 1 end end;
                            C.new.send(:m) )
assert_equal '1',       %q( class C; def m(a) a end end;
                            C.new.send(:m,1) )
assert_equal '1',       %q( class C; def m(a,b) a end end;
                            C.new.send(:m,1,7) )
assert_equal '1',       %q( class C; def m(x,a=1) a end end;
                            C.new.send(:m,7) )
assert_equal '1',       %q( class C; def m(x,a=7) a end end;
                            C.new.send(:m,7,1) )
assert_equal '[1, 2]',  %q( class C; def m(*a) a end end;
                            C.new.send(:m,1,2).inspect )
assert_equal '1',       %q( class C; def m() 7 end; private :m end
                            begin C.new.send(:m); rescue NoMethodError; 1 end )
assert_equal '1',       %q( class C; def m() 1 end; private :m end
                            C.new.funcall(:m) )
