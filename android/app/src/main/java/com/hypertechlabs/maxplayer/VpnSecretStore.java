package com.hypertechlabs.maxplayer;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** VPN-only secrets. Ciphertext is excluded from Android backup (noBackupFilesDir).
 * The non-exportable AES key stays in AndroidKeyStore; there is no plaintext fallback. */
public final class VpnSecretStore {
  private static final String ALIAS = "maxplayer_vpn_aes_v1";
  private static synchronized SecretKey key() throws Exception {
    KeyStore ks = KeyStore.getInstance("AndroidKeyStore"); ks.load(null);
    if (ks.containsAlias(ALIAS)) return (SecretKey) ks.getKey(ALIAS, null);
    KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
    generator.init(new KeyGenParameterSpec.Builder(ALIAS,
        KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
    return generator.generateKey();
  }
  private static java.io.File file(Context c, String name) throws Exception {
    if (!name.matches("[a-zA-Z0-9._-]{1,100}")) throw new Exception("Invalid secret identifier");
    java.io.File dir = new java.io.File(c.getNoBackupFilesDir(), "vpn");
    if (!dir.isDirectory() && !dir.mkdirs()) throw new Exception("Secret storage unavailable");
    return new java.io.File(dir, name);
  }
  public static synchronized String read(Context c, String name) throws Exception {
    java.io.File f = file(c, name);
    if (!f.isFile()) return null;
    if (f.length() > 1024 * 1024) throw new Exception("Secret too large");
    String encoded;
    try (java.io.FileInputStream in = new java.io.FileInputStream(f)) {
      java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
      byte[] buffer = new byte[4096]; int n;
      while ((n = in.read(buffer)) != -1) bytes.write(buffer, 0, n);
      encoded = bytes.toString("UTF-8");
    }
    String[] parts = encoded.split(":", 2);
    if (parts.length != 2) throw new Exception("Invalid encrypted secret");
    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
    cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)));
    cipher.updateAAD(name.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    return new String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), java.nio.charset.StandardCharsets.UTF_8);
  }
  public static synchronized void write(Context c, String name, String value) throws Exception {
    java.io.File f = file(c, name);
    if (value == null) { if (f.exists() && !f.delete()) throw new Exception("Secret deletion failed"); return; }
    if (value.length() > 512 * 1024) throw new Exception("Secret too large");
    Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
    cipher.updateAAD(name.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    String encoded = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP) + ":" +
      Base64.encodeToString(cipher.doFinal(value.getBytes(java.nio.charset.StandardCharsets.UTF_8)), Base64.NO_WRAP);
    android.util.AtomicFile atomic = new android.util.AtomicFile(f);
    java.io.FileOutputStream out = null;
    try {
      out = atomic.startWrite(); out.write(encoded.getBytes(java.nio.charset.StandardCharsets.UTF_8)); atomic.finishWrite(out);
    } catch (Exception e) { if (out != null) atomic.failWrite(out); throw e; }
  }
}
