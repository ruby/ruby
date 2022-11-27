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
      @ruby_file = File.join(@tmpdir, 'ruby_file.rb')
      File.unlink(@ruby_file) if File.exist?(@ruby_file)
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

    def test_debug
      write_ruby <<~'RUBY'
        puts "start IRB"
        binding.irb
        puts "Hello"
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("debug\n")
      write("next\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg) next    # command
        [1, 3] in #{@ruby_file}
             1| puts "start IRB"
             2| binding.irb
        =>   3| puts "Hello"
      EOC
    end

    def test_break
      write_ruby <<~'RUBY'
        puts "start IRB"
        binding.irb
        puts "Hello"
        puts "World"
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("break 3\n")
      write("continue\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg:irb) break 3
        #0  BP - Line  #{@ruby_file}:3 (line)
      EOC
      assert_include_screen(<<~EOC)
        (rdbg) continue    # command
        [1, 4] in #{@ruby_file}
             1| puts "start IRB"
             2| binding.irb
        =>   3| puts "Hello"
             4| puts "World"
        =>#0    <main> at #{@ruby_file}:3

        Stop by #0  BP - Line  #{@ruby_file}:3 (line)
      EOC
    end

    def test_delete
      write_ruby <<~'RUBY'
        puts "start IRB"
        binding.irb
        puts "Hello"
        binding.irb
        puts "World"
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("break 5\n")
      write("continue\n")
      write("delete 0\n")
      close
      assert_include_screen(<<~EOC.strip)
        (rdbg:irb) delete 0
        deleted: #0  BP - Line
      EOC
    end

    def test_next
      write_ruby <<~'RUBY'
        puts "start IRB"
        binding.irb
        puts "Hello"
        puts "World"
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("next\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg:irb) next
        [1, 4] in #{@ruby_file}
             1| puts "start IRB"
             2| binding.irb
        =>   3| puts "Hello"
             4| puts "World"
        =>#0    <main> at #{@ruby_file}:3
      EOC
    end

    def test_step
      write_ruby <<~'RUBY'
        puts "start IRB"
        def foo
          puts "Hello"
        end
        binding.irb
        foo
        puts "World"
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("step\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg:irb) step
        [1, 7] in #{@ruby_file}
             1| puts "start IRB"
             2| def foo
        =>   3|   puts "Hello"
             4| end
             5| binding.irb
      EOC
    end

    def test_continue
      write_ruby <<~'RUBY'
        puts "start IRB"
        binding.irb
        puts "Hello"
        binding.irb
        puts "World"
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("continue\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg:irb) continue
        Hello

        From: #{@ruby_file} @ line 4 :

            1: puts "start IRB"
            2: binding.irb
            3: puts "Hello"
         => 4: binding.irb
            5: puts "World"
      EOC
    end

    def test_finish
      write_ruby <<~'RUBY'
        puts "start IRB"
        def foo
          binding.irb
          puts "Hello"
        end
        foo
        puts "World"
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("finish\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg:irb) finish
        Hello
        [1, 7] in #{@ruby_file}
             1| puts "start IRB"
             2| def foo
             3|   binding.irb
             4|   puts "Hello"
        =>   5| end
             6| foo
      EOC
    end

    def test_backtrace
      write_ruby <<~'RUBY'
        puts "start IRB"
        def foo
          binding.irb
        end
        foo
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("backtrace\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg:irb) backtrace
        =>#0    Object#foo at #{@ruby_file}:3
          #1    <main> at #{@ruby_file}:5
      EOC
    end

    def test_info
      write_ruby <<~'RUBY'
        puts "start IRB"
        a = 1
        binding.irb
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("info\n")
      close
      assert_include_screen(<<~EOC)
        (rdbg:irb) info
        %self = main
        a = 1
      EOC
    end

    def test_catch
      write_ruby <<~'RUBY'
        puts "start IRB"
        binding.irb
        raise NotImplementedError
      RUBY
      start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@ruby_file}}, startup_message: 'start IRB')
      write("catch NotImplementedError\n")
      write("continue\n")
      close
      assert_include_screen(<<~EOC)
        Stop by #0  BP - Catch  "NotImplementedError"
      EOC
    end

    private

    def assert_include_screen(expected)
      assert_include(result.join("\n"), expected)
    end

    def write_irbrc(content)
      File.open(@irbrc_file, 'w') do |f|
        f.write content
      end
    end

    def write_ruby(content)
      File.open(@ruby_file, 'w') do |f|
        f.write content
      end
    end
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
