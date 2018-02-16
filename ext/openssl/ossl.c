/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"
#include <stdarg.h> /* for ossl_raise */
#include <ruby/thread_native.h> /* for OpenSSL < 1.1.0 locks */

/*
 * Data Conversion
 */
#define OSSL_IMPL_ARY2SK(name, type, expected_class, dup)	\
STACK_OF(type) *						\
ossl_##name##_ary2sk0(VALUE ary)				\
{								\
    STACK_OF(type) *sk;						\
    VALUE val;							\
    type *x;							\
    int i;							\
    								\
    Check_Type(ary, T_ARRAY);					\
    sk = sk_##type##_new_null();				\
    if (!sk) ossl_raise(eOSSLError, NULL);			\
    								\
    for (i = 0; i < RARRAY_LEN(ary); i++) {			\
	val = rb_ary_entry(ary, i);				\
	if (!rb_obj_is_kind_of(val, expected_class)) {		\
	    sk_##type##_pop_free(sk, type##_free);		\
	    ossl_raise(eOSSLError, "object in array not"	\
		       " of class ##type##");			\
	}							\
	x = dup(val); /* NEED TO DUP */				\
	sk_##type##_push(sk, x);				\
    }								\
    return sk;							\
}								\
								\
STACK_OF(type) *						\
ossl_protect_##name##_ary2sk(VALUE ary, int *status)		\
{								\
    return (STACK_OF(type)*)rb_protect(				\
	    (VALUE (*)(VALUE))ossl_##name##_ary2sk0,		\
	    ary,						\
	    status);						\
}								\
								\
STACK_OF(type) *						\
ossl_##name##_ary2sk(VALUE ary)					\
{								\
    STACK_OF(type) *sk;						\
    int status = 0;						\
    								\
    sk = ossl_protect_##name##_ary2sk(ary, &status);		\
    if (status) rb_jump_tag(status);				\
								\
    return sk;							\
}
OSSL_IMPL_ARY2SK(x509, X509, cX509Cert, DupX509CertPtr)

