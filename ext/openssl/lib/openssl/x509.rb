module OpenSSL
  module X509
    class StoreContext
      def cleanup
        warn "(#{caller.first}) OpenSSL::X509::StoreContext#cleanup is deprecated with no replacement" if $VERBOSE
      end
    end
  end
end
