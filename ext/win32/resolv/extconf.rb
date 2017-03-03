if have_library('iphlpapi', 'GetNetworkParams')
  create_makefile('win32/resolv')
end