#define OSSL_IMPL_SK2ARY(name, type)	        \
VALUE						\
ossl_##name##_sk2ary(const STACK_OF(type) *sk)	\
{						\
    type *t;					\
    int i, num;					\
    VALUE ary;					\
						\
    if (!sk) {					\
	OSSL_Debug("empty sk!");		\
	return Qnil;				\
    }						\
    num = sk_##type##_num(sk);			\
    if (num < 0) {				\
	OSSL_Debug("items in sk < -1???");	\
	return rb_ary_new();			\
    }						\
    ary = rb_ary_new2(num);			\
						\
    for (i=0; i<num; i++) {			\
	t = sk_##type##_value(sk, i);		\
	rb_ary_push(ary, ossl_##name##_new(t));	\
    }						\
    return ary;					\
}
OSSL_IMPL_SK2ARY(x509, X509)
OSSL_IMPL_SK2ARY(x509crl, X509_CRL)
OSSL_IMPL_SK2ARY(x509name, X509_NAME)

static VALUE
ossl_str_new_i(VALUE size)
{
    return rb_str_new(NULL, (long)size);
}

VALUE
ossl_str_new(const char *ptr, long len, int *pstate)
{
    VALUE str;
    int state;

    str = rb_protect(ossl_str_new_i, len, &state);
    if (pstate)
	*pstate = state;
    if (state) {
	if (!pstate)
	    rb_set_errinfo(Qnil);
	return Qnil;
    }
    if (ptr)
	memcpy(RSTRING_PTR(str), ptr, len);
    return str;
}

VALUE
ossl_buf2str(char *buf, int len)
{
    VALUE str;
    int state;

    str = ossl_str_new(buf, len, &state);
    OPENSSL_free(buf);
    if (state)
	rb_jump_tag(state);
    return str;
}

void
ossl_bin2hex(unsigned char *in, char *out, size_t inlen)
{
    const char *hex = "0123456789abcdef";
    size_t i;

    assert(inlen <= LONG_MAX / 2);
    for (i = 0; i < inlen; i++) {
	unsigned char p = in[i];

	out[i * 2 + 0] = hex[p >> 4];
	out[i * 2 + 1] = hex[p & 0x0f];
    }
}

/*
 * our default PEM callback
 */
VALUE
ossl_pem_passwd_value(VALUE pass)
{
    if (NIL_P(pass))
	return Qnil;

    StringValue(pass);

    /* PEM_BUFSIZE is currently used as the second argument of pem_password_cb,
     * that is +max_len+ of ossl_pem_passwd_cb() */
    if (RSTRING_LEN(pass) > PEM_BUFSIZE)
	ossl_raise(eOSSLError, "password must not be longer than %d bytes", PEM_BUFSIZE);

    return pass;
}

static VALUE
ossl_pem_passwd_cb0(VALUE flag)
{
    VALUE pass = rb_yield(flag);
    if (NIL_P(pass))
	return Qnil;
    StringValue(pass);
    return pass;
}

int
ossl_pem_passwd_cb(char *buf, int max_len, int flag, void *pwd_)
{
    long len;
    int status;
    VALUE rflag, pass = (VALUE)pwd_;

    if (RTEST(pass)) {
	/* PEM_def_callback(buf, max_len, flag, StringValueCStr(pass)) does not
	 * work because it does not allow NUL characters and truncates to 1024
	 * bytes silently if the input is over 1024 bytes */
	if (RB_TYPE_P(pass, T_STRING)) {
	    len = RSTRING_LEN(pass);
	    if (len <= max_len) {
		memcpy(buf, RSTRING_PTR(pass), len);
		return (int)len;
	    }
	}
	OSSL_Debug("passed data is not valid String???");
	return -1;
    }

    if (!rb_block_given_p()) {
	return PEM_def_callback(buf, max_len, flag, NULL);
    }

    while (1) {
	/*
	 * when the flag is nonzero, this passphrase
	 * will be used to perform encryption; otherwise it will
	 * be used to perform decryption.
	 */
	rflag = flag ? Qtrue : Qfalse;
	pass  = rb_protect(ossl_pem_passwd_cb0, rflag, &status);
	if (status) {
	    /* ignore an exception raised. */
	    rb_set_errinfo(Qnil);
	    return -1;
	}
	if (NIL_P(pass))
	    return -1;
	len = RSTRING_LEN(pass);
	if (len > max_len) {
	    rb_warning("password must not be longer than %d bytes", max_len);
	    continue;
	}
	memcpy(buf, RSTRING_PTR(pass), len);
	break;
    }
    return (int)len;
}

/*
 * main module
 */
VALUE mOSSL;

/*
 * OpenSSLError < StandardError
 */
VALUE eOSSLError;

/*
 * Convert to DER string
 */
static ID ossl_s_to_der;

VALUE
ossl_to_der(VALUE obj)
{
    VALUE tmp;

    tmp = rb_funcall(obj, ossl_s_to_der, 0);
    StringValue(tmp);

    return tmp;
}

VALUE
ossl_to_der_if_possible(VALUE obj)
{
    if(rb_respond_to(obj, ossl_s_to_der))
	return ossl_to_der(obj);
    return obj;
}

/*
 * Errors
 */
static VALUE
ossl_make_error(VALUE exc, const char *fmt, va_list args)
{
    VALUE str = Qnil;
    unsigned long e;

    if (fmt) {
	str = rb_vsprintf(fmt, args);
    }
    e = ERR_peek_last_error();
    if (e) {
	const char *msg = ERR_reason_error_string(e);

	if (NIL_P(str)) {
	    if (msg) str = rb_str_new_cstr(msg);
	}
	else {
	    if (RSTRING_LEN(str)) rb_str_cat2(str, ": ");
	    rb_str_cat2(str, msg ? msg : "(null)");
	}
	ossl_clear_error();
    }

    if (NIL_P(str)) str = rb_str_new(0, 0);
    return rb_exc_new3(exc, str);
}

void
ossl_raise(VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE err;
    va_start(args, fmt);
    err = ossl_make_error(exc, fmt, args);
    va_end(args);
    rb_exc_raise(err);
}

void
ossl_clear_error(void)
{
    if (dOSSL == Qtrue) {
	unsigned long e;
	const char *file, *data, *errstr;
	int line, flags;

	while ((e = ERR_get_error_line_data(&file, &line, &data, &flags))) {
	    errstr = ERR_error_string(e, NULL);
	    if (!errstr)
		errstr = "(null)";

	    if (flags & ERR_TXT_STRING) {
		if (!data)
		    data = "(null)";
		rb_warn("error on stack: %s (%s)", errstr, data);
	    }
	    else {
		rb_warn("error on stack: %s", errstr);
	    }
	}
    }
    else {
	ERR_clear_error();
    }
}

/*
 * call-seq:
 *   OpenSSL.errors -> [String...]
 *
 * See any remaining errors held in queue.
 *
 * Any errors you see here are probably due to a bug in Ruby's OpenSSL
 * implementation.
 */
VALUE
ossl_get_errors(void)
{
    VALUE ary;
    long e;

    ary = rb_ary_new();
    while ((e = ERR_get_error()) != 0){
        rb_ary_push(ary, rb_str_new2(ERR_error_string(e, NULL)));
    }

    return ary;
}

/*
 * Debug
 */
VALUE dOSSL;

#if !defined(HAVE_VA_ARGS_MACRO)
void
ossl_debug(const char *fmt, ...)
{
    va_list args;

    if (dOSSL == Qtrue) {
	fprintf(stderr, "OSSL_DEBUG: ");
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	va_end(args);
	fprintf(stderr, " [CONTEXT N/A]\n");
    }
}
#endif

/*
 * call-seq:
 *   OpenSSL.debug -> true | false
 */
static VALUE
ossl_debug_get(VALUE self)
{
    return dOSSL;
}

/*
 * call-seq:
 *   OpenSSL.debug = boolean -> boolean
 *
 * Turns on or off debug mode. With debug mode, all erros added to the OpenSSL
 * error queue will be printed to stderr.
 */
static VALUE
ossl_debug_set(VALUE self, VALUE val)
{
    dOSSL = RTEST(val) ? Qtrue : Qfalse;

    return val;
}

/*
 * call-seq
 *   OpenSSL.fips_mode -> true | false
 */
static VALUE
ossl_fips_mode_get(VALUE self)
{

#ifdef OPENSSL_FIPS
    VALUE enabled;
    enabled = FIPS_mode() ? Qtrue : Qfalse;
    return enabled;
#else
    return Qfalse;
#endif
}

/*
 * call-seq:
 *   OpenSSL.fips_mode = boolean -> boolean
 *
 * Turns FIPS mode on or off. Turning on FIPS mode will obviously only have an
 * effect for FIPS-capable installations of the OpenSSL library. Trying to do
 * so otherwise will result in an error.
 *
 * === Examples
 *   OpenSSL.fips_mode = true   # turn FIPS mode on
 *   OpenSSL.fips_mode = false  # and off again
 */
static VALUE
ossl_fips_mode_set(VALUE self, VALUE enabled)
{

#ifdef OPENSSL_FIPS
    if (RTEST(enabled)) {
	int mode = FIPS_mode();
	if(!mode && !FIPS_mode_set(1)) /* turning on twice leads to an error */
	    ossl_raise(eOSSLError, "Turning on FIPS mode failed");
    } else {
	if(!FIPS_mode_set(0)) /* turning off twice is OK */
	    ossl_raise(eOSSLError, "Turning off FIPS mode failed");
    }
    return enabled;
#else
    if (RTEST(enabled))
	ossl_raise(eOSSLError, "This version of OpenSSL does not support FIPS mode");
    return enabled;
#endif
}

#if defined(OSSL_DEBUG)
#if !defined(LIBRESSL_VERSION_NUMBER) && \
    (OPENSSL_VERSION_NUMBER >= 0x10100000 && !defined(OPENSSL_NO_CRYPTO_MDEBUG) || \
     defined(CRYPTO_malloc_debug_init))
/*
 * call-seq:
 *   OpenSSL.mem_check_start -> nil
 *
 * Calls CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON). Starts tracking memory
 * allocations. See also OpenSSL.print_mem_leaks.
 *
 * This is available only when built with a capable OpenSSL and --enable-debug
 * configure option.
 */
static VALUE
mem_check_start(VALUE self)
{
	CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON);
	return Qnil;
}

