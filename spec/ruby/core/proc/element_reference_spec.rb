require_relative '../../spec_helper'
require_relative 'shared/call'
require_relative 'shared/call_arguments'
require_relative 'fixtures/proc_aref'
require_relative 'fixtures/proc_aref_frozen'

describe "Proc#[]" do
  it_behaves_like :proc_call, :[]
  it_behaves_like :proc_call_block_args, :[]
end

describe "Proc#call on a Proc created with Proc.new" do
  it_behaves_like :proc_call_on_proc_new, :call
end

describe "Proc#call on a Proc created with Kernel#lambda or Kernel#proc" do
  it_behaves_like :proc_call_on_proc_or_lambda, :call
end

ruby_bug "#15118", ""..."2.6" do
  describe "Proc#[] with frozen_string_literals" do
    it "doesn't duplicate frozen strings" do
      ProcArefSpecs.aref.frozen?.should be_false
      ProcArefSpecs.aref_freeze.frozen?.should be_true
      ProcArefFrozenSpecs.aref.frozen?.should be_true
      ProcArefFrozenSpecs.aref_freeze.frozen?.should be_true
    end
  end
end
