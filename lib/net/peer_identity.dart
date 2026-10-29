import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';

/// Ephemeral TLS identity used to encrypt peer traffic and pin the certificate
/// advertised by LAN discovery. The private key stays in memory for this run.
class PeerIdentity {
  PeerIdentity._(this.context, this.fingerprint);

  final SecurityContext context;
  final String fingerprint;

  static Future<PeerIdentity> create() async {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'PONG! LAN peer'},
      privateKey,
      publicKey,
    );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      2,
    );
    final context = SecurityContext()
      ..usePrivateKeyBytes(
        utf8.encode(
          CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
        ),
      )
      ..useCertificateChainBytes(utf8.encode(certificate));
    final pemBody = certificate.replaceAll(
      RegExp(r'-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s'),
      '',
    );
    final der = base64.decode(pemBody);
    return PeerIdentity._(context, CryptoUtils.getHash(der).toLowerCase());
  }
}