/*
 * call-seq:
 *   OpenSSL.print_mem_leaks -> true | false
 *
 * For debugging the Ruby/OpenSSL library. Calls CRYPTO_mem_leaks_fp(stderr).
 * Prints detected memory leaks to standard error. This cleans the global state
 * up thus you cannot use any methods of the library after calling this.
 *
 * Returns +true+ if leaks detected, +false+ otherwise.
 *
 * This is available only when built with a capable OpenSSL and --enable-debug
 * configure option.
 *
 * === Example
 *   OpenSSL.mem_check_start
 *   NOT_GCED = OpenSSL::PKey::RSA.new(256)
 *
 *   END {
 *     GC.start
 *     OpenSSL.print_mem_leaks # will print the leakage
 *   }
 */
static VALUE
print_mem_leaks(VALUE self)
{
#if OPENSSL_VERSION_NUMBER >= 0x10100000
    int ret;
#endif

    BN_CTX_free(ossl_bn_ctx);
    ossl_bn_ctx = NULL;

#if OPENSSL_VERSION_NUMBER >= 0x10100000
    ret = CRYPTO_mem_leaks_fp(stderr);
    if (ret < 0)
	ossl_raise(eOSSLError, "CRYPTO_mem_leaks_fp");
    return ret ? Qfalse : Qtrue;
#else
    CRYPTO_mem_leaks_fp(stderr);
    return Qnil;
#endif
}
#endif
#endif

#if !defined(HAVE_OPENSSL_110_THREADING_API)
/**
 * Stores locks needed for OpenSSL thread safety
 */
struct CRYPTO_dynlock_value {
    rb_nativethread_lock_t lock;
    rb_nativethread_id_t owner;
    size_t count;
};

static void
ossl_lock_init(struct CRYPTO_dynlock_value *l)
{
    rb_nativethread_lock_initialize(&l->lock);
    l->count = 0;
}

static void
ossl_lock_unlock(int mode, struct CRYPTO_dynlock_value *l)
{
    if (mode & CRYPTO_LOCK) {
	/* TODO: rb_nativethread_id_t is not necessarily compared with ==. */
	rb_nativethread_id_t tid = rb_nativethread_self();
	if (l->count && l->owner == tid) {
	    l->count++;
	    return;
	}
	rb_nativethread_lock_lock(&l->lock);
	l->owner = tid;
	l->count = 1;
    } else {
	if (!--l->count)
	    rb_nativethread_lock_unlock(&l->lock);
    }
}

