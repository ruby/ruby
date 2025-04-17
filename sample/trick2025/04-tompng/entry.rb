                                                      $c=%q@E="                 
                                                  \e[4%d;37m%s\e[m"             
                                                ;n=32.chr;pu    ts"\e           
                                              [H\e[J#{$c=n*54+'    $c=%         
                                             q'+[64.chr]*2*$c+';e   val$        
                                            c.'+n*10+"\n"+n*57+"spl  it*'       
                                            '"+n*15}";n=l=0;R=->y=0 {n+=1       
                ;l=$c.lines.                map{|m|m=(0..79).chunk{380-n+       
           36*Math.sin(0.04.*it-n           )<9*y}.map{a=_2.map{m[it]}*''       
        ;_1&&E%[6,a]||a}*'';m!=l[~-y        +=1]&&$><<"\e[#{y}H#{m}\e[37H       
      ";m}};N=(Integer$*      [-1]resc       ue+30)*H=44100;alias:r:rand        
    ;F=->e,w=1{a=b=c=0;d=(       1-e)**0      .5*20;->v=r-0.5{a=a*w*e+v         
   ;b=b*w*e*e+v;d.*a-2*b+c=c*w     *e**3+       v}};A=->u,n,t{(0..n).           
  map{|i|u=u.shuffle.map{|w|R[];     a=u.s        ample;b,c,d=[[0.5             
 ,(0.2+r)*H/3*1.1**i,[[1+r/10,1+r/    10]][           i]||[1.2+                 
 r/10,1.3+r/5]],[0.3,r*H/2,[1,1+r/5   ]]][t                                     
];e,f=d.shuffle;g=b+r;h=b+r;(0..[w.  size/e,             a.size/f               
+c].max).map{g*(w[it*e]||0)+h*(a[[it-c,0].ma        x*f]||0)}}}};j=A[A          
[(0..9).map{a=F[0.998,1i**0.02];(0..28097).m     ap{a[].real.*0.1**(8.0*i       
t/H)-8e-6}},14,0].transpose.map{|d|a=[0]*3e3     ;15.times{|i|R      [];b=r     
 (3e3);d[i].each_with_index{a[c=_2+b]=(a[c]      ||0)+_1*0.63**i}}     ;a},9,   
 1][4..].flatten(1).shuffle;y=(0..3).map{F[     1-1e-5]};m=[-1,1].map    {[F[1  
  -1e-4],F[1-5e-5],it]};u=v=w=0;k=[],[],[]     ;z=F[0.7,1i**0.5];File.o   pen($ 
   *.grep(/[^\d]/)[0]||'output.wav','wb')      {|f|f<<'RIFF'+[N*4+36,'WA   VEfmt
    ',32,16,1,2,H,H*4,4,16,'data',N*4].p      ack('Va7cVvvVVvva4V');N.tim   es{|
      i|$><<E%[4,?#]if(i+1)*80/N!=i*80      /N;t=[i/1e5,(N-i)/2e5,1].min;a,b,c=k
        .map{it.shift||(j[20*r,0]=[g       =j.pop];a=1+r/3;it[0..]=(0..g.size).m
           ap{g[it*a]||0};0)};u=u         *0.96+r-0.5;v=v*0.99+d=r-0.5;w=w*0.8+d
                ;x=(z[].*1+0              .59i).imag;e=y.map(&:[]);f.<<m.map{|o,
                                           p,q|r=a+(b+c)/2+(b-c)*q/5;s=o[r.abs] 
                                            ;r=t*t*(3-2*t)*(r+s*w/1e4+p[s]*x/1  
                                             e7+[[u,0],[v,1]].sum{_1*1.5**(e[   
                                               _2]+q*e[_2+2]/9)}/32)/9;r/(1     
                                                 +r*r)**0.5*32768}.pack'v       
                                                    *'}};puts@;eval$c.          
                                                         split*''               
