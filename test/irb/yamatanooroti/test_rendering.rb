require 'irb'

begin
  require 'yamatanooroti'
rescue LoadError, NameError
  # On Ruby repository, this test suite doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
  return
end

class IRB::RenderingTest < Yamatanooroti::TestCase
  def setup
    @original_term = ENV['TERM']
    @home_backup = ENV['HOME']
    @xdg_config_home_backup = ENV['XDG_CONFIG_HOME']
    ENV['TERM'] = "xterm-256color"
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
    ENV['HOME'] = File.join(@tmpdir, 'home')
    ENV['XDG_CONFIG_HOME'] = File.join(@tmpdir, 'xdg_config_home')
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV['IRBRC'] = @irbrc_backup
    ENV['TERM'] = @original_term
    ENV['HOME'] = @home_backup
    ENV['XDG_CONFIG_HOME'] = @xdg_config_home_backup
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
      irb(main):001> 'Hello, World!'
      => "Hello, World!"
      irb(main):002>
    EOC
  end

  def test_configuration_file_is_skipped_with_dash_f
    write_irbrc <<~'LINES'
      puts '.irbrc file should be ignored when -f is used'
    LINES
    start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb -f}, startup_message: '')
    write(<<~EOC)
      'Hello, World!'
    EOC
    close
    assert_screen(<<~EOC)
      irb(main):001> 'Hello, World!'
      => "Hello, World!"
      irb(main):002>
    EOC
  end

  def test_configuration_file_is_skipped_with_dash_f_for_nested_sessions
    write_irbrc <<~'LINES'
      puts '.irbrc file should be ignored when -f is used'
    LINES
    start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb -f}, startup_message: '')
    write(<<~EOC)
      'Hello, World!'
      binding.irb
      exit!
    EOC
    close
    assert_screen(<<~EOC)
      irb(main):001> 'Hello, World!'
      => "Hello, World!"
      irb(main):002> binding.irb
      irb(main):003> exit!
      irb(main):001>
    EOC
  end

  def test_nomultiline
    write_irbrc <<~'LINES'
      puts 'start IRB'
    LINES
    start_terminal(25, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb --nomultiline}, startup_message: 'start IRB')
    write(<<~EOC)
      if true
      if false
      a = "hello
      world"
      puts a
      end
      end
    EOC
    close
    assert_screen(<<~EOC)
      start IRB
      irb(main):001> if true
      irb(main):002*   if false
      irb(main):003*     a = "hello
      irb(main):004" world"
      irb(main):005*     puts a
      irb(main):006*     end
      irb(main):007*   end
      => nil
      irb(main):008>
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
      irb(main):001* class A
      irb(main):002*   def inspect; '#<A>'; end
      irb(main):003*   def a; self; end
      irb(main):004*   def b; true; end
      irb(main):005> end
      => :b
      irb(main):006>
      irb(main):007> a = A.new
      => #<A>
      irb(main):008>
      irb(main):009> a
      irb(main):010>  .a
      irb(main):011> .b
      => true
      irb(main):012>
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
      irb(main):001* class A
      irb(main):002*   def inspect; '#<A>'; end
      irb(main):003*   def b; self; end
      irb(main):004*   def c; true; end
      irb(main):005> end
      => :c
      irb(main):006>
      irb(main):007> a = A.new
      => #<A>
      irb(main):008>
      irb(main):009> a
      irb(main):010>   .b
      irb(main):011>   # aaa
      irb(main):012>   .c
      => true
      irb(main):013>
      irb(main):014> (a)
      irb(main):015>   &.b()
      => #<A>
      irb(main):016>
      irb(main):017>
      irb(main):018> class A def b; self; end; def c; true; end; end;
      irb(main):019> a = A.new
      => #<A>
      irb(main):020> a
      irb(main):021>   .b
      irb(main):022>   # aaa
      irb(main):023>   .c
      => true
      irb(main):024> (a)
      irb(main):025> &.b()
      => #<A>
      irb(main):026>
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
      irb(main):001> :`
      => :`
      irb(main):002>
    EOC
  end

  def test_autocomplete_with_multiple_doc_namespaces
    write_irbrc <<~'LINES'
      puts 'start IRB'
    LINES
    start_terminal(3, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("{}.__id_")
    write("\C-i")
    close
    screen = result.join("\n").sub(/\n*\z/, "\n")
    # This assertion passes whether showdoc dialog completed or not.
    assert_match(/start\ IRB\nirb\(main\):001> {}\.__id__\n                }\.__id__(?:Press )?/, screen)
  end

  def test_autocomplete_with_showdoc_in_gaps_on_narrow_screen_right
    rdoc_dir = File.join(@tmpdir, 'rdoc')
    system("bundle exec rdoc -r -o #{rdoc_dir}")
    write_irbrc <<~LINES
      IRB.conf[:EXTRA_DOC_DIRS] = ['#{rdoc_dir}']
      IRB.conf[:PROMPT][:MY_PROMPT] = {
        :PROMPT_I => "%03n> ",
        :PROMPT_S => "%03n> ",
        :PROMPT_C => "%03n> "
      }
      IRB.conf[:PROMPT_MODE] = :MY_PROMPT
      puts 'start IRB'
    LINES
    start_terminal(4, 19, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("IR")
    write("\C-i")
    close

    # This is because on macOS we display different shortcut for displaying the full doc
    # 'O' is for 'Option' and 'A' is for 'Alt'
    if RUBY_PLATFORM =~ /darwin/
      assert_screen(<<~EOC)
        start IRB
        001> IRB
             IRBPress Opti
                IRB
      EOC
    else
      assert_screen(<<~EOC)
        start IRB
        001> IRB
             IRBPress Alt+
                IRB
      EOC
    end
  end

  def test_autocomplete_with_showdoc_in_gaps_on_narrow_screen_left
    rdoc_dir = File.join(@tmpdir, 'rdoc')
    system("bundle exec rdoc -r -o #{rdoc_dir}")
    write_irbrc <<~LINES
      IRB.conf[:EXTRA_DOC_DIRS] = ['#{rdoc_dir}']
      IRB.conf[:PROMPT][:MY_PROMPT] = {
        :PROMPT_I => "%03n> ",
        :PROMPT_S => "%03n> ",
        :PROMPT_C => "%03n> "
      }
      IRB.conf[:PROMPT_MODE] = :MY_PROMPT
      puts 'start IRB'
    LINES
    start_terminal(4, 12, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("IR")
    write("\C-i")
    close
    assert_screen(<<~EOC)
      start IRB
      001> IRB
      PressIRB
      IRB
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
      irb(main):001> #{code}
      =>
      [0,
      ...
      irb(main):002>
    EOC
  end

  def test_ctrl_c_is_handled
    write_irbrc <<~'LINES'
      puts 'start IRB'
    LINES
    start_terminal(40, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    # Assignment expression code that turns into non-assignment expression after evaluation
    write("\C-c")
    close
    assert_screen(<<~EOC)
      start IRB
      irb(main):001>
      ^C
      irb(main):001>
    EOC
  end

  def test_show_cmds_with_pager_can_quit_with_ctrl_c
    write_irbrc <<~'LINES'
      puts 'start IRB'
    LINES
    start_terminal(40, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("help\n")
    write("G") # move to the end of the screen
    write("\C-c") # quit pager
    write("'foo' + 'bar'\n") # eval something to make sure IRB resumes
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    # IRB::Abort should be rescued
    assert_not_match(/IRB::Abort/, screen)
    # IRB should resume
    assert_match(/foobar/, screen)
  end

  def test_pager_page_content_pages_output_when_it_does_not_fit_in_the_screen_because_of_total_length
    write_irbrc <<~'LINES'
      puts 'start IRB'
      require "irb/pager"
    LINES
    start_terminal(10, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("IRB::Pager.page_content('a' * (80 * 8))\n")
    write("'foo' + 'bar'\n") # eval something to make sure IRB resumes
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    assert_match(/a{80}/, screen)
    # because pager is invoked, foobar will not be evaluated
    assert_not_match(/foobar/, screen)
  end

  def test_pager_page_content_pages_output_when_it_does_not_fit_in_the_screen_because_of_screen_height
    write_irbrc <<~'LINES'
      puts 'start IRB'
      require "irb/pager"
    LINES
    start_terminal(10, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("IRB::Pager.page_content('a\n' * 8)\n")
    write("'foo' + 'bar'\n") # eval something to make sure IRB resumes
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    assert_match(/(a\n){8}/, screen)
    # because pager is invoked, foobar will not be evaluated
    assert_not_match(/foobar/, screen)
  end

  def test_pager_page_content_doesnt_page_output_when_it_fits_in_the_screen
    write_irbrc <<~'LINES'
      puts 'start IRB'
      require "irb/pager"
    LINES
    start_terminal(10, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("IRB::Pager.page_content('a' * (80 * 7))\n")
    write("'foo' + 'bar'\n") # eval something to make sure IRB resumes
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    assert_match(/a{80}/, screen)
    # because pager is not invoked, foobar will be evaluated
    assert_match(/foobar/, screen)
  end

  def test_long_evaluation_output_is_paged
    write_irbrc <<~'LINES'
      puts 'start IRB'
      require "irb/pager"
    LINES
    start_terminal(10, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("'a' * 80 * 11\n")
    write("'foo' + 'bar'\n") # eval something to make sure IRB resumes
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    assert_match(/(a{80}\n){8}/, screen)
    # because pager is invoked, foobar will not be evaluated
    assert_not_match(/foobar/, screen)
  end

  def test_long_evaluation_output_is_preserved_after_paging
    write_irbrc <<~'LINES'
      puts 'start IRB'
      require "irb/pager"
    LINES
    start_terminal(10, 80, %W{ruby -I#{@pwd}/lib #{@pwd}/exe/irb}, startup_message: 'start IRB')
    write("'a' * 80 * 11\n")
    write("q") # quit pager
    write("'foo' + 'bar'\n") # eval something to make sure IRB resumes
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    # confirm pager has exited
    assert_match(/foobar/, screen)
    # confirm output is preserved
    assert_match(/(a{80}\n){6}/, screen)
  end

  def test_debug_integration_hints_debugger_commands
    write_irbrc <<~'LINES'
      IRB.conf[:USE_COLORIZE] = false
    LINES
    script = Tempfile.create(["debug", ".rb"])
    script.write <<~RUBY
      puts 'start IRB'
      binding.irb
    RUBY
    script.close
    start_terminal(40, 80, %W{ruby -I#{@pwd}/lib #{script.to_path}}, startup_message: 'start IRB')
    write("debug\n")
    write("pp 1\n")
    write("pp 1")
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    # submitted input shouldn't contain hint
    assert_include(screen, "irb:rdbg(main):002> pp 1\n")
    # unsubmitted input should contain hint
    assert_include(screen, "irb:rdbg(main):003> pp 1 # debug command\n")
  ensure
    File.unlink(script) if script
  end

  def test_debug_integration_doesnt_hint_non_debugger_commands
    write_irbrc <<~'LINES'
      IRB.conf[:USE_COLORIZE] = false
    LINES
    script = Tempfile.create(["debug", ".rb"])
    script.write <<~RUBY
      puts 'start IRB'
      binding.irb
    RUBY
    script.close
    start_terminal(40, 80, %W{ruby -I#{@pwd}/lib #{script.to_path}}, startup_message: 'start IRB')
    write("debug\n")
    write("foo")
    close

    screen = result.join("\n").sub(/\n*\z/, "\n")
    assert_include(screen, "irb:rdbg(main):002> foo\n")
  ensure
    File.unlink(script) if script
  end

  private

  def write_irbrc(content)
    File.open(@irbrc_file, 'w') do |f|
      f.write content
    end
  end
end
