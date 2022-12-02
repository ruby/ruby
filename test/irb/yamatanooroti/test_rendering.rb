require 'irb'

begin
  require 'yamatanooroti'

  class IRB::TestRendering < Yamatanooroti::TestCase
    def setup
      @pwd = Dir.pwd
      suffix = '%010d' % Random.rand(0..65535)
      @tmpdir = File.join(File.expand_path(Dir.tmpdir), "test_irb_#{$$}_#{suffix}")
      begin
        Dir.mkdir(@tmpdir)
      rescue Errno::EEXIST
        FileUtils.rm_rf(@tmpdir)
        Dir.mkdir(@tmpdir)
      end
      @irbrc_backup = ENV['IRBRC']
      @irbrc_file = ENV['IRBRC'] = File.join(@tmpdir, 'temporaty_irbrc')
      File.unlink(@irbrc_file) if File.exist?(@irbrc_file)
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      ENV['IRBRC'] = @irbrc_backup
      ENV.delete('RELINE_TEST_PROMPT') if ENV['RELINE_TEST_PROMPT']
    end

    def test_launch
      write_irbrc <<~'LINES'
        puts 'start IRB'
      LINES
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
      write(<<~EOC)
        'Hello, World!'
      EOC
      close
      assert_screen(<<~EOC)
        start IRB
        irb(main):001:0> 'Hello, World!'
        => "Hello, World!"
        irb(main):002:0>
      EOC
    end

    def test_multiline_paste
      write_irbrc <<~'LINES'
        puts 'start IRB'
      LINES
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
      write(<<~EOC)
        class A
          def inspect; '#<A>'; end
          def a; self; end
          def b; true; end
        end

        a = A.new

        a
         .a
         .b
      EOC
      close
      assert_screen(<<~EOC)
        start IRB
        irb(main):001:1* class A
        irb(main):002:1*   def inspect; '#<A>'; end
        irb(main):003:1*   def a; self; end
        irb(main):004:1*   def b; true; end
        irb(main):005:0> end
        => :b
        irb(main):006:0>
        irb(main):007:0> a = A.new
        => #<A>
        irb(main):008:0>
        irb(main):009:0> a
        irb(main):010:0>  .a
        irb(main):011:0>  .b
        => true
        irb(main):012:0>
      EOC
    end

    def test_evaluate_each_toplevel_statement_by_multiline_paste
      write_irbrc <<~'LINES'
        puts 'start IRB'
      LINES
      start_terminal(40, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
      write(<<~EOC)
        class A
          def inspect; '#<A>'; end
          def b; self; end
          def c; true; end
        end

        a = A.new

        a
          .b
          # aaa
          .c

        (a)
          &.b()


        class A def b; self; end; def c; true; end; end;
        a = A.new
        a
          .b
          # aaa
          .c
        (a)
          &.b()
      EOC
      close
      assert_screen(<<~EOC)
        start IRB
        irb(main):001:1* class A
        irb(main):002:1*   def inspect; '#<A>'; end
        irb(main):003:1*   def b; self; end
        irb(main):004:1*   def c; true; end
        irb(main):005:0> end
        => :c
        irb(main):006:0>
        irb(main):007:0> a = A.new
        => #<A>
        irb(main):008:0>
        irb(main):009:0> a
        irb(main):010:0>   .b
        irb(main):011:0>   # aaa
        irb(main):012:0>   .c
        => true
        irb(main):013:0>
        irb(main):014:0> (a)
        irb(main):015:0>   &.b()
        => #<A>
        irb(main):016:0>
        irb(main):017:0>
        irb(main):018:0> class A def b; self; end; def c; true; end; end;
        => :c
        irb(main):019:0> a = A.new
        => #<A>
        irb(main):020:0> a
        irb(main):021:0>   .b
        irb(main):022:0>   # aaa
        irb(main):023:0>   .c
        => true
        irb(main):024:0> (a)
        irb(main):025:0>   &.b()
        => #<A>
        irb(main):026:0>
      EOC
    end

    def test_symbol_with_backtick
      write_irbrc <<~'LINES'
        puts 'start IRB'
      LINES
      start_terminal(40, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
      write(<<~EOC)
        :`
      EOC
      close
      assert_screen(<<~EOC)
        start IRB
        irb(main):001:0> :`
        => :`
        irb(main):002:0>
      EOC
    end

    def test_autocomplete_with_showdoc_in_gaps_on_narrow_screen_right
      pend "Needs a dummy document to show doc"
      write_irbrc <<~'LINES'
        IRB.conf[:PROMPT][:MY_PROMPT] = {
          :PROMPT_I => "%03n> ",
          :PROMPT_N => "%03n> ",
          :PROMPT_S => "%03n> ",
          :PROMPT_C => "%03n> "
        }
        IRB.conf[:PROMPT_MODE] = :MY_PROMPT
        puts 'start IRB'
      LINES
      start_terminal(4, 19, %W{ruby -I/home/aycabta/ruby/reline/lib -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
      write("Str\C-i")
      close
      assert_screen(<<~EOC)
        001> String
             StringPress A
             StructString
                   of byte
      EOC
    end

    def test_autocomplete_with_showdoc_in_gaps_on_narrow_screen_left
      pend "Needs a dummy document to show doc"
      write_irbrc <<~'LINES'
        IRB.conf[:PROMPT][:MY_PROMPT] = {
          :PROMPT_I => "%03n> ",
          :PROMPT_N => "%03n> ",
          :PROMPT_S => "%03n> ",
          :PROMPT_C => "%03n> "
        }
        IRB.conf[:PROMPT_MODE] = :MY_PROMPT
        puts 'start IRB'
      LINES
      start_terminal(4, 12, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
      write("Str\C-i")
      close
      assert_screen(<<~EOC)
        001> String
        PressString
        StrinStruct
        of by
      EOC
    end

    def test_assignment_expression_truncate
      write_irbrc <<~'LINES'
        puts 'start IRB'
      LINES
      start_terminal(40, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
      # Assignment expression code that turns into non-assignment expression after evaluation
      code = "a /'/i if false; a=1; x=1000.times.to_a#'.size"
      write(code + "\n")
      close
      assert_screen(<<~EOC)
        start IRB
        irb(main):001:0> #{code}
        =>
        [0,
        ...
        irb(main):002:0>
      EOC
    end

    private

    def write_irbrc(content)
      File.open(@irbrc_file, 'w') do |f|
        f.write content
      end
    end
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
