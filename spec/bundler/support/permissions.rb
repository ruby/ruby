# frozen_string_literal: true
module Spec
  module Permissions
    def with_umask(new_umask)
      old_umask = File.umask(new_umask)
      yield if block_given?
    ensure
      File.umask(old_umask)
    end
  end
end
