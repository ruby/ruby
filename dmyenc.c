#define require(name) ruby_require_internal(name, (unsigned int)sizeof(name)-1)
int ruby_require_internal(const char *, int);

void
Init_enc(void)
{
    if (require("enc/encdb.so") == 1) {
	require("enc/trans/transdb.so");
    }
}
