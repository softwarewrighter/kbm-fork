int main(int,char**);
__attribute__((__section__(".text.startup"))) 
void _start(){
 asm volatile ("subq $8,%%rsp"::);
#ifdef KSYS
 // Zero k's globals: BareMetal loads the flat k.app without clearing them,
 // and after UEFI firmware (or on real hardware) that memory is not zero.
 // With -mcmodel=large they all live in .lbss (see app.ld), not .bss.
 // PORTABLE builds only; the default k.app stays byte-identical.
 extern char __lbss_start[],__lbss_end[];
 asm volatile ("rep stosb"::"D"(__lbss_start),"c"(__lbss_end-__lbss_start),"a"(0):"memory");
#endif
 char*v[2]={"k",0};
 main(1,v);
 asm volatile ("addq $8,%%rsp"::);
}

#include<libBareMetal.c>
static char b_in(void) {
 for(;;) {
  asm volatile ("hlt"::);
  char c=b_input();
  if(!c) continue;
  c=c==0x1c?'\n':c;
  b_output(&c,1);
  return c;
}}
u64 b_read(long fd,char*s,u64 n) {
 u64 i=0;
 for(;i<n;i++) {
  char c=b_in();
  s[i]=c;
  if(c=='\n') break;
 }
 return i;
}
