require 'test/unit'

class TestRubyYield < Test::Unit::TestCase

  def test_ary_each
    ary = [1]
    ary.each {|a, b, c, d| assert_equal [1,nil,nil,nil], [a,b,c,d] }
    ary.each {|a, b, c| assert_equal [1,nil,nil], [a,b,c] }
    ary.each {|a, b| assert_equal [1,nil], [a,b] }
    ary.each {|a| assert_equal 1, a }
  end

  def test_hash_each
    h = {:a => 1}
    h.each do |k, v|
      assert_equal :a, k
      assert_equal 1, v
    end
    h.each do |kv|
      assert_equal [:a, 1], kv
    end
  end

  def test_yield_0
    assert_equal 1, iter0 { 1 }
    assert_equal 2, iter0 { 2 }
  end

  def iter0
    yield
  end

  def test_yield_1
    iter1([]) {|a, b| assert_equal [nil,nil], [a, b] }
    iter1([1]) {|a, b| assert_equal [1,nil], [a, b] }
    iter1([1, 2]) {|a, b| assert_equal [1,2], [a,b] }
    iter1([1, 2, 3]) {|a, b| assert_equal [1,2], [a,b] }

    iter1([]) {|a| assert_equal [], a }
    iter1([1]) {|a| assert_equal [1], a }
    iter1([1, 2]) {|a| assert_equal [1,2], a }
    iter1([1, 2, 3]) {|a| assert_equal [1,2,3], a }
  end

  def iter1(args)
    yield args
  end

  def test_yield2
    def iter2_1() yield 1, *[2, 3] end
    iter2_1 {|a, b, c| assert_equal [1,2,3], [a,b,c] }
    def iter2_2() yield 1, *[] end
    iter2_2 {|a, b, c| assert_equal [1,nil,nil], [a,b,c] }
    def iter2_3() yield 1, *[2] end
    iter2_3 {|a, b, c| assert_equal [1,2,nil], [a,b,c] }
  end

  def test_yield_nested
    [[1, [2, 3]]].each {|a, (b, c)|
      assert_equal [1,2,3], [a,b,c]
    }
    [[1, [2, 3]]].map {|a, (b, c)|
      assert_equal [1,2,3], [a,b,c]
    }
  end

end

require 'sentgen'
class TestRubyYieldGen < Test::Unit::TestCase
  Syntax = {
    :exp => [["0"],
             ["nil"],
             ["false"],
             ["[]"],
             ["[",:exps,"]"]],
    :exps => [[:exp],
              [:exp,",",:exps]],
    :opt_block_param => [[],
                         [:block_param_def]],
    :block_param_def => [['|', '|'],
                         ['|', :block_param, '|']],
    :block_param => [[:f_arg, ",", :f_rest_arg, :opt_f_block_arg],
                     [:f_arg, ","],
                     [:f_arg, ',', :f_rest_arg, ",", :f_arg, :opt_f_block_arg],
                     [:f_arg, :opt_f_block_arg],
                     [:f_rest_arg, :opt_f_block_arg],
                     [:f_rest_arg, ',', :f_arg, :opt_f_block_arg],
                     [:f_block_arg]],
    :f_arg => [[:f_arg_item],
               [:f_arg, ',', :f_arg_item]],
    :f_rest_arg => [['*', "var"],
                    ['*']],
    :opt_f_block_arg => [[',', :f_block_arg],
                         []],
    :f_block_arg => [['&', 'var']],
    :f_arg_item => [[:f_norm_arg],
                    ['(', :f_margs, ')']],
    :f_margs => [[:f_marg_head],
                 [:f_marg_head, ',', '*', :f_norm_arg],
                 [:f_marg_head, ',', '*', :f_norm_arg, ',', :f_marg],
                 [:f_marg_head, ',', '*'],
                 [:f_marg_head, ',', '*',              ',', :f_marg],
                 [                   '*', :f_norm_arg],
                 [                   '*', :f_norm_arg, ',', :f_marg],
                 [                   '*'],
                 [                   '*',              ',', :f_marg]],
    :f_marg_head => [[:f_marg],
                     [:f_marg_head, ',', :f_marg]],
    :f_marg => [[:f_norm_arg],
                ['(', :f_margs, ')']],
    :f_norm_arg => [['var']],

    :command_args => [[:open_args]],
    :open_args => [[' ',:call_args],
                   ['(', ')'],
                   ['(', :call_args2, ')']],
    :call_args =>  [[:command],
                    [           :args,               :opt_block_arg],
                    [                       :assocs, :opt_block_arg],
                    [           :args, ',', :assocs, :opt_block_arg],
                    [                                    :block_arg]],
    :call_args2 => [[:arg, ',', :args,               :opt_block_arg],
                    [:arg, ',',                          :block_arg],
                    [                       :assocs, :opt_block_arg],
                    [:arg, ',',             :assocs, :opt_block_arg],
                    [:arg, ',', :args, ',', :assocs, :opt_block_arg],
                    [                                    :block_arg]],

    :command_args_noblock => [[:open_args_noblock]],
    :open_args_noblock => [[' ',:call_args_noblock],
                   ['(', ')'],
                   ['(', :call_args2_noblock, ')']],
    :call_args_noblock =>  [[:command],
                    [           :args],
                    [                       :assocs],
                    [           :args, ',', :assocs]],
    :call_args2_noblock => [[:arg, ',', :args],
                            [                       :assocs],
                            [:arg, ',',             :assocs],
                            [:arg, ',', :args, ',', :assocs]],

    :command => [],
    :args => [[:arg],
              ["*",:arg],
              [:args,",",:arg],
              [:args,",","*",:arg]],
    :arg => [[:exp]],
    :assocs => [[:assoc],
                [:assocs, ',', :assoc]],
    :assoc => [[:arg, '=>', :arg],
               ['label', ':', :arg]],
    :opt_block_arg => [[',', :block_arg],
                       []],
    :block_arg => [['&', :arg]],
    #:test => [['def m() yield', :command_args_noblock, ' end; r = m {', :block_param_def, 'vars', '}; undef m; r']]
    :test => [['def m(&b) b.yield', :command_args_noblock, ' end; r = m {', :block_param_def, 'vars', '}; undef m; r']]
  }

  def rename_var(obj)
    vars = []
    r = SentGen.subst(obj, 'var') {
      var = "v#{vars.length}"
      vars << var
      var
    }
    return r, vars
  end

  def check_nofork(t)
    t, vars = rename_var(t)
    t = SentGen.subst(t, 'vars') { " [#{vars.join(",")}]" }
    s = [t].join
    #print "#{s}\t\t"
    #STDOUT.flush
    v = eval(s)
    #puts "#{v.inspect[1...-1]}"
    ##xxx: assertion for v here.
  end

  def test_yield
    syntax = SentGen.expand_syntax(Syntax)
    SentGen.each_tree(syntax, :test, 5) {|t|
      check_nofork(t)
    }
  end
end
