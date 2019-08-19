require_relative '../../spec_helper'

describe "The TOPLEVEL_BINDING constant" do
  it "only includes local variables defined in the main script, not in required files or eval" do
    binding_toplevel_variables = ruby_exe(fixture(__FILE__, "toplevel_binding_variables.rb"))
    binding_toplevel_variables.should == "[:required_after, [:main_script]]\n[:main_script]\n"
  end

  it "has no local variables in files required before the main script" do
    required = fixture(__FILE__, 'toplevel_binding_required_before.rb')
    out = ruby_exe("a=1; p TOPLEVEL_BINDING.local_variables.sort; b=2", options: "-r#{required}")
    out.should == "[:required_before, []]\n[:a, :b]\n"
  end

  it "merges local variables of the main script with dynamically-defined Binding variables" do
    required = fixture(__FILE__, 'toplevel_binding_dynamic_required.rb')
    out = ruby_exe(fixture(__FILE__, 'toplevel_binding_dynamic.rb'), options: "-r#{required}")
    out.should == <<EOS
[:dynamic_set_required]
[:dynamic_set_required, :main_script]
[:dynamic_set_main, :dynamic_set_required, :main_script]
EOS
  end

  it "gets updated variables values as they are defined and set" do
    out = ruby_exe(fixture(__FILE__, "toplevel_binding_values.rb"))
    out.should == "nil\nnil\n1\nnil\n3\n2\n"
  end

  it "is always the same object for all top levels" do
    binding_toplevel_id = ruby_exe(fixture(__FILE__, "toplevel_binding_id.rb"))
    binding_toplevel_id.should == "1\n"
  end
end
