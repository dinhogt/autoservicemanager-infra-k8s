#!/usr/bin/env node
/**
 * Converte PEM RSA privado → JWKS (JWK público) via crypto nativo (Node ≥16).
 * Usado por data.external no Terraform (apply/plan).
 */
import { createPrivateKey } from 'crypto';

let raw = '';
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  try {
    const query = JSON.parse(raw);
    const key = createPrivateKey(query.privateKeyPem);
    const jwk = key.export({ format: 'jwk' });
    const publicJwk = {
      kty: jwk.kty,
      n: jwk.n,
      e: jwk.e,
      kid: query.kid || 'auth-cpf-1',
      use: 'sig',
      alg: 'RS256',
    };
    // data.external exige map[string]string
    process.stdout.write(JSON.stringify({
      jwks: JSON.stringify({ keys: [publicJwk] }),
    }));
  } catch (err) {
    console.error(err.message || err);
    process.exit(1);
  }
});
