# frozen_string_literal: false
module ProcCallSpecs
  def self.call
    proc {|a| a }.call("sometext")
  end

  def self.call_freeze
    proc {|a| a }.call("sometext".freeze)
  end
end