static struct CRYPTO_dynlock_value *
ossl_dyn_create_callback(const char *file, int line)
{
    /* Do not use xmalloc() here, since it may raise NoMemoryError */
    struct CRYPTO_dynlock_value *dynlock =
	OPENSSL_malloc(sizeof(struct CRYPTO_dynlock_value));
    if (dynlock)
	ossl_lock_init(dynlock);
    return dynlock;
}

static void
ossl_dyn_lock_callback(int mode, struct CRYPTO_dynlock_value *l, const char *file, int line)
{
    ossl_lock_unlock(mode, l);
}

static void
ossl_dyn_destroy_callback(struct CRYPTO_dynlock_value *l, const char *file, int line)
{
    rb_nativethread_lock_destroy(&l->lock);
    OPENSSL_free(l);
}

static void ossl_threadid_func(CRYPTO_THREADID *id)
{
    /* register native thread id */
    CRYPTO_THREADID_set_pointer(id, (void *)rb_nativethread_self());
}

static struct CRYPTO_dynlock_value *ossl_locks;

static void
ossl_lock_callback(int mode, int type, const char *file, int line)
{
    ossl_lock_unlock(mode, &ossl_locks[type]);
}

static void Init_ossl_locks(void)
{
    int i;
    int num_locks = CRYPTO_num_locks();

    ossl_locks = ALLOC_N(struct CRYPTO_dynlock_value, num_locks);
    for (i = 0; i < num_locks; i++)
	ossl_lock_init(&ossl_locks[i]);

    CRYPTO_THREADID_set_callback(ossl_threadid_func);
    CRYPTO_set_locking_callback(ossl_lock_callback);
    CRYPTO_set_dynlock_create_callback(ossl_dyn_create_callback);
    CRYPTO_set_dynlock_lock_callback(ossl_dyn_lock_callback);
    CRYPTO_set_dynlock_destroy_callback(ossl_dyn_destroy_callback);
}
#endif /* !HAVE_OPENSSL_110_THREADING_API */

