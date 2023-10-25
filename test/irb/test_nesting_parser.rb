# frozen_string_literal: false
require 'irb'

require_relative "helper"

module TestIRB
  class NestingParserTest < TestCase
    def setup
      save_encodings
    end

    def teardown
      restore_encodings
    end

    def parse_by_line(code)
      IRB::NestingParser.parse_by_line(IRB::RubyLex.ripper_lex_without_warning(code))
    end

    def test_open_tokens
      code = <<~'EOS'
        class A
          def f
            if true
              tap do
                {
                  x: "
                    #{p(1, 2, 3
      EOS
      opens = IRB::NestingParser.open_tokens(IRB::RubyLex.ripper_lex_without_warning(code))
      assert_equal(%w[class def if do { " #{ (], opens.map(&:tok))
    end

    def test_parse_by_line
      code = <<~EOS
        (((((1+2
        ).to_s())).tap do (((
      EOS
      _tokens, prev_opens, next_opens, min_depth = parse_by_line(code).last
      assert_equal(%w[( ( ( ( (], prev_opens.map(&:tok))
      assert_equal(%w[( ( do ( ( (], next_opens.map(&:tok))
      assert_equal(2, min_depth)
    end

    def test_ruby_syntax
      code = <<~'EOS'
        class A
          1 if 2
          1 while 2
          1 until 2
          1 unless 2
          1 rescue 2
          begin; rescue; ensure; end
          tap do; rescue; ensure; end
          class B; end
          module C; end
          def f; end
          def `; end
          def f() = 1
          %(); %w[]; %q(); %r{}; %i[]
          "#{1}"; ''; /#{1}/; `#{1}`
          :sym; :"sym"; :+; :`; :if
          [1, 2, 3]
          { x: 1, y: 2 }
          (a, (*b, c), d), e = 1, 2, 3
          ->(a){}; ->(a) do end
          -> a = -> b = :do do end do end
          if 1; elsif 2; else; end
          unless 1; end
          while 1; end
          until 1; end
          for i in j; end
          case 1; when 2; end
          puts(1, 2, 3)
          loop{|i|}
          loop do |i| end
        end
      EOS
      line_results = parse_by_line(code)
      assert_equal(code.lines.size, line_results.size)
      class_open, *inner_line_results, class_close = line_results
      assert_equal(['class'], class_open[2].map(&:tok))
      inner_line_results.each {|result| assert_equal(['class'], result[2].map(&:tok)) }
      assert_equal([], class_close[2].map(&:tok))
    end

    def test_multiline_string
      code = <<~EOS
        "
        aaa
        bbb
        "
        <<A
        aaa
        bbb
        A
      EOS
      line_results = parse_by_line(code)
      assert_equal(code.lines.size, line_results.size)
      string_content_line, string_opens = line_results[1]
      assert_equal("\naaa\nbbb\n", string_content_line.first.first.tok)
      assert_equal("aaa\n", string_content_line.first.last)
      assert_equal(['"'], string_opens.map(&:tok))
      heredoc_content_line, heredoc_opens = line_results[6]
      assert_equal("aaa\nbbb\n", heredoc_content_line.first.first.tok)
      assert_equal("bbb\n", heredoc_content_line.first.last)
      assert_equal(['<<A'], heredoc_opens.map(&:tok))
      _line, _prev_opens, next_opens, _min_depth = line_results.last
      assert_equal([], next_opens)
    end

    def test_backslash_continued_nested_symbol
      code = <<~'EOS'
        x = <<A, :\
          heredoc #{
            here
          }
        A
        =begin
        embdoc
        =end
        # comment

        if # this is symbol :if
        while
      EOS
      line_results = parse_by_line(code)
      assert_equal(%w[: <<A #{], line_results[2][2].map(&:tok))
      assert_equal(%w[while], line_results.last[2].map(&:tok))
    end

    def test_oneliner_def
      code = <<~EOC
        if true
          # normal oneliner def
          def f = 1
          def f() = 1
          def f(*) = 1
          # keyword, backtick, op
          def * = 1
          def ` = 1
          def if = 1
          def *() = 1
          def `() = 1
          def if() = 1
          # oneliner def with receiver
          def a.* = 1
          def $a.* = 1
          def @a.` = 1
          def A.` = 1
          def ((a;b;c)).*() = 1
          def ((a;b;c)).if() = 1
          def ((a;b;c)).end() = 1
          # multiline oneliner def
          def f =
          1
          def f()
          =
          1
          # oneliner def with comment and embdoc
          def # comment
        =begin
        embdoc
        =end
            ((a;b;c))
            . # comment
        =begin
        embdoc
        =end
            f (*) # comment
        =begin
        embdoc
        =end
          =
          1
          # nested oneliner def
          def f(x = def f() = 1) = def f() = 1
      EOC
      _tokens, _prev_opens, next_opens, min_depth = parse_by_line(code).last
      assert_equal(['if'], next_opens.map(&:tok))
      assert_equal(1, min_depth)
    end

    def test_heredoc_embexpr
      code = <<~'EOS'
        <<A+<<B+<<C+(<<D+(<<E)
          #{
            <<~F+"#{<<~G}
            #{
              here
            }
            F
            G
            "
          }
        A
        B
        C
        D
        E
        )
      EOS
      line_results = parse_by_line(code)
      last_opens = line_results.last[-2]
      assert_equal([], last_opens)
      _tokens, _prev_opens, next_opens, _min_depth = line_results[4]
      assert_equal(%w[( <<E <<D <<C <<B <<A #{ " <<~G <<~F #{], next_opens.map(&:tok))
    end

    def test_for_in
      code = <<~EOS
        for i in j
          here
        end
        for i in j do
          here
        end
        for i in
          j do
          here
        end
        for
          # comment
          i in j do
          here
        end
        for (a;b;c).d in (a;b;c) do
          here
        end
        for i in :in + :do do
          here
        end
        for i in -> do end do
          here
        end
      EOS
      line_results = parse_by_line(code).select { |tokens,| tokens.map(&:last).include?('here') }
      assert_equal(7, line_results.size)
      line_results.each do |_tokens, _prev_opens, next_opens, _min_depth|
        assert_equal(['for'], next_opens.map(&:tok))
      end
    end

    def test_while_until
      base_code = <<~'EOS'
        while_or_until true
          here
        end
        while_or_until a < c
          here
        end
        while_or_until true do
          here
        end
        while_or_until
          # comment
          (a + b) <
          # comment
          c do
          here
        end
        while_or_until :\
          do do
          here
        end
        while_or_until def do; end == :do do
          here
        end
        while_or_until -> do end do
          here
        end
      EOS
      %w[while until].each do |keyword|
        code = base_code.gsub('while_or_until', keyword)
        line_results = parse_by_line(code).select { |tokens,| tokens.map(&:last).include?('here') }
        assert_equal(7, line_results.size)
        line_results.each do |_tokens, _prev_opens, next_opens, _min_depth|
          assert_equal([keyword], next_opens.map(&:tok) )
        end
      end
    end

    def test_case_in
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
        pend 'This test requires ruby version that supports case-in syntax'
      end
      code = <<~EOS
        case 1
        in 1
          here
        in
          2
          here
        end
      EOS
      line_results = parse_by_line(code).select { |tokens,| tokens.map(&:last).include?('here') }
      assert_equal(2, line_results.size)
      line_results.each do |_tokens, _prev_opens, next_opens, _min_depth|
        assert_equal(['in'], next_opens.map(&:tok))
      end
    end
  end
end
