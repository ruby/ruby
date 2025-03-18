require_relative '../spec_helper'

describe "Pattern matching" do
  before :each do
    ScratchPad.record []
  end

  describe "Rightward assignment (`=>`) that can be standalone assoc operator that" do
    it "deconstructs value" do
      suppress_warning do
        [0, 1] => [a, b]
        [a, b].should == [0, 1]
      end
    end

    it "deconstructs value and properly scopes variables" do
      suppress_warning do
        a = nil
        1.times {
          [0, 1] => [a, b]
        }
        [a, defined?(b)].should == [0, nil]
      end
    end

    it "can work with keywords" do
      { a: 0, b: 1 } => { a:, b: }
      [a, b].should == [0, 1]
    end
  end

  describe "One-line pattern matching" do
    it "can be used to check if a pattern matches for Array-like entities" do
      ([0, 1] in [a, b]).should == true
      ([0, 1] in [a, b, c]).should == false
    end

    it "can be used to check if a pattern matches for Hash-like entities" do
      ({ a: 0, b: 1 } in { a:, b: }).should == true
      ({ a: 0, b: 1 } in { a:, b:, c: }).should == false
    end
  end

  describe "find pattern" do
    it "captures preceding elements to the pattern" do
      case [0, 1, 2, 3]
      in [*pre, 2, 3]
        pre
      else
        false
      end.should == [0, 1]
    end

    it "captures following elements to the pattern" do
      case [0, 1, 2, 3]
      in [0, 1, *post]
        post
      else
        false
      end.should == [2, 3]
    end

    it "captures both preceding and following elements to the pattern" do
      case [0, 1, 2, 3, 4]
      in [*pre, 2, *post]
        [pre, post]
      else
        false
      end.should == [[0, 1], [3, 4]]
    end

    it "can capture the entirety of the pattern" do
      case [0, 1, 2, 3, 4]
      in [*everything]
        everything
      else
        false
      end.should == [0, 1, 2, 3, 4]
    end

    it "will match an empty Array-like structure" do
      case []
      in [*everything]
        everything
      else
        false
      end.should == []
    end

    it "can be nested" do
      case [0, [2, 4, 6], [3, 9, 27], [4, 16, 64]]
      in [*pre, [*, 9, a], *post]
        [pre, post, a]
      else
        false
      end.should == [[0, [2, 4, 6]], [[4, 16, 64]], 27]
    end

    it "can be nested with an array pattern" do
      case [0, [2, 4, 6], [3, 9, 27], [4, 16, 64]]
      in [_, _, [*, 9, *], *post]
        post
      else
        false
      end.should == [[4, 16, 64]]
    end

    it "can be nested within a hash pattern" do
      case {a: [3, 9, 27]}
      in {a: [*, 9, *post]}
        post
      else
        false
      end.should == [27]
    end

    it "can nest hash and array patterns" do
      case [0, {a: 42, b: [0, 1]}, {a: 42, b: [1, 2]}]
      in [*, {a:, b: [1, c]}, *]
        [a, c]
      else
        false
      end.should == [42, 2]
    end
  end

  it "extends case expression with case/in construction" do
    case [0, 1]
    in [0]
      :foo
    in [0, 1]
      :bar
    end.should == :bar
  end

  it "allows using then operator" do
    case [0, 1]
    in [0] then :foo
    in [0, 1] then :bar
    end.should == :bar
  end

  describe "warning" do
    before :each do
      @experimental, Warning[:experimental] = Warning[:experimental], true
    end

    after :each do
      Warning[:experimental] = @experimental
    end

    context 'when regular form' do
      before :each do
        @src = 'case [0, 1]; in [a, b]; end'
      end

      it "does not warn about pattern matching is experimental feature" do
        -> { eval @src }.should_not complain
      end
    end

    context 'when one-line form' do
      before :each do
        @src = '[0, 1] => [a, b]'
      end

      ruby_version_is ""..."3.1" do
        it "warns about pattern matching is experimental feature" do
          -> { eval @src }.should complain(/pattern matching is experimental, and the behavior may change in future versions of Ruby!/i)
        end
      end

      ruby_version_is "3.1" do
        it "does not warn about pattern matching is experimental feature" do
          -> { eval @src }.should_not complain
        end
      end
    end
  end

  it "binds variables" do
    case [0, 1]
    in [0, a]
      a
    end.should == 1
  end

  it "cannot mix in and when operators" do
    -> {
      eval <<~RUBY
        case []
        when 1 == 1
        in []
        end
      RUBY
    }.should raise_error(SyntaxError, /syntax error, unexpected `in'|\(eval\):3: syntax error, unexpected keyword_in|unexpected 'in'/)

    -> {
      eval <<~RUBY
        case []
        in []
        when 1 == 1
        end
      RUBY
    }.should raise_error(SyntaxError, /syntax error, unexpected `when'|\(eval\):3: syntax error, unexpected keyword_when|unexpected 'when'/)
  end

  it "checks patterns until the first matching" do
    case [0, 1]
    in [0]
      :foo
    in [0, 1]
      :bar
    in [0, 1]
      :baz
    end.should == :bar
  end

  it "executes else clause if no pattern matches" do
    case [0, 1]
    in [0]
      true
    else
      false
    end.should == false
  end

  it "raises NoMatchingPatternError if no pattern matches and no else clause" do
    -> {
      case [0, 1]
      in [0]
      end
    }.should raise_error(NoMatchingPatternError, /\[0, 1\]/)

    error_pattern = ruby_version_is("3.4") ? /\{a: 0, b: 1\}/ : /\{:a=>0, :b=>1\}/
    -> {
      case {a: 0, b: 1}
      in a: 1, b: 1
      end
    }.should raise_error(NoMatchingPatternError, error_pattern)
  end

  it "raises NoMatchingPatternError if no pattern matches and evaluates the expression only once" do
    evals = 0
    -> {
      case (evals += 1; [0, 1])
      in [0]
      end
    }.should raise_error(NoMatchingPatternError, /\[0, 1\]/)
    evals.should == 1
  end

  it "does not allow calculation or method calls in a pattern" do
    -> {
      eval <<~RUBY
        case 0
        in 1 + 1
          true
        end
      RUBY
    }.should raise_error(SyntaxError, /unexpected|expected a delimiter after the patterns of an `in` clause/)
  end

  it "evaluates the case expression once for multiple patterns, caching the result" do
    case (ScratchPad << :foo; 1)
    in 0
      false
    in 1
      true
    end.should == true

    ScratchPad.recorded.should == [:foo]
  end

  describe "guards" do
    it "supports if guard" do
      case 0
      in 0 if false
        true
      else
        false
      end.should == false

      case 0
      in 0 if true
        true
      else
        false
      end.should == true
    end

    it "supports unless guard" do
      case 0
      in 0 unless true
        true
      else
        false
      end.should == false

      case 0
      in 0 unless false
        true
      else
        false
      end.should == true
    end

    it "makes bound variables visible in guard" do
      case [0, 1]
      in [a, 1] if a >= 0
        true
      end.should == true
    end

    it "does not evaluate guard if pattern does not match" do
      case 0
      in 1 if (ScratchPad << :foo) || true
      else
      end

      ScratchPad.recorded.should == []
    end

    it "takes guards into account when there are several matching patterns" do
      case 0
      in 0 if false
        :foo
      in 0 if true
        :bar
      end.should == :bar
    end

    it "executes else clause if no guarded pattern matches" do
      case 0
      in 0 if false
        true
      else
        false
      end.should == false
    end

    it "raises NoMatchingPatternError if no guarded pattern matches and no else clause" do
      -> {
        case [0, 1]
        in [0, 1] if false
        end
      }.should raise_error(NoMatchingPatternError, /\[0, 1\]/)
    end
  end

  describe "value pattern" do
    it "matches an object such that pattern === object" do
      case 0
      in 0
        true
      end.should == true

      case 0
      in (
        -1..1)
        true
      end.should == true

      case 0
      in Integer
        true
      end.should == true

      case "0"
      in /0/
        true
      end.should == true

      case "0"
      in -> s { s == "0" }
        true
      end.should == true
    end

    it "allows string literal with interpolation" do
      x = "x"

      case "x"
      in "#{x + ""}"
        true
      end.should == true
    end
  end

  describe "variable pattern" do
    it "matches a value and binds variable name to this value" do
      case 0
      in a
        a
      end.should == 0
    end

    it "makes bounded variable visible outside a case statement scope" do
      case 0
      in a
      end

      a.should == 0
    end

    it "create local variables even if a pattern doesn't match" do
      case 0
      in a
      in b
      in c
      end

      [a, b, c].should == [0, nil, nil]
    end

    it "allow using _ name to drop values" do
      case [0, 1]
      in [a, _]
        a
      end.should == 0
    end

    it "supports using _ in a pattern several times" do
      case [0, 1, 2]
      in [0, _, _]
        true
      end.should == true
    end

    it "supports using any name with _ at the beginning in a pattern several times" do
      case [0, 1, 2]
      in [0, _x, _x]
        true
      end.should == true

      case {a: 0, b: 1, c: 2}
      in {a: 0, b: _x, c: _x}
        true
      end.should == true
    end

    it "does not support using variable name (except _) several times" do
      -> {
        eval <<~RUBY
          case [0]
          in [a, a]
          end
        RUBY
      }.should raise_error(SyntaxError, /duplicated variable name/)
    end

    it "supports existing variables in a pattern specified with ^ operator" do
      a = 0

      case 0
      in ^a
        true
      end.should == true
    end

    it "allows applying ^ operator to bound variables" do
      case [1, 1]
      in [n, ^n]
        n
      end.should == 1

      case [1, 2]
      in [n, ^n]
        true
      else
        false
      end.should == false
    end

    it "requires bound variable to be specified in a pattern before ^ operator when it relies on a bound variable" do
      -> {
        eval <<~RUBY
          case [1, 2]
          in [^n, n]
            true
          else
            false
          end
        RUBY
      }.should raise_error(SyntaxError, /n: no such local variable/)
    end
  end

  describe "alternative pattern" do
    it "matches if any of patterns matches" do
      case 0
      in 0 | 1 | 2
        true
      end.should == true
    end

    it "does not support variable binding" do
      -> {
        eval <<~RUBY
          case [0, 1]
          in [0, 0] | [0, a]
          end
        RUBY
      }.should raise_error(SyntaxError, /illegal variable in alternative pattern/)
    end

    it "support underscore prefixed variables in alternation" do
      case [0, 1]
      in [1, _]
        false
      in [0, 0] | [0, _a]
        true
      end.should == true
    end

    it "can be used as a nested pattern" do
      case [[1], ["2"]]
      in [[0] | nil, _]
        false
      in [[1], [1]]
        false
      in [[1], [2 | "2"]]
        true
      end.should == true

      case [1, 2]
      in [0, _] | {a: 0}
        false
      in {a: 1, b: 2} | [1, 2]
        true
      end.should == true
    end
  end

  describe "AS pattern" do
    it "binds a variable to a value if pattern matches" do
      case 0
      in Integer => n
        n
      end.should == 0
    end

    it "can be used as a nested pattern" do
      case [1, [2, 3]]
      in [1, Array => ary]
        ary
      end.should == [2, 3]
    end
  end

  describe "Array pattern" do
    it "supports form Constant(pat, pat, ...)" do
      case [0, 1, 2]
      in Array(0, 1, 2)
        true
      end.should == true
    end

    it "supports form Constant[pat, pat, ...]" do
      case [0, 1, 2]
      in Array[0, 1, 2]
        true
      end.should == true
    end

    it "supports form [pat, pat, ...]" do
      case [0, 1, 2]
      in [0, 1, 2]
        true
      end.should == true
    end

    it "supports form pat, pat, ..." do
      case [0, 1, 2]
      in 0, 1, 2
        true
      end.should == true

      case [0, 1, 2]
      in 0, a, 2
        a
      end.should == 1

      case [0, 1, 2]
      in 0, *rest
        rest
      end.should == [1, 2]
    end

    it "matches an object with #deconstruct method which returns an array and each element in array matches element in pattern" do
      obj = Object.new

      def obj.deconstruct
        [0, 1]
      end

      case obj
      in [Integer, Integer]
        true
      end.should == true
    end

    it "calls #deconstruct once for multiple patterns, caching the result" do
      obj = Object.new

      def obj.deconstruct
        ScratchPad << :deconstruct
        [0, 1]
      end

      case obj
      in [1, 2]
        false
      in [0, 1]
        true
      end.should == true

      ScratchPad.recorded.should == [:deconstruct]
    end

    it "calls #deconstruct even on objects that are already an array" do
      obj = [1, 2]

      def obj.deconstruct
        ScratchPad << :deconstruct
        [3, 4]
      end

      case obj
      in [3, 4]
        true
      else
        false
      end.should == true

      ScratchPad.recorded.should == [:deconstruct]
    end

    it "does not match object if Constant === object returns false" do
      case [0, 1, 2]
      in String[0, 1, 2]
        true
      else
        false
      end.should == false
    end

    it "checks Constant === object before calling #deconstruct" do
      c1 = Class.new
      obj = c1.new
      obj.should_not_receive(:deconstruct)

      case obj
      in String[1]
        true
      else
        false
      end.should == false
    end

    it "does not match object without #deconstruct method" do
      obj = Object.new
      obj.should_receive(:respond_to?).with(:deconstruct)

      case obj
      in Object[]
        true
      else
        false
      end.should == false
    end

    it "raises TypeError if #deconstruct method does not return array" do
      obj = Object.new

      def obj.deconstruct
        ""
      end

      -> {
        case obj
        in Object[]
        else
        end
      }.should raise_error(TypeError, /deconstruct must return Array/)
    end

    it "accepts a subclass of Array from #deconstruct" do
      obj = Object.new

      def obj.deconstruct
        Class.new(Array).new([0, 1])
      end

      case obj
      in [1, 2]
        false
      in [0, 1]
        true
      end.should == true
    end

    it "does not match object if elements of array returned by #deconstruct method does not match elements in pattern" do
      obj = Object.new

      def obj.deconstruct
        [1]
      end

      case obj
      in Object[0]
        true
      else
        false
      end.should == false
    end

    it "binds variables" do
      case [0, 1, 2]
      in [a, b, c]
        [a, b, c]
      end.should == [0, 1, 2]
    end

    it "supports splat operator *rest" do
      case [0, 1, 2]
      in [0, *rest]
        rest
      end.should == [1, 2]
    end

    it "does not match partially by default" do
      case [0, 1, 2, 3]
      in [1, 2]
        true
      else
        false
      end.should == false
    end

    it "does match partially from the array beginning if list + , syntax used" do
      case [0, 1, 2, 3]
      in [0, 1, ]
        true
      end.should == true

      case [0, 1, 2, 3]
      in 0, 1,;
        true
      end.should == true
    end

    it "matches [] with []" do
      case []
      in []
        true
      end.should == true
    end

    it "matches anything with *" do
      case [0, 1]
      in *;
        true
      end.should == true
    end

    it "can be used as a nested pattern" do
      case [[1], ["2"]]
      in [[0] | nil, _]
        false
      in [[1], [1]]
        false
      in [[1], [2 | "2"]]
        true
      end.should == true

      case [1, 2]
      in [0, _] | {a: 0}
        false
      in {a: 1, b: 2} | [1, 2]
        true
      end.should == true
    end
  end

  describe "Hash pattern" do
    it "supports form Constant(id: pat, id: pat, ...)" do
      case {a: 0, b: 1}
      in Hash(a: 0, b: 1)
        true
      end.should == true
    end

    it "supports form Constant[id: pat, id: pat, ...]" do
      case {a: 0, b: 1}
      in Hash[a: 0, b: 1]
        true
      end.should == true
    end

    it "supports form {id: pat, id: pat, ...}" do
      case {a: 0, b: 1}
      in {a: 0, b: 1}
        true
      end.should == true
    end

    it "supports form id: pat, id: pat, ..." do
      case {a: 0, b: 1}
      in a: 0, b: 1
        true
      end.should == true

      case {a: 0, b: 1}
      in a: a, b: b
        [a, b]
      end.should == [0, 1]

      case {a: 0, b: 1, c: 2}
      in a: 0, **rest
        rest
      end.should == {b: 1, c: 2}
    end

    it "supports a: which means a: a" do
      case {a: 0, b: 1}
      in Hash(a:, b:)
        [a, b]
      end.should == [0, 1]

      a = b = nil

      case {a: 0, b: 1}
      in Hash[a:, b:]
        [a, b]
      end.should == [0, 1]

      a = b = nil

      case {a: 0, b: 1}
      in {a:, b:}
        [a, b]
      end.should == [0, 1]

      a = nil

      case {a: 0, b: 1, c: 2}
      in {a:, **rest}
        [a, rest]
      end.should == [0, {b: 1, c: 2}]

      a = b = nil

      case {a: 0, b: 1}
      in a:, b:
        [a, b]
      end.should == [0, 1]
    end

    it "can mix key (a:) and key-value (a: b) declarations" do
      case {a: 0, b: 1}
      in Hash(a:, b: x)
        [a, x]
      end.should == [0, 1]
    end

    it "supports 'string': key literal" do
      case {a: 0}
      in {"a": 0}
        true
      end.should == true
    end

    it "does not support non-symbol keys" do
      -> {
        eval <<~RUBY
          case {a: 1}
          in {"a" => 1}
          end
        RUBY
      }.should raise_error(SyntaxError, /unexpected|expected a label as the key in the hash pattern/)
    end

    it "does not support string interpolation in keys" do
      -> {
        eval <<~'RUBY'
          case {a: 1}
          in {"#{x}": 1}
          end
        RUBY
      }.should raise_error(SyntaxError, /symbol literal with interpolation is not allowed|expected a label as the key in the hash pattern/)
    end

    it "raise SyntaxError when keys duplicate in pattern" do
      -> {
        eval <<~RUBY
          case {a: 1}
          in {a: 1, b: 2, a: 3}
          end
        RUBY
      }.should raise_error(SyntaxError, /duplicated key name/)
    end

    it "matches an object with #deconstruct_keys method which returns a Hash with equal keys and each value in Hash matches value in pattern" do
      obj = Object.new

      def obj.deconstruct_keys(*)
        {a: 1}
      end

      case obj
      in {a: 1}
        true
      end.should == true
    end

    it "calls #deconstruct_keys per pattern" do
      obj = Object.new

      def obj.deconstruct_keys(*)
        ScratchPad << :deconstruct_keys
        {a: 1}
      end

      case obj
      in {b: 1}
        false
      in {a: 1}
        true
      end.should == true

      ScratchPad.recorded.should == [:deconstruct_keys, :deconstruct_keys]
    end

    it "does not match object if Constant === object returns false" do
      case {a: 1}
      in String[a: 1]
        true
      else
        false
      end.should == false
    end

    it "checks Constant === object before calling #deconstruct_keys" do
      c1 = Class.new
      obj = c1.new
      obj.should_not_receive(:deconstruct_keys)

      case obj
      in String(a: 1)
        true
      else
        false
      end.should == false
    end

    it "does not match object without #deconstruct_keys method" do
      obj = Object.new
      obj.should_receive(:respond_to?).with(:deconstruct_keys)

      case obj
      in Object[a: 1]
        true
      else
        false
      end.should == false
    end

    it "does not match object if #deconstruct_keys method does not return Hash" do
      obj = Object.new

      def obj.deconstruct_keys(*)
        ""
      end

      -> {
        case obj
        in Object[a: 1]
        end
      }.should raise_error(TypeError, /deconstruct_keys must return Hash/)
    end

    it "does not match object if #deconstruct_keys method returns Hash with non-symbol keys" do
      obj = Object.new

      def obj.deconstruct_keys(*)
        {"a" => 1}
      end

      case obj
      in Object[a: 1]
        true
      else
        false
      end.should == false
    end

    it "does not match object if elements of Hash returned by #deconstruct_keys method does not match values in pattern" do
      obj = Object.new

      def obj.deconstruct_keys(*)
        {a: 1}
      end

      case obj
      in Object[a: 2]
        true
      else
        false
      end.should == false
    end

    it "passes keys specified in pattern as arguments to #deconstruct_keys method" do
      obj = Object.new

      def obj.deconstruct_keys(*args)
        ScratchPad << args
        {a: 1, b: 2, c: 3}
      end

      case obj
      in Object[a: 1, b: 2, c: 3]
      end

      ScratchPad.recorded.sort.should == [[[:a, :b, :c]]]
    end

    it "passes keys specified in pattern to #deconstruct_keys method if pattern contains double splat operator **" do
      obj = Object.new

      def obj.deconstruct_keys(*args)
        ScratchPad << args
        {a: 1, b: 2, c: 3}
      end

      case obj
      in Object[a: 1, b: 2, **]
      end

      ScratchPad.recorded.sort.should == [[[:a, :b]]]
    end

    it "passes nil to #deconstruct_keys method if pattern contains double splat operator **rest" do
      obj = Object.new

      def obj.deconstruct_keys(*args)
        ScratchPad << args
        {a: 1, b: 2}
      end

      case obj
      in Object[a: 1, **rest]
      end

      ScratchPad.recorded.should == [[nil]]
    end

    it "binds variables" do
      case {a: 0, b: 1, c: 2}
      in {a: x, b: y, c: z}
        [x, y, z]
      end.should == [0, 1, 2]
    end

    it "supports double splat operator **rest" do
      case {a: 0, b: 1, c: 2}
      in {a: 0, **rest}
        rest
      end.should == {b: 1, c: 2}
    end

    it "treats **nil like there should not be any other keys in a matched Hash" do
      case {a: 1, b: 2}
      in {a: 1, b: 2, **nil}
        true
      end.should == true

      case {a: 1, b: 2}
      in {a: 1, **nil}
        true
      else
        false
      end.should == false
    end

    it "can match partially" do
      case {a: 1, b: 2}
      in {a: 1}
        true
      end.should == true
    end

    it "matches {} with {}" do
      case {}
      in {}
        true
      end.should == true
    end

    it "in {} only matches empty hashes" do
      case {a: 1}
      in {}
        true
      else
        false
      end.should == false
    end

    it "in {**nil} only matches empty hashes" do
      case {}
      in {**nil}
        true
      else
        false
      end.should == true

      case {a: 1}
      in {**nil}
        true
      else
        false
      end.should == false
    end

    it "matches anything with **" do
      case {a: 1}
      in **;
        true
      end.should == true
    end

    it "can be used as a nested pattern" do
      case {a: {a: 1, b: 1}, b: {a: 1, b: 2}}
      in {a: {a: 0}}
        false
      in {a: {a: 1}, b: {b: 1}}
        false
      in {a: {a: 1}, b: {b: 2} }
        true
      end.should == true

      case [{a: 1, b: [1]}, {a: 1, c: ["2"]}]
      in [{a:, c:}, ]
        false
      in [{a: 1, b:}, {a: 1, c: [Integer]}]
        false
      in [_, {a: 1, c: [String]}]
        true
      end.should == true
    end
  end

  describe "refinements" do
    it "are used for #deconstruct" do
      refinery = Module.new do
        refine Array do
          def deconstruct
            [0]
          end
        end
      end

      result = nil
      Module.new do
        using refinery

        result =
          case []
          in [0]
            true
          end
      end

      result.should == true
    end

    it "are used for #deconstruct_keys" do
      refinery = Module.new do
        refine Hash do
          def deconstruct_keys(_)
            {a: 0}
          end
        end
      end

      result = nil
      Module.new do
        using refinery

        result =
          case {}
          in a: 0
            true
          end
      end

      result.should == true
    end

    it "are used for #=== in constant pattern" do
      refinery = Module.new do
        refine Array.singleton_class do
          def ===(obj)
            obj.is_a?(Hash)
          end
        end
      end

      result = nil
      Module.new do
        using refinery

        result =
          case {}
          in Array
            true
          end
      end

      result.should == true
    end
  end
end

ruby_version_is "3.1" do
  require_relative 'pattern_matching/3.1'
end
