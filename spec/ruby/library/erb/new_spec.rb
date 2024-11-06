require 'erb'
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "ERB.new" do
  before :all do
    @eruby_str = <<'END'
<ul>
<% list = [1,2,3] %>
<% for item in list %>
<% if item %>
<li><%= item %></li>
<% end %>
<% end %>
</ul>
END

    @eruby_str2 = <<'END'
<ul>
% list = [1,2,3]
%for item in list
%  if item
  <li><%= item %>
  <% end %>
<% end %>
</ul>
%%%
END

  end

  it "compiles eRuby script into ruby code when trim mode is 0 or not specified" do
    expected = "<ul>\n\n\n\n<li>1</li>\n\n\n\n<li>2</li>\n\n\n\n<li>3</li>\n\n\n</ul>\n"
    [0, nil].each do |trim_mode|
      ERBSpecs.new_erb(@eruby_str, trim_mode: trim_mode).result.should == expected
    end
  end

  it "warns invalid trim_mode" do
    -> do
      ERBSpecs.new_erb(@eruby_str, trim_mode: '')
    end.should complain(/Invalid ERB trim mode/)
  end

  it "removes '\n' when trim_mode is 1 or '>'" do
    expected = "<ul>\n<li>1</li>\n<li>2</li>\n<li>3</li>\n</ul>\n"
    [1, '>'].each do |trim_mode|
      ERBSpecs.new_erb(@eruby_str, trim_mode: trim_mode).result.should == expected
    end
  end

  it "removes spaces at beginning of line and '\n' when trim_mode is 2 or '<>'" do
    expected = "<ul>\n<li>1</li>\n<li>2</li>\n<li>3</li>\n</ul>\n"
    [2, '<>'].each do |trim_mode|
      ERBSpecs.new_erb(@eruby_str, trim_mode: trim_mode).result.should == expected
    end
  end

  it "removes spaces around '<%- -%>' when trim_mode is '-'" do
    expected = "<ul>\n  <li>1  <li>2  <li>3</ul>\n"
    input = <<'END'
<ul>
<%- for item in [1,2,3] -%>
  <%- if item -%>
  <li><%= item -%>
  <%- end -%>
<%- end -%>
</ul>
END

    ERBSpecs.new_erb(input, trim_mode: '-').result.should == expected
  end


  it "does not support '<%-= expr %> even when trim_mode is '-'" do

    input = <<'END'
<p>
  <%= expr -%>
  <%-= expr -%>
</p>
END

    -> {
      ERBSpecs.new_erb(input, trim_mode: '-').result
    }.should raise_error(SyntaxError)
  end

  it "regards lines starting with '%' as '<% ... %>' when trim_mode is '%'" do
    expected = "<ul>\n  <li>1\n  \n  <li>2\n  \n  <li>3\n  \n\n</ul>\n%%\n"
    ERBSpecs.new_erb(@eruby_str2, trim_mode: "%").result.should == expected
  end
  it "regards lines starting with '%' as '<% ... %>' and remove \"\\n\" when trim_mode is '%>'" do
    expected = "<ul>\n  <li>1    <li>2    <li>3  </ul>\n%%\n"
    ERBSpecs.new_erb(@eruby_str2, trim_mode: '%>').result.should == expected
  end


  it "regard lines starting with '%' as '<% ... %>' and remove \"\\n\" when trim_mode is '%<>'" do
    expected = "<ul>\n  <li>1\n  \n  <li>2\n  \n  <li>3\n  \n</ul>\n%%\n"
    ERBSpecs.new_erb(@eruby_str2, trim_mode: '%<>').result.should == expected
  end


  it "regard lines starting with '%' as '<% ... %>' and spaces around '<%- -%>' when trim_mode is '%-'" do
    expected = "<ul>\n<li>1</li>\n<li>2</li>\n</ul>\n%%\n"
    input = <<'END'
<ul>
%list = [1,2]
%for item in list
<li><%= item %></li>
<% end %></ul>
%%%
END

    ERBSpecs.new_erb(input, trim_mode: '%-').result.should == expected
  end

  it "changes '_erbout' variable name in the produced source" do
    input = @eruby_str
    match_erbout = ERB.new(input, trim_mode: nil).src
    match_buf = ERB.new(input, trim_mode: nil, eoutvar: 'buf').src
    match_erbout.gsub("_erbout", "buf").should == match_buf
  end


  it "ignores '<%# ... %>'" do
    input = <<'END'
<%# for item in list %>
<b><%#= item %></b>
<%# end %>
END
    ERBSpecs.new_erb(input).result.should == "\n<b></b>\n\n"
    ERBSpecs.new_erb(input, trim_mode: '<>').result.should == "<b></b>\n"
  end

  it "forget local variables defined previous one" do
    ERB.new(@eruby_str).result
    ->{ ERB.new("<%= list %>").result }.should raise_error(NameError)
  end

  describe "warning about arguments" do
    version_is ERB.version, "2.2.1" do #ruby_version_is "3.1" do
      it "warns when passed safe_level and later arguments" do
        -> {
          ERB.new(@eruby_str, nil, '%')
        }.should complain(/warning: Passing safe_level with the 2nd argument of ERB.new is deprecated. Do not use it, and specify other arguments as keyword arguments./)
      end

      it "does not warn when passed arguments as keyword argument" do
        -> {
          ERB.new(@eruby_str, trim_mode: '%')
        }.should_not complain(/warning: Passing safe_level with the 2nd argument of ERB.new is deprecated. Do not use it, and specify other arguments as keyword arguments./)
      end
    end
  end
end