/*
 * OpenSSL provides SSL, TLS and general purpose cryptography.  It wraps the
 * OpenSSL[https://www.openssl.org/] library.
 *
 * = Examples
 *
 * All examples assume you have loaded OpenSSL with:
 *
 *   require 'openssl'
 *
 * These examples build atop each other.  For example the key created in the
 * next is used in throughout these examples.
 *
 * == Keys
 *
 * === Creating a Key
 *
 * This example creates a 2048 bit RSA keypair and writes it to the current
 * directory.
 *
 *   key = OpenSSL::PKey::RSA.new 2048
 *
 *   open 'private_key.pem', 'w' do |io| io.write key.to_pem end
 *   open 'public_key.pem', 'w' do |io| io.write key.public_key.to_pem end
 *
 * === Exporting a Key
 *
 * Keys saved to disk without encryption are not secure as anyone who gets
 * ahold of the key may use it unless it is encrypted.  In order to securely
 * export a key you may export it with a pass phrase.
 *
 *   cipher = OpenSSL::Cipher.new 'AES-128-CBC'
 *   pass_phrase = 'my secure pass phrase goes here'
 *
 *   key_secure = key.export cipher, pass_phrase
 *
 *   open 'private.secure.pem', 'w' do |io|
 *     io.write key_secure
 *   end
 *
 * OpenSSL::Cipher.ciphers returns a list of available ciphers.
 *
 * === Loading a Key
 *
 * A key can also be loaded from a file.
 *
 *   key2 = OpenSSL::PKey::RSA.new File.read 'private_key.pem'
 *   key2.public? # => true
 *   key2.private? # => true
 *
 * or
 *
 *   key3 = OpenSSL::PKey::RSA.new File.read 'public_key.pem'
 *   key3.public? # => true
 *   key3.private? # => false
 *
 * === Loading an Encrypted Key
 *
 * OpenSSL will prompt you for your pass phrase when loading an encrypted key.
 * If you will not be able to type in the pass phrase you may provide it when
 * loading the key:
 *
 *   key4_pem = File.read 'private.secure.pem'
 *   pass_phrase = 'my secure pass phrase goes here'
 *   key4 = OpenSSL::PKey::RSA.new key4_pem, pass_phrase
 *
 * == RSA Encryption
 *
 * RSA provides encryption and decryption using the public and private keys.
 * You can use a variety of padding methods depending upon the intended use of
 * encrypted data.
 *
 * === Encryption & Decryption
 *
 * Asymmetric public/private key encryption is slow and victim to attack in
 * cases where it is used without padding or directly to encrypt larger chunks
 * of data. Typical use cases for RSA encryption involve "wrapping" a symmetric
 * key with the public key of the recipient who would "unwrap" that symmetric
 * key again using their private key.
 * The following illustrates a simplified example of such a key transport
 * scheme. It shouldn't be used in practice, though, standardized protocols
 * should always be preferred.
 *
 *   wrapped_key = key.public_encrypt key
 *
 * A symmetric key encrypted with the public key can only be decrypted with
 * the corresponding private key of the recipient.
 *
 *   original_key = key.private_decrypt wrapped_key
 *
 * By default PKCS#1 padding will be used, but it is also possible to use
 * other forms of padding, see PKey::RSA for further details.
 *
 * === Signatures
 *
 * Using "private_encrypt" to encrypt some data with the private key is
 * equivalent to applying a digital signature to the data. A verifying
 * party may validate the signature by comparing the result of decrypting
 * the signature with "public_decrypt" to the original data. However,
 * OpenSSL::PKey already has methods "sign" and "verify" that handle
 * digital signatures in a standardized way - "private_encrypt" and
 * "public_decrypt" shouldn't be used in practice.
 *
 * To sign a document, a cryptographically secure hash of the document is
 * computed first, which is then signed using the private key.
 *
 *   digest = OpenSSL::Digest::SHA256.new
 *   signature = key.sign digest, document
 *
 * To validate the signature, again a hash of the document is computed and
 * the signature is decrypted using the public key. The result is then
 * compared to the hash just computed, if they are equal the signature was
 * valid.
 *
 *   digest = OpenSSL::Digest::SHA256.new
 *   if key.verify digest, signature, document
 *     puts 'Valid'
 *   else
 *     puts 'Invalid'
 *   end
 *
 * == PBKDF2 Password-based Encryption
 *
 * If supported by the underlying OpenSSL version used, Password-based
 * Encryption should use the features of PKCS5. If not supported or if
 * required by legacy applications, the older, less secure methods specified
 * in RFC 2898 are also supported (see below).
 *
 * PKCS5 supports PBKDF2 as it was specified in PKCS#5
 * v2.0[http://www.rsa.com/rsalabs/node.asp?id=2127]. It still uses a
 * password, a salt, and additionally a number of iterations that will
 * slow the key derivation process down. The slower this is, the more work
 * it requires being able to brute-force the resulting key.
 *
 * === Encryption
 *
 * The strategy is to first instantiate a Cipher for encryption, and
 * then to generate a random IV plus a key derived from the password
 * using PBKDF2. PKCS #5 v2.0 recommends at least 8 bytes for the salt,
 * the number of iterations largely depends on the hardware being used.
 *
 *   cipher = OpenSSL::Cipher.new 'AES-128-CBC'
 *   cipher.encrypt
 *   iv = cipher.random_iv
 *
 *   pwd = 'some hopefully not to easily guessable password'
 *   salt = OpenSSL::Random.random_bytes 16
 *   iter = 20000
 *   key_len = cipher.key_len
 *   digest = OpenSSL::Digest::SHA256.new
 *
 *   key = OpenSSL::PKCS5.pbkdf2_hmac(pwd, salt, iter, key_len, digest)
 *   cipher.key = key
 *
 *   Now encrypt the data:
 *
 *   encrypted = cipher.update document
 *   encrypted << cipher.final
 *
 * === Decryption
 *
 * Use the same steps as before to derive the symmetric AES key, this time
 * setting the Cipher up for decryption.
 *
 *   cipher = OpenSSL::Cipher.new 'AES-128-CBC'
 *   cipher.decrypt
 *   cipher.iv = iv # the one generated with #random_iv
 *
 *   pwd = 'some hopefully not to easily guessable password'
 *   salt = ... # the one generated above
 *   iter = 20000
 *   key_len = cipher.key_len
 *   digest = OpenSSL::Digest::SHA256.new
 *
 *   key = OpenSSL::PKCS5.pbkdf2_hmac(pwd, salt, iter, key_len, digest)
 *   cipher.key = key
 *
 *   Now decrypt the data:
 *
 *   decrypted = cipher.update encrypted
 *   decrypted << cipher.final
 *
 * == PKCS #5 Password-based Encryption
 *
 * PKCS #5 is a password-based encryption standard documented at
 * RFC2898[http://www.ietf.org/rfc/rfc2898.txt].  It allows a short password or
 * passphrase to be used to create a secure encryption key. If possible, PBKDF2
 * as described above should be used if the circumstances allow it.
 *
 * PKCS #5 uses a Cipher, a pass phrase and a salt to generate an encryption
 * key.
 *
 *   pass_phrase = 'my secure pass phrase goes here'
 *   salt = '8 octets'
 *
 * === Encryption
 *
 * First set up the cipher for encryption
 *
 *   encryptor = OpenSSL::Cipher.new 'AES-128-CBC'
 *   encryptor.encrypt
 *   encryptor.pkcs5_keyivgen pass_phrase, salt
 *
 * Then pass the data you want to encrypt through
 *
 *   encrypted = encryptor.update 'top secret document'
 *   encrypted << encryptor.final
 *
 * === Decryption
 *
 * Use a new Cipher instance set up for decryption
 *
 *   decryptor = OpenSSL::Cipher.new 'AES-128-CBC'
 *   decryptor.decrypt
 *   decryptor.pkcs5_keyivgen pass_phrase, salt
 *
 * Then pass the data you want to decrypt through
 *
 *   plain = decryptor.update encrypted
 *   plain << decryptor.final
 *
 * == X509 Certificates
 *
 * === Creating a Certificate
 *
 * This example creates a self-signed certificate using an RSA key and a SHA1
 * signature.
 *
 *   key = OpenSSL::PKey::RSA.new 2048
 *   name = OpenSSL::X509::Name.parse 'CN=nobody/DC=example'
 *
 *   cert = OpenSSL::X509::Certificate.new
 *   cert.version = 2
 *   cert.serial = 0
 *   cert.not_before = Time.now
 *   cert.not_after = Time.now + 3600
 *
 *   cert.public_key = key.public_key
 *   cert.subject = name
 *
 * === Certificate Extensions
 *
 * You can add extensions to the certificate with
 * OpenSSL::SSL::ExtensionFactory to indicate the purpose of the certificate.
 *
 *   extension_factory = OpenSSL::X509::ExtensionFactory.new nil, cert
 *
 *   cert.add_extension \
 *     extension_factory.create_extension('basicConstraints', 'CA:FALSE', true)
 *
 *   cert.add_extension \
 *     extension_factory.create_extension(
 *       'keyUsage', 'keyEncipherment,dataEncipherment,digitalSignature')
 *
 *   cert.add_extension \
 *     extension_factory.create_extension('subjectKeyIdentifier', 'hash')
 *
 * The list of supported extensions (and in some cases their possible values)
 * can be derived from the "objects.h" file in the OpenSSL source code.
 *
 * === Signing a Certificate
 *
 * To sign a certificate set the issuer and use OpenSSL::X509::Certificate#sign
 * with a digest algorithm.  This creates a self-signed cert because we're using
 * the same name and key to sign the certificate as was used to create the
 * certificate.
 *
 *   cert.issuer = name
 *   cert.sign key, OpenSSL::Digest::SHA1.new
 *
 *   open 'certificate.pem', 'w' do |io| io.write cert.to_pem end
 *
 * === Loading a Certificate
 *
 * Like a key, a cert can also be loaded from a file.
 *
 *   cert2 = OpenSSL::X509::Certificate.new File.read 'certificate.pem'
 *
 * === Verifying a Certificate
 *
 * Certificate#verify will return true when a certificate was signed with the
 * given public key.
 *
 *   raise 'certificate can not be verified' unless cert2.verify key
 *
 * == Certificate Authority
 *
 * A certificate authority (CA) is a trusted third party that allows you to
 * verify the ownership of unknown certificates.  The CA issues key signatures
 * that indicate it trusts the user of that key.  A user encountering the key
 * can verify the signature by using the CA's public key.
 *
 * === CA Key
 *
 * CA keys are valuable, so we encrypt and save it to disk and make sure it is
 * not readable by other users.
 *
 *   ca_key = OpenSSL::PKey::RSA.new 2048
 *   pass_phrase = 'my secure pass phrase goes here'
 *
 *   cipher = OpenSSL::Cipher.new 'AES-128-CBC'
 *
 *   open 'ca_key.pem', 'w', 0400 do |io|
 *     io.write ca_key.export(cipher, pass_phrase)
 *   end
 *
 * === CA Certificate
 *
 * A CA certificate is created the same way we created a certificate above, but
 * with different extensions.
 *
 *   ca_name = OpenSSL::X509::Name.parse 'CN=ca/DC=example'
 *
 *   ca_cert = OpenSSL::X509::Certificate.new
 *   ca_cert.serial = 0
 *   ca_cert.version = 2
 *   ca_cert.not_before = Time.now
 *   ca_cert.not_after = Time.now + 86400
 *
 *   ca_cert.public_key = ca_key.public_key
 *   ca_cert.subject = ca_name
 *   ca_cert.issuer = ca_name
 *
 *   extension_factory = OpenSSL::X509::ExtensionFactory.new
 *   extension_factory.subject_certificate = ca_cert
 *   extension_factory.issuer_certificate = ca_cert
 *
 *   ca_cert.add_extension \
 *     extension_factory.create_extension('subjectKeyIdentifier', 'hash')
 *
 * This extension indicates the CA's key may be used as a CA.
 *
 *   ca_cert.add_extension \
 *     extension_factory.create_extension('basicConstraints', 'CA:TRUE', true)
 *
 * This extension indicates the CA's key may be used to verify signatures on
 * both certificates and certificate revocations.
 *
 *   ca_cert.add_extension \
 *     extension_factory.create_extension(
 *       'keyUsage', 'cRLSign,keyCertSign', true)
 *
 * Root CA certificates are self-signed.
 *
 *   ca_cert.sign ca_key, OpenSSL::Digest::SHA1.new
 *
 * The CA certificate is saved to disk so it may be distributed to all the
 * users of the keys this CA will sign.
 *
 *   open 'ca_cert.pem', 'w' do |io|
 *     io.write ca_cert.to_pem
 *   end
 *
 * === Certificate Signing Request
 *
 * The CA signs keys through a Certificate Signing Request (CSR).  The CSR
 * contains the information necessary to identify the key.
 *
 *   csr = OpenSSL::X509::Request.new
 *   csr.version = 0
 *   csr.subject = name
 *   csr.public_key = key.public_key
 *   csr.sign key, OpenSSL::Digest::SHA1.new
 *
 * A CSR is saved to disk and sent to the CA for signing.
 *
 *   open 'csr.pem', 'w' do |io|
 *     io.write csr.to_pem
 *   end
 *
 * === Creating a Certificate from a CSR
 *
 * Upon receiving a CSR the CA will verify it before signing it.  A minimal
 * verification would be to check the CSR's signature.
 *
 *   csr = OpenSSL::X509::Request.new File.read 'csr.pem'
 *
 *   raise 'CSR can not be verified' unless csr.verify csr.public_key
 *
 * After verification a certificate is created, marked for various usages,
 * signed with the CA key and returned to the requester.
 *
 *   csr_cert = OpenSSL::X509::Certificate.new
 *   csr_cert.serial = 0
 *   csr_cert.version = 2
 *   csr_cert.not_before = Time.now
 *   csr_cert.not_after = Time.now + 600
 *
 *   csr_cert.subject = csr.subject
 *   csr_cert.public_key = csr.public_key
 *   csr_cert.issuer = ca_cert.subject
 *
 *   extension_factory = OpenSSL::X509::ExtensionFactory.new
 *   extension_factory.subject_certificate = csr_cert
 *   extension_factory.issuer_certificate = ca_cert
 *
 *   csr_cert.add_extension \
 *     extension_factory.create_extension('basicConstraints', 'CA:FALSE')
 *
 *   csr_cert.add_extension \
 *     extension_factory.create_extension(
 *       'keyUsage', 'keyEncipherment,dataEncipherment,digitalSignature')
 *
 *   csr_cert.add_extension \
 *     extension_factory.create_extension('subjectKeyIdentifier', 'hash')
 *
 *   csr_cert.sign ca_key, OpenSSL::Digest::SHA1.new
 *
 *   open 'csr_cert.pem', 'w' do |io|
 *     io.write csr_cert.to_pem
 *   end
 *
 * == SSL and TLS Connections
 *
 * Using our created key and certificate we can create an SSL or TLS connection.
 * An SSLContext is used to set up an SSL session.
 *
 *   context = OpenSSL::SSL::SSLContext.new
 *
 * === SSL Server
 *
 * An SSL server requires the certificate and private key to communicate
 * securely with its clients:
 *
 *   context.cert = cert
 *   context.key = key
 *
 * Then create an SSLServer with a TCP server socket and the context.  Use the
 * SSLServer like an ordinary TCP server.
 *
 *   require 'socket'
 *
 *   tcp_server = TCPServer.new 5000
 *   ssl_server = OpenSSL::SSL::SSLServer.new tcp_server, context
 *
 *   loop do
 *     ssl_connection = ssl_server.accept
 *
 *     data = connection.gets
 *
 *     response = "I got #{data.dump}"
 *     puts response
 *
 *     connection.puts "I got #{data.dump}"
 *     connection.close
 *   end
 *
 * === SSL client
 *
 * An SSL client is created with a TCP socket and the context.
 * SSLSocket#connect must be called to initiate the SSL handshake and start
 * encryption.  A key and certificate are not required for the client socket.
 *
 * Note that SSLSocket#close doesn't close the underlying socket by default. Set
 * SSLSocket#sync_close to true if you want.
 *
 *   require 'socket'
 *
 *   tcp_socket = TCPSocket.new 'localhost', 5000
 *   ssl_client = OpenSSL::SSL::SSLSocket.new tcp_socket, context
 *   ssl_client.sync_close = true
 *   ssl_client.connect
 *
 *   ssl_client.puts "hello server!"
 *   puts ssl_client.gets
 *
 *   ssl_client.close # shutdown the TLS connection and close tcp_socket
 *
 * === Peer Verification
 *
 * An unverified SSL connection does not provide much security.  For enhanced
 * security the client or server can verify the certificate of its peer.
 *
 * The client can be modified to verify the server's certificate against the
 * certificate authority's certificate:
 *
 *   context.ca_file = 'ca_cert.pem'
 *   context.verify_mode = OpenSSL::SSL::VERIFY_PEER
 *
 *   require 'socket'
 *
 *   tcp_socket = TCPSocket.new 'localhost', 5000
 *   ssl_client = OpenSSL::SSL::SSLSocket.new tcp_socket, context
 *   ssl_client.connect
 *
 *   ssl_client.puts "hello server!"
 *   puts ssl_client.gets
 *
 * If the server certificate is invalid or <tt>context.ca_file</tt> is not set
 * when verifying peers an OpenSSL::SSL::SSLError will be raised.
 *
 */
