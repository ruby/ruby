/*
 * $Id$
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licenced under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"
#include <stdarg.h> /* for ossl_raise */

/*
 * String to HEXString conversion
 */
int
string2hex(const unsigned char *buf, int buf_len, char **hexbuf, int *hexbuf_len)
{
    static const char hex[]="0123456789abcdef";
    int i, len = 2 * buf_len;

    if (buf_len < 0 || len < buf_len) { /* PARANOIA? */
	return -1;
    }
    if (!hexbuf) { /* if no buf, return calculated len */
	if (hexbuf_len) {
	    *hexbuf_len = len;
	}
	return len;
    }
    if (!(*hexbuf = OPENSSL_malloc(len + 1))) {
	return -1;
    }
    for (i = 0; i < buf_len; i++) {
	(*hexbuf)[2 * i] = hex[((unsigned char)buf[i]) >> 4];
	(*hexbuf)[2 * i + 1] = hex[buf[i] & 0x0f];
    }
    (*hexbuf)[2 * i] = '\0';

    if (hexbuf_len) {
	*hexbuf_len = len;
    }
    return len;
}

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
	    (VALUE(*)_((VALUE)))ossl_##name##_ary2sk0,		\
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
ossl_##name##_sk2ary(STACK_OF(type) *sk)	\
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
ossl_str_new(int size)
{
    return rb_str_new(0, size);
}

VALUE
ossl_buf2str(char *buf, int len)
{
    VALUE str;
    int status = 0;

    str = rb_protect((VALUE(*)_((VALUE)))ossl_str_new, len, &status);
    if(!NIL_P(str)) memcpy(RSTRING_PTR(str), buf, len);
    OPENSSL_free(buf);
    if(status) rb_jump_tag(status);

    return str;
}

/*
 * our default PEM callback
 */
static VALUE
ossl_pem_passwd_cb0(VALUE flag)
{
    VALUE pass;

    pass = rb_yield(flag);
    SafeStringValue(pass);

    return pass;
}

int
ossl_pem_passwd_cb(char *buf, int max_len, int flag, void *pwd)
{
    int len, status = 0;
    VALUE rflag, pass;

    if (pwd || !rb_block_given_p())
	return PEM_def_callback(buf, max_len, flag, pwd);

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
	len = RSTRING_LENINT(pass);
	if (len < 4) { /* 4 is OpenSSL hardcoded limit */
	    rb_warning("password must be longer than 4 bytes");
	    continue;
	}
	if (len > max_len) {
	    rb_warning("password must be shorter then %d bytes", max_len-1);
	    continue;
	}
	memcpy(buf, RSTRING_PTR(pass), len);
	break;
    }
    return len;
}

/*
 * Verify callback
 */
int ossl_verify_cb_idx;

VALUE
ossl_call_verify_cb_proc(struct ossl_verify_cb_args *args)
{
    return rb_funcall(args->proc, rb_intern("call"), 2,
                      args->preverify_ok, args->store_ctx);
}

int
ossl_verify_cb(int ok, X509_STORE_CTX *ctx)
{
    VALUE proc, rctx, ret;
    struct ossl_verify_cb_args args;
    int state = 0;

    proc = (VALUE)X509_STORE_CTX_get_ex_data(ctx, ossl_verify_cb_idx);
    if ((void*)proc == 0)
	proc = (VALUE)X509_STORE_get_ex_data(ctx->ctx, ossl_verify_cb_idx);
    if ((void*)proc == 0)
	return ok;
    if (!NIL_P(proc)) {
	ret = Qfalse;
	rctx = rb_protect((VALUE(*)(VALUE))ossl_x509stctx_new,
			  (VALUE)ctx, &state);
	if (state) {
	    rb_set_errinfo(Qnil);
	    rb_warn("StoreContext initialization failure");
	}
	else {
	    args.proc = proc;
	    args.preverify_ok = ok ? Qtrue : Qfalse;
	    args.store_ctx = rctx;
	    ret = rb_protect((VALUE(*)(VALUE))ossl_call_verify_cb_proc, (VALUE)&args, &state);
	    if (state) {
		rb_set_errinfo(Qnil);
		rb_warn("exception in verify_callback is ignored");
	    }
	    ossl_x509stctx_clear_ptr(rctx);
	}
	if (ret == Qtrue) {
	    X509_STORE_CTX_set_error(ctx, X509_V_OK);
	    ok = 1;
	}
	else{
	    if (X509_STORE_CTX_get_error(ctx) == X509_V_OK) {
		X509_STORE_CTX_set_error(ctx, X509_V_ERR_CERT_REJECTED);
	    }
	    ok = 0;
	}
    }

    return ok;
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
ID ossl_s_to_der;

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
    const char *msg;
    long e;

#ifdef HAVE_ERR_PEEK_LAST_ERROR
    e = ERR_peek_last_error();
#else
    e = ERR_peek_error();
#endif
    if (fmt) {
	str = rb_vsprintf(fmt, args);
    }
    if (e) {
	if (dOSSL == Qtrue) /* FULL INFO */
	    msg = ERR_error_string(e, NULL);
	else
	    msg = ERR_reason_error_string(e);
	if (NIL_P(str)) {
	    str = rb_str_new_cstr(msg);
	}
	else {
	    rb_str_cat2(rb_str_cat2(str, ": "), msg);
	}
    }
    if (dOSSL == Qtrue){ /* show all errors on the stack */
	while ((e = ERR_get_error()) != 0){
	    rb_warn("error on stack: %s", ERR_error_string(e, NULL));
	}
    }
    ERR_clear_error();

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

VALUE
ossl_exc_new(VALUE exc, const char *fmt, ...)
{
    va_list args;
    VALUE err;
    va_start(args, fmt);
    err = ossl_make_error(exc, fmt, args);
    va_end(args);
    return err;
}

/*
 * call-seq:
 *   OpenSSL.errors -> [String...]
 *
 * See any remaining errors held in queue.
 *
 * Any errors you see here are probably due to a bug in ruby's OpenSSL implementation.
 */
VALUE
ossl_get_errors()
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
 * Turns on or off CRYPTO_MEM_CHECK.
 * Also shows some debugging message on stderr.
 */
static VALUE
ossl_debug_set(VALUE self, VALUE val)
{
    VALUE old = dOSSL;
    dOSSL = val;

    if (old != dOSSL) {
	if (dOSSL == Qtrue) {
	    CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON);
	    fprintf(stderr, "OSSL_DEBUG: IS NOW ON!\n");
	} else if (old == Qtrue) {
	    CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_OFF);
	    fprintf(stderr, "OSSL_DEBUG: IS NOW OFF!\n");
	}
    }
    return val;
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
 *
 * OpenSSL.fips_mode = true   # turn FIPS mode on
 * OpenSSL.fips_mode = false  # and off again
 */
