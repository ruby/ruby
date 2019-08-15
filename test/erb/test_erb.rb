# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'
require 'erb'
require 'stringio'

class TestERB < Test::Unit::TestCase
  class MyError < RuntimeError ; end

  def test_without_filename
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\A\(erb\):1\b/, e.backtrace[0])
  end

  def test_with_filename
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\Atest filename:1\b/, e.backtrace[0])
  end

  # [deprecated] This will be removed later
  def test_without_filename_with_safe_level
    erb = EnvUtil.suppress_warning do
      ERB.new("<% raise ::TestERB::MyError %>", 1)
    end
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\A\(erb\):1\b/, e.backtrace[0])
  end

  # [deprecated] This will be removed later
  def test_with_filename_and_safe_level
    erb = EnvUtil.suppress_warning do
      ERB.new("<% raise ::TestERB::MyError %>", 1)
    end
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\Atest filename:1\b/, e.backtrace[0])
  end

  def test_with_filename_lineno
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    erb.filename = "test filename"
    erb.lineno = 100
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\Atest filename:101\b/, e.backtrace[0])
  end

  def test_with_location
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    erb.location = ["test filename", 200]
    e = assert_raise(MyError) {
      erb.result
    }
    assert_match(/\Atest filename:201\b/, e.backtrace[0])
  end

  def test_html_escape
    assert_equal(" !&quot;\#$%&amp;&#39;()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",
                 ERB::Util.html_escape(" !\"\#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"))

    assert_equal("", ERB::Util.html_escape(""))
    assert_equal("abc", ERB::Util.html_escape("abc"))
    assert_equal("&lt;&lt;", ERB::Util.html_escape("<\<"))

    assert_equal("", ERB::Util.html_escape(nil))
    assert_equal("123", ERB::Util.html_escape(123))
  end

  def test_concurrent_default_binding
    template1 = 'one <%= ERB.new(template2).result %>'

    eval 'template2 = "two"', TOPLEVEL_BINDING

    bug7046 = '[ruby-core:47638]'
    assert_equal("one two", ERB.new(template1).result, bug7046)
  end
end

class TestERBCore < Test::Unit::TestCase
  def setup
    @erb = ERB
  end

  def test_version
    assert_equal(String, @erb.version.class)
  end

  def test_core
    # [deprecated] Fix initializer later
    EnvUtil.suppress_warning do
      _test_core(nil)
      _test_core(0)
      _test_core(1)
    end
  end

  def _test_core(safe)
    erb = @erb.new("hello")
    assert_equal("hello", erb.result)

    erb = @erb.new("hello", safe, 0)
    assert_equal("hello", erb.result)

    erb = @erb.new("hello", safe, 1)
    assert_equal("hello", erb.result)

    erb = @erb.new("hello", safe, 2)
    assert_equal("hello", erb.result)

    src = <<EOS
%% hi
= hello
<% 3.times do |n| %>
% n=0
* <%= n %>
<% end %>
EOS

    ans = <<EOS
%% hi
= hello

% n=0
* 0

% n=0
* 1

% n=0
* 2

EOS
    erb = @erb.new(src)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, 0)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, '')
    assert_equal(ans, erb.result)

    ans = <<EOS
%% hi
= hello
% n=0
* 0% n=0
* 1% n=0
* 2
EOS
    erb = @erb.new(src, safe, 1)
    assert_equal(ans.chomp, erb.result)
    erb = @erb.new(src, safe, '>')
    assert_equal(ans.chomp, erb.result)

    ans  = <<EOS
%% hi
= hello
% n=0
* 0
% n=0
* 1
% n=0
* 2
EOS

    erb = @erb.new(src, safe, 2)
    assert_equal(ans, erb.result)
    erb = @erb.new(src, safe, '<>')
    assert_equal(ans, erb.result)

    ans = <<EOS
% hi
= hello

* 0

* 0

* 0

EOS
    erb = @erb.new(src, safe, '%')
    assert_equal(ans, erb.result)

    ans = <<EOS
% hi
= hello
* 0* 0* 0
EOS
    erb = @erb.new(src, safe, '%>')
    assert_equal(ans.chomp, erb.result)

    ans = <<EOS
