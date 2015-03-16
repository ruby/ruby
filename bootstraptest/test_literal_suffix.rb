# numbers with suffix
assert_equal '0/1',             '0r'
assert_equal 'Rational',        '0r.class'
assert_equal '1/1',             '1r'
assert_equal 'Rational',        '1r.class'
assert_equal '-1/1',            '-1r'
assert_equal 'Rational',        '(-1r).class'
assert_equal '1/1',             '0x1r'
assert_equal 'Rational',        '0x1r.class'
assert_equal '1/1',             '0b1r'
assert_equal 'Rational',        '0b1r.class'
assert_equal '1/1',             '0d1r'
assert_equal 'Rational',        '0d1r.class'
assert_equal '1/1',             '0o1r'
assert_equal 'Rational',        '0o1r.class'
assert_equal '1/1',             '01r'
assert_equal 'Rational',        '01r.class'
assert_equal '6/5',             '1.2r'
assert_equal 'Rational',        '1.2r.class'
assert_equal '-6/5',            '-1.2r'
assert_equal 'Rational',        '(-1.2r).class'
assert_equal '0+0i',            '0i'
assert_equal 'Complex',         '0i.class'
assert_equal '0+1i',            '1i'
assert_equal 'Complex',         '1i.class'
assert_equal '0+1i',            '0x1i'
assert_equal 'Complex',         '0x1i.class'
assert_equal '0+1i',            '0b1i'
assert_equal 'Complex',         '0b1i.class'
assert_equal '0+1i',            '0d1i'
assert_equal 'Complex',         '0d1i.class'
assert_equal '0+1i',            '0o1i'
assert_equal 'Complex',         '0o1i.class'
assert_equal '0+1i',            '01i'
assert_equal 'Complex',         '01i.class'
assert_equal '0+1.2i',          '1.2i'
assert_equal 'Complex',         '1.2i.class'
assert_equal '0+1/1i',          '1ri'
assert_equal 'Complex',         '1ri.class'
assert_equal '0+6/5i',          '1.2ri'
assert_equal 'Complex',         '1.2ri.class'
assert_equal '0+10.0i',         '1e1i'
assert_equal 'Complex',         '1e1i.class'
assert_equal '1',               '1if true'
assert_equal '1',               '1rescue nil'
assert_equal '10000000000000000001/10000000000000000000',
             '1.0000000000000000001r'

assert_equal 'syntax error, unexpected tIDENTIFIER, expecting end-of-input',
             %q{begin eval('1ir', nil, '', 0); rescue SyntaxError => e; e.message[/\A:(?:\d+:)? (.*)/, 1] end}
assert_equal 'syntax error, unexpected tIDENTIFIER, expecting end-of-input',
             %q{begin eval('1.2ir', nil, '', 0); rescue SyntaxError => e; e.message[/\A:(?:\d+:)? (.*)/, 1] end}
assert_equal 'syntax error, unexpected tIDENTIFIER, expecting end-of-input',
             %q{begin eval('1e1r', nil, '', 0); rescue SyntaxError => e; e.message[/\A:(?:\d+:)? (.*)/, 1] end}
