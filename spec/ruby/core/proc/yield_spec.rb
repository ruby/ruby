require_relative '../../spec_helper'
require_relative 'shared/call'
require_relative 'shared/call_arguments'

describe "Proc#yield" do
  it_behaves_like :proc_call, :yield
  it_behaves_like :proc_call_block_args, :yield
end

describe "Proc#yield on a Proc created with Proc.new" do
  it_behaves_like :proc_call_on_proc_new, :yield
end

describe "Proc#yield on a Proc created with Kernel#lambda or Kernel#proc" do
  it_behaves_like :proc_call_on_proc_or_lambda, :yield
end