% hi
= hello
* 0
* 0
* 0
EOS
    erb = @erb.new(src, safe, '%<>')
    assert_equal(ans, erb.result)
  end

  def test_trim_line1_with_carriage_return
    erb = @erb.new("<% 3.times do %>\r\nline\r\n<% end %>\r\n", trim_mode: '>')
    assert_equal("line\r\n" * 3, erb.result)

    erb = @erb.new("<% 3.times do %>\r\nline\r\n<% end %>\r\n", trim_mode: '%>')
    assert_equal("line\r\n" * 3, erb.result)
  end

  def test_trim_line2_with_carriage_return
    erb = @erb.new("<% 3.times do %>\r\nline\r\n<% end %>\r\n", trim_mode: '<>')
    assert_equal("line\r\n" * 3, erb.result)

    erb = @erb.new("<% 3.times do %>\r\nline\r\n<% end %>\r\n", trim_mode: '%<>')
    assert_equal("line\r\n" * 3, erb.result)
  end

  def test_explicit_trim_line_with_carriage_return
    erb = @erb.new("<%- 3.times do -%>\r\nline\r\n<%- end -%>\r\n", trim_mode: '-')
    assert_equal("line\r\n" * 3, erb.result)

    erb = @erb.new("<%- 3.times do -%>\r\nline\r\n<%- end -%>\r\n", trim_mode: '%-')
    assert_equal("line\r\n" * 3, erb.result)
  end

  def test_invalid_trim_mode
    assert_warning(/#{__FILE__}:#{__LINE__ + 1}/) do
      @erb.new("", trim_mode: 'abc-def')
    end

    assert_warning(/Invalid ERB trim mode/) do
      @erb.new("", trim_mode: 'abc-def')
    end

    assert_warning(/Invalid ERB trim mode/) do
      @erb.new("", trim_mode: '%<')
    end

    assert_warning(/Invalid ERB trim mode/) do
      @erb.new("", trim_mode: '%<>-')
    end

    assert_warning(/Invalid ERB trim mode/) do
      @erb.new("", trim_mode: 3)
    end
  end

  def test_run
    out = StringIO.new
    orig, $stdout = $stdout, out

    num = 3
    @erb.new('<%= num * 3 %>').run(binding)

    $stdout = orig
    out.rewind
    assert_equal('9', out.read)
    return unless num               # to remove warning
  end

  class Foo; end

  def test_def_class
    erb = @erb.new('hello')
    cls = erb.def_class
    assert_equal(Object, cls.superclass)
    assert_respond_to(cls.new, 'result')
    cls = erb.def_class(Foo)
    assert_equal(Foo, cls.superclass)
    assert_respond_to(cls.new, 'result')
    cls = erb.def_class(Object, 'erb')
    assert_equal(Object, cls.superclass)
    assert_respond_to(cls.new, 'erb')
  end

  def test_percent
    src = <<EOS
%n = 1
<%= n%>
EOS
    assert_equal("1\n", ERB.new(src, trim_mode: '%').result(binding))

    src = <<EOS
<%
%>
EOS
    ans = "\n"
    assert_equal(ans, ERB.new(src, trim_mode: '%').result(binding))

    src = "<%\n%>"
    # ans = "\n"
    ans = ""
    assert_equal(ans, ERB.new(src, trim_mode: '%').result(binding))

    src = <<EOS
<%
n = 1
%><%= n%>
EOS
    assert_equal("1\n", ERB.new(src, trim_mode: '%').result(binding))

    src = <<EOS
%n = 1
%% <% n = 2
n.times do |i|%>
%% %%><%%<%= i%><%
end%>
%%%
EOS
    ans = <<EOS
%\s
% %%><%0
% %%><%1
%%
EOS
    assert_equal(ans, ERB.new(src, trim_mode: '%').result(binding))
  end

  def test_def_erb_method
    klass = Class.new
    klass.module_eval do
      extend ERB::DefMethod
      fname = File.join(File.dirname(File.expand_path(__FILE__)), 'hello.erb')
      def_erb_method('hello', fname)
    end
    assert_respond_to(klass.new, 'hello')

    assert_not_respond_to(klass.new, 'hello_world')
    erb = @erb.new('hello, world')
    klass.module_eval do
      def_erb_method('hello_world', erb)
    end
    assert_respond_to(klass.new, 'hello_world')
  end

  def test_def_method_without_filename
    klass = Class.new
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    erb.filename = "test filename"
    assert_not_respond_to(klass.new, 'my_error')
    erb.def_method(klass, 'my_error')
    e = assert_raise(::TestERB::MyError) {
       klass.new.my_error
    }
    assert_match(/\A\(ERB\):1\b/, e.backtrace[0])
  end

  def test_def_method_with_fname
    klass = Class.new
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    erb.filename = "test filename"
    assert_not_respond_to(klass.new, 'my_error')
    erb.def_method(klass, 'my_error', 'test fname')
    e = assert_raise(::TestERB::MyError) {
       klass.new.my_error
    }
    assert_match(/\Atest fname:1\b/, e.backtrace[0])
  end

  def test_def_module
    klass = Class.new
    klass.include ERB.new('<%= val %>').def_module('render(val)')
    assert_equal('1', klass.new.render(1))
  end

  def test_escape
    src = <<EOS
1.<%% : <%="<%%"%>
2.%%> : <%="%%>"%>
3.
% x = "foo"
<%=x%>
4.
%% print "foo"
5.
%% <%="foo"%>
6.<%="
% print 'foo'
"%>
7.<%="
%% print 'foo'
"%>
EOS
    ans = <<EOS
1.<% : <%%
2.%%> : %>
3.
foo
4.
% print "foo"
5.
% foo
6.
% print 'foo'

7.
%% print 'foo'

EOS
    assert_equal(ans, ERB.new(src, trim_mode: '%').result)
  end

  def test_keep_lineno
    src = <<EOS
Hello,\s
% x = "World"
<%= x%>
% raise("lineno")
EOS

    erb = ERB.new(src, trim_mode: '%')
    e = assert_raise(RuntimeError) {
      erb.result
    }
    assert_match(/\A\(erb\):4\b/, e.backtrace[0].to_s)

    src = <<EOS
%>
Hello,\s
<% x = "World%%>
"%>
<%= x%>
EOS

    ans = <<EOS
%>Hello,\s
World%>
EOS
    assert_equal(ans, ERB.new(src, trim_mode: '>').result)

    ans = <<EOS
%>
Hello,\s

World%>
EOS
    assert_equal(ans, ERB.new(src, trim_mode: '<>').result)

    ans = <<EOS
%>
Hello,\s

World%>

EOS
    assert_equal(ans, ERB.new(src).result)

    src = <<EOS
Hello,\s
<% x = "World%%>
"%>
<%= x%>
<% raise("lineno") %>
EOS

    erb = ERB.new(src)
    e = assert_raise(RuntimeError) {
      erb.result
    }
    assert_match(/\A\(erb\):5\b/, e.backtrace[0].to_s)

    erb = ERB.new(src, trim_mode: '>')
    e = assert_raise(RuntimeError) {
      erb.result
    }
    assert_match(/\A\(erb\):5\b/, e.backtrace[0].to_s)

    erb = ERB.new(src, trim_mode: '<>')
    e = assert_raise(RuntimeError) {
      erb.result
    }
    assert_match(/\A\(erb\):5\b/, e.backtrace[0].to_s)

    src = <<EOS
% y = 'Hello'
<%- x = "World%%>
"-%>
<%= x %><%- x = nil -%>\s
<% raise("lineno") %>
EOS

    erb = ERB.new(src, trim_mode: '-')
    e = assert_raise(RuntimeError) {
      erb.result
    }
    assert_match(/\A\(erb\):5\b/, e.backtrace[0].to_s)

    erb = ERB.new(src, trim_mode: '%-')
    e = assert_raise(RuntimeError) {
      erb.result
    }
    assert_match(/\A\(erb\):5\b/, e.backtrace[0].to_s)
  end

  def test_explicit
    src = <<EOS
<% x = %w(hello world) -%>
NotSkip <%- y = x -%> NotSkip
<% x.each do |w| -%>
  <%- up = w.upcase -%>
  * <%= up %>
<% end -%>
 <%- z = nil -%> NotSkip <%- z = x %>
 <%- z.each do |w| -%>
   <%- down = w.downcase -%>
   * <%= down %>
   <%- up = w.upcase -%>
   * <%= up %>
 <%- end -%>
KeepNewLine <%- z = nil -%>\s
EOS

   ans = <<EOS
NotSkip  NotSkip
  * HELLO
  * WORLD
 NotSkip\s
   * hello
   * HELLO
   * world
   * WORLD
KeepNewLine \s
EOS
   assert_equal(ans, ERB.new(src, trim_mode: '-').result)
   assert_equal(ans, ERB.new(src, trim_mode: '-%').result)
  end

  def test_url_encode
    assert_equal("Programming%20Ruby%3A%20%20The%20Pragmatic%20Programmer%27s%20Guide",
                 ERB::Util.url_encode("Programming Ruby:  The Pragmatic Programmer's Guide"))

    assert_equal("%A5%B5%A5%F3%A5%D7%A5%EB",
                 ERB::Util.url_encode("\xA5\xB5\xA5\xF3\xA5\xD7\xA5\xEB".force_encoding("EUC-JP")))

    assert_equal("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
                 ERB::Util.url_encode("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"),
                 "should not escape any unreserved characters, as per RFC3986 Section 2.3")
  end

  def test_percent_after_etag
    assert_equal("1%", @erb.new("<%= 1 %>%", trim_mode: "%").result)
  end

  def test_token_extension
    extended_erb = Class.new(ERB)
    extended_erb.module_eval do
      def make_compiler(trim_mode)
        compiler = Class.new(ERB::Compiler)
        compiler.module_eval do
          def compile_stag(stag, out, scanner)
            case stag
            when '<%=='
              scanner.stag = stag
              add_put_cmd(out, content) if content.size > 0
              self.content = ''
            else
              super
            end
          end

          def compile_content(stag, out)
            case stag
            when '<%=='
              out.push("#{@insert_cmd}(::ERB::Util.html_escape(#{content}))")
            else
              super
            end
          end

          def make_scanner(src)
            scanner = Class.new(ERB::Compiler::SimpleScanner)
            scanner.module_eval do
              def stags
                ['<%=='] + super
              end
            end
            scanner.new(src, @trim_mode, @percent)
          end
        end
        compiler.new(trim_mode)
      end
    end

    src = <<~EOS
      <% tag = '<>' \%>
      <\%= tag \%>
      <\%== tag \%>
    EOS
    ans = <<~EOS

      <>
      &lt;&gt;
    EOS
    assert_equal(ans, extended_erb.new(src).result)
  end

  def test_frozen_string_literal
    bug12031 = '[ruby-core:73561] [Bug #12031]'
    e = @erb.new("<%#encoding: us-ascii%>a")
    e.src.sub!(/\A#(?:-\*-)?(.*)(?:-\*-)?/) {
      '# -*- \1; frozen-string-literal: true -*-'
    }
    assert_equal("a", e.result, bug12031)

    %w(false true).each do |flag|
      erb = @erb.new("<%#frozen-string-literal: #{flag}%><%=''.frozen?%>")
      assert_equal(flag, erb.result)
    end
  end

  def test_result_with_hash
    erb = @erb.new("<%= foo %>")
    assert_equal("1", erb.result_with_hash(foo: "1"))
  end

  def test_result_with_hash_does_not_use_caller_local_variables
    erb = @erb.new("<%= foo %>")
    foo = 1
    assert_raise(NameError) { erb.result_with_hash({}) }
    assert_equal("1", erb.result_with_hash(foo: foo))
  end

  def test_result_with_hash_does_not_modify_caller_binding
    erb = @erb.new("<%= foo %>")
    erb.result_with_hash(foo: "1")
    assert_equal(false, binding.local_variable_defined?(:foo))
  end

  def test_result_with_hash_does_not_modify_toplevel_binding
    erb = @erb.new("<%= foo %>")
    erb.result_with_hash(foo: "1")
    assert_equal(false, TOPLEVEL_BINDING.local_variable_defined?(:foo))
    TOPLEVEL_BINDING.eval 'template2 = "two"'
    erb = @erb.new("<%= template2 %>")
    erb.result_with_hash(template2: "TWO")
    assert_equal "two", TOPLEVEL_BINDING.local_variable_get("template2")
  end

  # This depends on the behavior that #local_variable_set raises TypeError by invalid key.
  def test_result_with_hash_with_invalid_keys_raises_type_error
    erb = @erb.new("<%= 1 %>")
    assert_raise(TypeError) { erb.result_with_hash({ 1 => "1" }) }
  end

  # Bug#14243
  def test_half_working_comment_backward_compatibility
    assert_nothing_raised do
      @erb.new("<% # comment %>\n").result
    end
  end

  # [deprecated] These interfaces will be removed later
  def test_deprecated_interface_warnings
    [nil, 0].each do |safe|
      assert_warning(/2nd argument of ERB.new is deprecated/) do
        ERB.new('', safe)
      end
    end

    [1, 2].each do |safe|
      assert_warn(/2nd argument of ERB.new is deprecated/) do
        ERB.new('', safe)
      end
    end

    [nil, '', '%', '%<>'].each do |trim|
      assert_warning(/3rd argument of ERB.new is deprecated/) do
        ERB.new('', nil, trim)
      end
    end

    [nil, '_erbout', '_hamlout'].each do |eoutvar|
      assert_warning(/4th argument of ERB.new is deprecated/) do
        ERB.new('', nil, nil, eoutvar)
      end
    end
  end

  def test_prohibited_marshal_dump
    erb = ERB.new("")
    assert_raise(TypeError) {Marshal.dump(erb)}
  end

  def test_prohibited_marshal_load
    erb = ERB.allocate
    erb.instance_variable_set(:@src, "")
    erb.instance_variable_set(:@lineno, 1)
    erb.instance_variable_set(:@_init, true)
    erb = Marshal.load(Marshal.dump(erb))
    assert_raise(ArgumentError) {erb.result}
  end
end

class TestERBCoreWOStrScan < TestERBCore
  def setup
    @save_map = ERB::Compiler::Scanner.instance_variable_get('@scanner_map')
    map = {[nil, false]=>ERB::Compiler::SimpleScanner}
    ERB::Compiler::Scanner.instance_variable_set('@scanner_map', map)
    super
  end

  def teardown
    ERB::Compiler::Scanner.instance_variable_set('@scanner_map', @save_map)
  end
end
