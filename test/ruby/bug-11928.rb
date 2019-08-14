class Segfault
  at_exit { Segfault.new.segfault }

  define_method 'segfault' do
    n = 11928
    v = nil
    i = 0
    while i < n
      i += 1
      v = (foo rescue $!).local_variables
    end
    assert_equal(%i[i n v], v.sort)
  end
end