void
Init_openssl(void)
{
#undef rb_intern
    /*
     * Init timezone info
     */
#if 0
    tzset();
#endif

    /*
     * Init all digests, ciphers
     */
#if !defined(LIBRESSL_VERSION_NUMBER) && OPENSSL_VERSION_NUMBER >= 0x10100000
    if (!OPENSSL_init_ssl(0, NULL))
        rb_raise(rb_eRuntimeError, "OPENSSL_init_ssl");
#else
    OpenSSL_add_ssl_algorithms();
    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();
    SSL_load_error_strings();
#endif

    /*
     * Init main module
     */
    mOSSL = rb_define_module("OpenSSL");
    rb_global_variable(&mOSSL);

    /*
     * OpenSSL ruby extension version
     */
    rb_define_const(mOSSL, "VERSION", rb_str_new2(OSSL_VERSION));

    /*
     * Version of OpenSSL the ruby OpenSSL extension was built with
     */
    rb_define_const(mOSSL, "OPENSSL_VERSION", rb_str_new2(OPENSSL_VERSION_TEXT));

    /*
     * Version of OpenSSL the ruby OpenSSL extension is running with
     */
#if !defined(LIBRESSL_VERSION_NUMBER) && OPENSSL_VERSION_NUMBER >= 0x10100000
    rb_define_const(mOSSL, "OPENSSL_LIBRARY_VERSION", rb_str_new2(OpenSSL_version(OPENSSL_VERSION)));
#else
    rb_define_const(mOSSL, "OPENSSL_LIBRARY_VERSION", rb_str_new2(SSLeay_version(SSLEAY_VERSION)));
#endif

    /*
     * Version number of OpenSSL the ruby OpenSSL extension was built with
     * (base 16)
     */
    rb_define_const(mOSSL, "OPENSSL_VERSION_NUMBER", INT2NUM(OPENSSL_VERSION_NUMBER));

    /*
     * Boolean indicating whether OpenSSL is FIPS-capable or not
     */
    rb_define_const(mOSSL, "OPENSSL_FIPS",
#ifdef OPENSSL_FIPS
		    Qtrue
#else
		    Qfalse
#endif
		   );

    rb_define_module_function(mOSSL, "fips_mode", ossl_fips_mode_get, 0);
    rb_define_module_function(mOSSL, "fips_mode=", ossl_fips_mode_set, 1);

    /*
     * Generic error,
     * common for all classes under OpenSSL module
     */
    eOSSLError = rb_define_class_under(mOSSL,"OpenSSLError",rb_eStandardError);
    rb_global_variable(&eOSSLError);

    /*
     * Init debug core
     */
    dOSSL = Qfalse;
    rb_global_variable(&dOSSL);

    rb_define_module_function(mOSSL, "debug", ossl_debug_get, 0);
    rb_define_module_function(mOSSL, "debug=", ossl_debug_set, 1);
    rb_define_module_function(mOSSL, "errors", ossl_get_errors, 0);

    /*
     * Get ID of to_der
     */
    ossl_s_to_der = rb_intern("to_der");

#if !defined(HAVE_OPENSSL_110_THREADING_API)
    Init_ossl_locks();
#endif

    /*
     * Init components
     */
    Init_ossl_bn();
    Init_ossl_cipher();
    Init_ossl_config();
    Init_ossl_digest();
    Init_ossl_hmac();
    Init_ossl_ns_spki();
    Init_ossl_pkcs12();
    Init_ossl_pkcs7();
    Init_ossl_pkey();
    Init_ossl_rand();
    Init_ossl_ssl();
    Init_ossl_x509();
    Init_ossl_ocsp();
    Init_ossl_engine();
    Init_ossl_asn1();
    Init_ossl_kdf();

#if defined(OSSL_DEBUG)
    /*
     * For debugging Ruby/OpenSSL. Enable only when built with --enable-debug
     */
#if !defined(LIBRESSL_VERSION_NUMBER) && \
    (OPENSSL_VERSION_NUMBER >= 0x10100000 && !defined(OPENSSL_NO_CRYPTO_MDEBUG) || \
     defined(CRYPTO_malloc_debug_init))
    rb_define_module_function(mOSSL, "mem_check_start", mem_check_start, 0);
    rb_define_module_function(mOSSL, "print_mem_leaks", print_mem_leaks, 0);

#if defined(CRYPTO_malloc_debug_init) /* <= 1.0.2 */
    CRYPTO_malloc_debug_init();
#endif

#if defined(V_CRYPTO_MDEBUG_ALL) /* <= 1.0.2 */
    CRYPTO_set_mem_debug_options(V_CRYPTO_MDEBUG_ALL);
#endif

#if OPENSSL_VERSION_NUMBER < 0x10100000 /* <= 1.0.2 */
    {
	int i;
	/*
	 * See crypto/ex_data.c; call def_get_class() immediately to avoid
	 * allocations. 15 is the maximum number that is used as the class index
	 * in OpenSSL 1.0.2.
	 */
	for (i = 0; i <= 15; i++) {
	    if (CRYPTO_get_ex_new_index(i, 0, (void *)"ossl-mdebug-dummy", 0, 0, 0) < 0)
		rb_raise(rb_eRuntimeError, "CRYPTO_get_ex_new_index for "
			 "class index %d failed", i);
	}
    }
#endif
#endif
#endif
}
