require 'mspec/guards/guard'

class BlockDeviceGuard < SpecGuard
  def match?
    platform_is_not :freebsd, :windows, :opal do
      block = `find /dev /devices -type b 2> /dev/null`
      return !(block.nil? || block.empty?)
    end

    false
  end
end

def with_block_device(&block)
  BlockDeviceGuard.new.run_if(:with_block_device, &block)
end
