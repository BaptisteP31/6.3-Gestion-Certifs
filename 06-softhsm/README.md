# 06-softhsm - HSM root CA with SoftHSM2

This folder builds a root CA whose private key never leaves SoftHSM2.

## Files

- `softhsm2.conf`: local SoftHSM2 config for this TP.
- `openssl-hsm-root.cnf`: OpenSSL config for the root CA.
- `scripts/bootstrap-hsm-root-ca.sh`: initializes the token, creates the RSA 4096 key, self-signs the root cert, and generates the CRL.
- `scripts/sign-adcs-csr.sh`: signs a Windows ADCS CSR with the HSM-backed root CA key.

## Environment

```sh
export SOFTHSM2_CONF="$PWD/softhsm2.conf"
export OPENSSL_MODULES=/usr/lib/ossl-modules
export PKCS11_MODULE_PATH=/usr/lib/softhsm/libsofthsm2.so
```

## Bootstrap the root CA

```sh
./scripts/bootstrap-hsm-root-ca.sh
```

What this does:

1. Initializes a dedicated SoftHSM2 token.
2. Generates a 4096-bit RSA key pair directly inside SoftHSM2.
3. Verifies the key with `pkcs11-tool`.
4. Creates a self-signed root certificate with the private key accessed through PKCS#11.
5. Generates a CRL valid for 30 days.

## Expected artifacts

- `state/certs/HSM_Root_CA_TRI.crt`
- `state/crl/HSM_Root_CA_TRI.crl`
- `state/index.txt`
- `state/serial`
- `state/crlnumber`

The private key is never exported as a `.key` file and no private key `.pem` is written to disk outside SoftHSM2.

## Verify the key exists in the token

```sh
pkcs11-tool --module /usr/lib/softhsm/libsofthsm2.so --login --pin 12345678 -O
```

Look for:

```text
Private Key Object; RSA 4096 bits
label:      HSM_Root_CA_TRI
```

## Self-signed root certificate

The root CA subject is:

```text
C=FR, O=TP Crypto, OU=06-softhsm, CN=HSM_Root_CA_TRI
```

Validity is 10 years (`3650` days).

## CRL

The CRL is issued by the same HSM-backed CA and is valid for 30 days.

## Prove no private key file was written

```sh
./scripts/verify-no-private-files.sh
```

This fails if any `.key` or private `.pem` file appears under `06-softhsm`.

## Sign a Windows ADCS CSR

### 1. Convert the CSR if needed

If Windows exported a DER CSR:

```sh
openssl req -inform DER -in adcs.csr -out adcs.pem
```

If it is already PEM, keep it as-is.

### 2. Inspect the request

```sh
openssl req -in adcs.pem -noout -text
```

### 3. Sign it with the HSM-backed root CA

Use the helper script:

```sh
./scripts/sign-adcs-csr.sh adcs.pem issued/adcs-signed.crt
```

For a leaf certificate CSR, adjust the extension profile in `openssl-hsm-root.cnf` and in the script if needed.

## OpenSSL 3 note

The working path here is the OpenSSL 3 provider `pkcs11prov` with `PKCS11_MODULE_PATH=/usr/lib/softhsm/libsofthsm2.so`.

One failure mode tested on this machine was:

```text
pkey: unable to load provider pkcs11
Hint: use -provider-path option or OPENSSL_MODULES environment variable.
... could not load the shared library ... /usr/lib/ossl-modules/pkcs11.so: No such file or directory
```

Correction:

- Use `-provider pkcs11prov`, not `-provider pkcs11`.
- Set `OPENSSL_MODULES=/usr/lib/ossl-modules`.
- Set `PKCS11_MODULE_PATH=/usr/lib/softhsm/libsofthsm2.so`.

The legacy `-engine pkcs11` path is available on this host, but the provider path is the one used for the TP.