static VALUE
ossl_fips_mode_set(VALUE self, VALUE enabled)
{

#ifdef HAVE_OPENSSL_FIPS
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

/**
 * Stores locks needed for OpenSSL thread safety
 */
#include "../../thread_native.h"
static rb_nativethread_lock_t *ossl_locks;

static void
ossl_lock_unlock(int mode, rb_nativethread_lock_t *lock)
{
    if (mode & CRYPTO_LOCK) {
	rb_nativethread_lock_lock(lock);
    } else {
	rb_nativethread_lock_unlock(lock);
    }
}

static void
ossl_lock_callback(int mode, int type, const char *file, int line)
{
    ossl_lock_unlock(mode, &ossl_locks[type]);
}

struct CRYPTO_dynlock_value {
    rb_nativethread_lock_t lock;
};

static struct CRYPTO_dynlock_value *
ossl_dyn_create_callback(const char *file, int line)
{
    struct CRYPTO_dynlock_value *dynlock = (struct CRYPTO_dynlock_value *)OPENSSL_malloc((int)sizeof(struct CRYPTO_dynlock_value));
    rb_nativethread_lock_initialize(&dynlock->lock);
    return dynlock;
}

static void
ossl_dyn_lock_callback(int mode, struct CRYPTO_dynlock_value *l, const char *file, int line)
{
    ossl_lock_unlock(mode, &l->lock);
}

static void
ossl_dyn_destroy_callback(struct CRYPTO_dynlock_value *l, const char *file, int line)
{
    rb_nativethread_lock_destroy(&l->lock);
    OPENSSL_free(l);
}

#ifdef HAVE_CRYPTO_THREADID_PTR
static void ossl_threadid_func(CRYPTO_THREADID *id)
{
    /* register native thread id */
    CRYPTO_THREADID_set_pointer(id, (void *)rb_nativethread_self());
}
#else
static unsigned long ossl_thread_id(void)
{
    /* before OpenSSL 1.0, this is 'unsigned long' */
    return (unsigned long)rb_nativethread_self();
}
#endif

static void Init_ossl_locks(void)
{
    int i;
    int num_locks = CRYPTO_num_locks();

    if ((unsigned)num_locks >= INT_MAX / (int)sizeof(VALUE)) {
	rb_raise(rb_eRuntimeError, "CRYPTO_num_locks() is too big: %d", num_locks);
    }
    ossl_locks = (rb_nativethread_lock_t *) OPENSSL_malloc(num_locks * (int)sizeof(rb_nativethread_lock_t));
    if (!ossl_locks) {
	rb_raise(rb_eNoMemError, "CRYPTO_num_locks() is too big: %d", num_locks);
    }
    for (i = 0; i < num_locks; i++) {
	rb_nativethread_lock_initialize(&ossl_locks[i]);
    }

#ifdef HAVE_CRYPTO_THREADID_PTR
    CRYPTO_THREADID_set_callback(ossl_threadid_func);
#else
    CRYPTO_set_id_callback(ossl_thread_id);
#endif
    CRYPTO_set_locking_callback(ossl_lock_callback);
    CRYPTO_set_dynlock_create_callback(ossl_dyn_create_callback);
    CRYPTO_set_dynlock_lock_callback(ossl_dyn_lock_callback);
    CRYPTO_set_dynlock_destroy_callback(ossl_dyn_destroy_callback);
}

/*
 * OpenSSL provides SSL, TLS and general purpose cryptography.  It wraps the
 * OpenSSL[http://www.openssl.org/] library.
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
 *
 * or
 *
 *   key3 = OpenSSL::PKey::RSA.new File.read 'public_key.pem'
 *   key3.private? # => false
 *
 * === Loading an Encrypted Key
 *
 * OpenSSL will prompt you for your pass phrase when loading an encrypted key.
 * If you will not be able to type in the pass phrase you may provide it when
 * loading the key:
 *
 *   key4_pem = File.read 'private.secure.pem'
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
 *   encrypter = OpenSSL::Cipher.new 'AES-128-CBC'
 *   encrypter.encrypt
 *   encrypter.pkcs5_keyivgen pass_phrase, salt
 *
 * Then pass the data you want to encrypt through
 *
 *   encrypted = encrypter.update 'top secret document'
 *   encrypted << encrypter.final
 *
 * === Decryption
 *
 * Use a new Cipher instance set up for decryption
 *
 *   decrypter = OpenSSL::Cipher.new 'AES-128-CBC'
 *   decrypter.decrypt
 *   decrypter.pkcs5_keyivgen pass_phrase, salt
 *
 * Then pass the data you want to decrypt through
 *
 *   plain = decrypter.update encrypted
 *   plain << decrypter.final
 *
 * == X509 Certificates
 *
 * === Creating a Certificate
 *
 * This example creates a self-signed certificate using an RSA key and a SHA1
 * signature.
 *
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
 *
 *   cipher = OpenSSL::Cipher::Cipher.new 'AES-128-CBC'
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
 *   require 'socket'
 *
 *   tcp_client = TCPSocket.new 'localhost', 5000
 *   ssl_client = OpenSSL::SSL::SSLSocket.new client_socket, context
 *   ssl_client.connect
 *
 *   ssl_client.puts "hello server!"
 *   puts ssl_client.gets
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
 *   tcp_client = TCPSocket.new 'localhost', 5000
 *   ssl_client = OpenSSL::SSL::SSLSocket.new client_socket, context
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
Init_openssl()
{
    /*
     * Init timezone info
     */
#if 0
    tzset();
#endif

    /*
     * Init all digests, ciphers
     */
    /* CRYPTO_malloc_init(); */
    /* ENGINE_load_builtin_engines(); */
    OpenSSL_add_ssl_algorithms();
    OpenSSL_add_all_algorithms();
    ERR_load_crypto_strings();
    SSL_load_error_strings();

    /*
     * FIXME:
     * On unload do:
     */
#if 0
    CONF_modules_unload(1);
    destroy_ui_method();
    EVP_cleanup();
    ENGINE_cleanup();
    CRYPTO_cleanup_all_ex_data();
    ERR_remove_state(0);
    ERR_free_strings();
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
     * Version number of OpenSSL the ruby OpenSSL extension was built with
     * (base 16)
     */
    rb_define_const(mOSSL, "OPENSSL_VERSION_NUMBER", INT2NUM(OPENSSL_VERSION_NUMBER));

    /*
     * Boolean indicating whether OpenSSL is FIPS-enabled or not
     */
#ifdef HAVE_OPENSSL_FIPS
    rb_define_const(mOSSL, "OPENSSL_FIPS", Qtrue);
#else
    rb_define_const(mOSSL, "OPENSSL_FIPS", Qfalse);
#endif
    rb_define_module_function(mOSSL, "fips_mode=", ossl_fips_mode_set, 1);

    /*
     * Generic error,
     * common for all classes under OpenSSL module
     */
    eOSSLError = rb_define_class_under(mOSSL,"OpenSSLError",rb_eStandardError);
    rb_global_variable(&eOSSLError);

    /*
     * Verify callback Proc index for ext-data
     */
    if ((ossl_verify_cb_idx = X509_STORE_CTX_get_ex_new_index(0, (void *)"ossl_verify_cb_idx", 0, 0, 0)) < 0)
        ossl_raise(eOSSLError, "X509_STORE_CTX_get_ex_new_index");

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

    Init_ossl_locks();

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
    Init_ossl_pkcs5();
    Init_ossl_pkey();
    Init_ossl_rand();
    Init_ossl_ssl();
    Init_ossl_x509();
    Init_ossl_ocsp();
    Init_ossl_engine();
    Init_ossl_asn1();
}

#if defined(OSSL_DEBUG)
/*
 * Check if all symbols are OK with 'make LDSHARED=gcc all'
 */
int
main(int argc, char *argv[])
{
    return 0;
}
#endif /* OSSL_DEBUG */

