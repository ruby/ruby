require_relative 'test_optparse'

class WithDigitOptions < TestOptionParser
  def setup
    super
    @flags = {}
    @opt.def_option("-x"){|x| @flag = @flags[:x] = x }
    @opt.def_option("-o VAL"){|x| @flag = @flags[:o] = x}
    @opt.def_option("-p [VAL]"){|x| @flag = @flags[:p] = x}
    @opt.def_option("-2"){|x| @flag = @flags[2] = x}
    @opt.def_option("-4"){|x| @flag = @flags[4] = x}
  end
  
  def test_negative_digits
    assert_equal(%w"", no_error {@opt.parse!(%w"-2 -4")})
    assert_equal(true, @flags[2])
    assert_equal(true, @flags[4])
    @flags.clear
    
    assert_equal(%w"", no_error {@opt.parse!(%w"-42")})
    assert_equal(true, @flags[2])
    assert_equal(true, @flags[4])
    @flags.clear

    assert_raise(OptionParser::InvalidOption) {@opt.parse!(%w"-x -1")}
    assert_raise(OptionParser::InvalidOption) {@opt.parse!(%w"-x -2 -1")}
    assert_raise(OptionParser::InvalidOption) {@opt.parse!(%w"-x -12")}
    @flags.clear
  end
  
  def test_negative_digits_with_noargs
    assert_equal(%w"", no_error {@opt.parse!(%w"-x -2 -4")})
    assert_equal(true, @flags[:x])
    assert_equal(true, @flags[2])
    assert_equal(true, @flags[4])
    @flags.clear

    assert_equal(%w"", no_error {@opt.parse!(%w"-x2")})
    assert_equal(true, @flags[:x])
    assert_equal(true, @flags[2])
    @flags.clear

    assert_equal(%w"", no_error {@opt.parse!(%w"-2x")})
    assert_equal(true, @flags[:x])
    assert_equal(true, @flags[2])
    @flags.clear
  end
  
  def test_negative_digits_with_reqargs
    assert_equal(%w"", no_error {@opt.parse!(%w"-o -4 -2")})
    assert_equal('-4', @flags[:o])
    assert_equal(false, @flags.has_key?(4))
    assert_equal(true, @flags[2])
    @flags.clear

    assert_equal(%w"", no_error {@opt.parse!(%w"-o42")})
    assert_equal('42', @flags[:o])
    assert_equal(false, @flags.has_key?(4))
    assert_equal(false, @flags.has_key?(2))
    @flags.clear
  end

  # negative numerics after optional arguments are treated as argument 
  # even if it can be an option
  def test_negative_digits_with_optargs
    assert_equal(%w"", no_error {@opt.parse!(%w"-p -4 -2")})
    assert_equal('-4', @flags[:p])
    assert_equal(false, @flags.has_key?(4))
    assert_equal(true, @flags[2])
    @flags.clear

    assert_equal(%w"", no_error {@opt.parse!(%w"-p-4 -2")})
    assert_equal('-4', @flags[:p])
    assert_equal(false, @flags.has_key?(4))
    assert_equal(true, @flags[2])
    @flags.clear
  end
end

class WithoutDigitOptions < TestOptionParser
  def setup
    super
    @flags = {}
    @opt.def_option("-x"){|x| @flag = @flags[:x] = x}
    @opt.def_option("-o VAL"){|x| @flag = @flags[:o] = x}
    @opt.def_option("-p [VAL]"){|x| @flag = @flags[:p] = x}
  end
  
  def test_negative_digits
    assert_equal(%w"-1 -2", no_error {@opt.parse!(%w"-1 -2")})
    assert_equal(%w"-12", no_error {@opt.parse!(%w"-12")})
    assert_equal(%w"-3.14", no_error {@opt.parse!(%w"-3.14")})
    @flags.clear
  end
  def test_negative_digits_with_noargs
    assert_equal(%w"-1 -2", no_error {@opt.parse!(%w"-x -1 -2")})
    assert_equal(true, @flags[:x])
    @flags.clear
  end

  def test_negative_digits_with_reqargs
    assert_equal(%w"-2", no_error {@opt.parse!(%w"-o -1 -2")})
    assert_equal('-1', @flags[:o])
    @flags.clear

    assert_equal(%w"", no_error {@opt.parse!(%w"-o -3.14")})
    assert_equal('-3.14', @flags[:o])
    @flags.clear
  end

  def test_negative_digits_with_optargs
    assert_equal(%w"-2", no_error {@opt.parse!(%w"-p -1 -2")})
    assert_equal('-1', @flags[:p])
    @flags.clear

    assert_equal(%w"-2", no_error {@opt.parse!(%w"-p-1 -2")})
    assert_equal('-1', @flags[:p])
    @flags.clear
  end
end
