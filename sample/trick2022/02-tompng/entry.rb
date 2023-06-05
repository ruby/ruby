           q=->{!sleep                  _1/1e2};p=(
        c=0..2).map{[_1/9r          ,0,5**_1.i/3,1,0]}
     require'socket';puts'op'    "en http://localhost:#{(
   w=TCPServer.new$*[0]||0).addr[1]}";Thread.new{q[2];f=[-1
  ]*s=3;t=Time.now.to_f;p.select!{0<_1[3]=[_1[3]+_1[4]/8.0,1
 ].min};9.times{h=p.map{[2**(_1*t.i)/_4**0.5/(1+Math.sin(2*t-
 9*_1%2)**32/16),_2+_4*(  _3-_2)]};r=[s*3/2,84].min;g=->{x,y=
(s*(1+_1+1i)/2).rect;x<0  ||x>=s-1||y<0||y>=s-1?0:((l=f[y+1])[
x+1]*(a=x%1)+(1-a)*l[x]   )*(b=y%1)+(1-b)*((l=f[y])[x+1]*a+(1-
a)*l[x])};f=(1..r).map     {|y|(1..r).map{|x|z=1.5+1.5i-3.0*(y
.i+x)/r;[h.sum{g[_1.*z     +_2]}*0.9,1].min}};s=r};c=f.flatten
redo};loop{s=w.accept   ;   Thread.new{r=s.gets;h='HTTP/1.1 '+
"200 OK\r\nContent-"   'T'  "ype:text/html\r\n\r\n";r['/ ']?s.
 <<(h+'<style>ifram'  'e{'   'opacity:0;height:0;}input{wid'+
 'th:252px;}</styl'   'e>'   '<form target="i"><input src="'+
  "g#{rand}\" type"  '="im'  'age"><iframe name="i"></ifra'+
   'me></form>'):r   ['/g']   ?(h[/:.+l/]=?:'image/gif';s<<
                    h+'GIF8'  '7a'+[84,
      84,246,0,*(0..383).map   {15*_1.   /(383r)**(3-_1%
       3)*17}].pack('v3c*');   loop{    s<<[67434785,5,
         44,84,84,7,c.map{_1*  127}   .each_slice(126
           ).map{[127,128,*_1   ]    .pack'c*'}*'',
             1,129].pack('V3x'     'v2na*c2x');q[
               5];q.[]1while(r   ==r=c)}):(x,y,
                 z=r.scan(/\d+/).map{_1.to_f/
                   126-1};z&&p<<[rand-0.5,(
                      z=x+y.i)*1.5,z/(z.
                        abs+0.9),0,-p[
                          -3][4]=-1]
                           s.<<h);s
                            .close
                              }}
