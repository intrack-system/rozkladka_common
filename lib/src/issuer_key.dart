import 'dart:convert';

/// Відкритий ключ InTrack (SPKI DER), яким перевіряються QR-коди активації.
/// Застосунок належить тому InTrack, чий ключ вшито у збірку.
// ponytail: зараз — ключ стенду (~/InTrack/certs/apps/activation-key.pem,
// SHA-256 SPKI 2189cac3c919ff41…). Перед робочою збіркою замінити на ключ
// робочого InTrack за процедурою першого ключа (InTrack).
final List<int> issuerPublicKey = base64.decode(
  'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEbYKBYrSZnxbOKa6gQmmtVXS0qnx395AapAa0'
  '25zrY6D9VjTxdXS+DPdGOdx+Twd+fTVoKRLCs4KrXgJPHSTJfg==',
);
