#!/usr/bin/env ruby

ip_name = 'remote_ip'

fork{
  exec "/usr/bin/env ruby -r tk -e \"Tk.appname('#{ip_name}');Tk.mainloop\""
}

require 'remote-tk'

15.times{
  break if TkWinfo.interps.find{|ip| ip =~ /^#{ip_name}/}
  sleep 1
}

p TkWinfo.interps

ip = RemoteTkIp.new(ip_name)

btns = []
ip.eval_proc{
  btns << 
    TkButton.new(:command=>proc{
		   puts 'This procesure is on the controller-ip (Ruby-side)'
		 }, 
		 :text=>'print on controller-ip (Ruby-side)').pack(:fill=>:x)

  btns << 
    TkButton.new(:command=>
		   'puts {This procesure is on the remote-ip (Tk-side)}',
		 :text=>'print on remote-ip (Tk-side)').pack(:fill=>:x)

  btns << 
    TkButton.new(:command=>
                   'ruby {
                     puts "This procedure is on the remote-ip (Ruby-side)"
                     p Array.new(3,"ruby")
                    }', 
		 :text=>'ruby cmd on the remote-ip').pack(:fill=>:x)

  TkButton.new(:command=>'exit', :text=>'QUIT').pack(:fill=>:x)
}

btns.each_with_index{|b, idx|
  TkButton.new(:command=>proc{ip.eval_proc{b.flash}}, 
	       :text=>"flash button-#{idx}", 
	       :padx=>10).pack(:padx=>10, :pady=>2)
}

TkButton.new(:command=>proc{exit}, :text=>'QUIT', 
	     :padx=>10, :pady=>7).pack(:padx=>10, :pady=>7)

Tk.mainloop
