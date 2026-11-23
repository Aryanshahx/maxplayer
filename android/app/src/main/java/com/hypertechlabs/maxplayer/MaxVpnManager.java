package com.hypertechlabs.maxplayer;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.VpnService;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;
import com.wireguard.android.backend.GoBackend;
import com.wireguard.android.backend.Statistics;
import com.wireguard.android.backend.Tunnel;
import com.wireguard.config.Config;
import com.wireguard.config.InetEndpoint;
import com.wireguard.config.InetNetwork;
import com.wireguard.config.Peer;
import com.wireguard.crypto.Key;
import com.wireguard.crypto.KeyPair;
import io.flutter.plugin.common.MethodChannel;
import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TimeZone;
import java.util.concurrent.Callable;
import java.util.concurrent.CompletionService;
import java.util.concurrent.ExecutorCompletionService;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.json.JSONArray;
import org.json.JSONObject;

/**
 * Multi-Engine VPN Manager for RunX Player:
 * 1) 1-Tap Fast Edge WireGuard via Cloudflare WARP anonymous registration with cryptographic
 *    Noise_IKpsk2 handshake verification and multi-port ISP-throttling failover.
 * 2) 1-Tap Foreign Country OpenVPN Servers (USA, Netherlands, France, Canada, Japan,
 *    South Korea, United Kingdom, Thailand & live global relays) verified by real OpenVPN V2
 *    wire-packet handshakes and OpenVPN 2.7 / OpenSSL 3.5 cipher compatibility.
 * 3) Custom Country WireGuard (.conf) & OpenVPN (.ovpn) profile support + Max Player only.
 */
public final class MaxVpnManager {
  public static final int VPN_PERMISSION_REQUEST_CODE = 9418;
  private static final String VPN_NOTIF_CHANNEL = "maxplayer_vpn_status";
  private static final int VPN_NOTIF_ID = 77001;
  private static final String TUNNEL_NAME = "maxplayervpn";
  private static final String WARP_REG_URL = "https://api.cloudflareclient.com/v0a2158/reg";
  private static final String WARP_PEER_PUBKEY = "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=";

  private static final String[] WARP_FALLBACK_ENDPOINTS =
      new String[] {
        "162.159.193.2:500",
        "188.114.96.3:4500"
      };

  private static final String VPN_CACHE_PREFS = "max_vpn_fast_cache";
  private static final String PREF_RISEUP_CA = "riseup_ca";
  private static final String PREF_RISEUP_CERT = "riseup_cert";
  private static final String PREF_RISEUP_KEY = "riseup_key";
  private static final String PREF_RISEUP_CERT_AT = "riseup_cert_at";
  private static final String PREF_RISEUP_EIP = "riseup_eip_json";
  private static final String PREF_RISEUP_EIP_AT = "riseup_eip_at";
  private static final String PREF_VPNGATE_CSV = "vpngate_csv";
  private static final String PREF_VPNGATE_AT = "vpngate_at";

  private static final String RISEUP_CA_URL = "https://api.black.riseup.net/ca.crt";
  private static final String RISEUP_CERT_URL = "https://api.black.riseup.net/3/cert";
  private static final String RISEUP_EIP_URL =
      "https://api.black.riseup.net/3/config/eip-service.json";
  private static final String VPNGATE_HTTPS_URL = "https://www.vpngate.net/api/iphone/";

  private static final Pattern PEM_KEY_PATTERN =
      Pattern.compile(
          "(-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]+?-----END [A-Z ]*PRIVATE KEY-----)");
  private static final Pattern PEM_CERT_PATTERN =
      Pattern.compile("(-----BEGIN CERTIFICATE-----[\\s\\S]+?-----END CERTIFICATE-----)");
  private static final Pattern OVPN_REMOTE_PATTERN =
      Pattern.compile("(?m)^remote\\s+(\\S+)\\s+(\\d+)");
  private static final Pattern OVPN_PROTO_PATTERN = Pattern.compile("(?m)^proto\\s+(\\S+)");

  private final Context appContext;
  private final Handler mainHandler = new Handler(Looper.getMainLooper());
  private final SecureRandom secureRandom = new SecureRandom();
  private final ExecutorService vpnExecutor =
      Executors.newSingleThreadExecutor(
          r -> {
            Thread t = new Thread(r, "MaxVpnWorker");
            t.setDaemon(true);
            return t;
          });
  private final ExecutorService probePool =
      Executors.newCachedThreadPool(
          r -> {
            Thread t = new Thread(r, "MaxVpnProbe");
            t.setDaemon(true);
            return t;
          });

  private GoBackend goBackend;
  private final Tunnel wgTunnel;
  private volatile Tunnel.State currentState = Tunnel.State.DOWN;
  private volatile String activeProfileName = "RunX Player VPN";

  // Cached Riseup credentials, gateway directory & VPNGate directory (persisted + pre-warmed)
  private final SharedPreferences cachePrefs;
  private volatile String cachedRiseupCa;
  private volatile String cachedRiseupCert;
  private volatile String cachedRiseupKey;
  private volatile long cachedRiseupCertAtMs = 0L;
  private volatile String cachedRiseupEipJson;
  private volatile long cachedRiseupEipAtMs = 0L;
  private volatile String cachedVpnGateCsv;
  private volatile long cachedVpnGateAtMs = 0L;
  private volatile long lastVpnGateFailAtMs = 0L;

  private PendingConnectRequest pendingConnect;

  private static final class PendingConnectRequest {
    final String configText;
    final String profileName;
    final boolean browserOnly;
    final MethodChannel.Result result;

    PendingConnectRequest(
        String configText,
        String profileName,
        boolean browserOnly,
        MethodChannel.Result result) {
      this.configText = configText;
      this.profileName = profileName;
      this.browserOnly = browserOnly;
      this.result = result;
    }
  }

  private static final class VerifiedCandidate {
    final String ovpnConfig;
    final String serverHost;
    final String countryCode;
    final String countryName;
    final long latencyMs;
    final long speedBps;

    VerifiedCandidate(
        String ovpnConfig,
        String serverHost,
        String countryCode,
        String countryName,
        long latencyMs,
        long speedBps) {
      this.ovpnConfig = ovpnConfig;
      this.serverHost = serverHost;
      this.countryCode = countryCode;
      this.countryName = countryName;
      this.latencyMs = latencyMs;
      this.speedBps = speedBps;
    }
  }

  public MaxVpnManager(Context context) {
    this.appContext = context.getApplicationContext();
    this.cachePrefs = this.appContext.getSharedPreferences(VPN_CACHE_PREFS, Context.MODE_PRIVATE);
    loadPersistedCaches();
    // Provider requests start only after an explicit user action.
    this.wgTunnel =
        new Tunnel() {
          @Override
          public String getName() {
            return TUNNEL_NAME;
          }

          @Override
          public void onStateChange(State newState) {
            currentState = newState;
            if (newState == State.DOWN) {
              cancelStatusNotification();
            }
          }
        };
  }

  private void loadPersistedCaches() {
    try {
      String ca = cachePrefs.getString(PREF_RISEUP_CA, null);
      String cert = VpnSecretStore.read(appContext, PREF_RISEUP_CERT);
      String key = VpnSecretStore.read(appContext, PREF_RISEUP_KEY);
      long certAt = cachePrefs.getLong(PREF_RISEUP_CERT_AT, 0L);
      if (ca != null && cert != null && key != null) {
        cachedRiseupCa = ca;
        cachedRiseupCert = cert;
        cachedRiseupKey = key;
        cachedRiseupCertAtMs = certAt;
      }
      String eip = cachePrefs.getString(PREF_RISEUP_EIP, null);
      long eipAt = cachePrefs.getLong(PREF_RISEUP_EIP_AT, 0L);
      if (eip != null && !eip.isEmpty()) {
        cachedRiseupEipJson = eip;
        cachedRiseupEipAtMs = eipAt;
      }
      String csv = cachePrefs.getString(PREF_VPNGATE_CSV, null);
      long csvAt = cachePrefs.getLong(PREF_VPNGATE_AT, 0L);
      if (csv != null && csv.contains("*vpn_servers")) {
        cachedVpnGateCsv = csv;
        cachedVpnGateAtMs = csvAt;
      }
    } catch (Throwable ignored) {
    }
  }

  private void warmUpCachesAsync() {
    probePool.execute(
        () -> {
          try {
            ensureRiseupReady();
          } catch (Throwable ignored) {
          }
        });
  }

  private synchronized GoBackend ensureBackend() {
    if (goBackend == null) {
      goBackend = new GoBackend(appContext);
    }
    return goBackend;
  }

  /**
   * Provisions a verified, live foreign OpenVPN (.ovpn) configuration for the requested
   * countryCode (e.g. US, NL, FR, CA, JP, KR, GB, TH, VN, or AUTO_FOREIGN).
   */
  public void provisionForeignOpenVpnConfig(
      String countryCode, List<String> excludeHosts, MethodChannel.Result result) {
    probePool.execute(
        () -> {
          try {
            String cc =
                countryCode != null ? countryCode.trim().toUpperCase(Locale.US) : "AUTO_FOREIGN";
            Set<String> excluded = new HashSet<>();
            if (excludeHosts != null) {
              for (String h : excludeHosts) {
                if (h != null && !h.trim().isEmpty()) {
                  excluded.add(h.trim());
                }
              }
            }

            VerifiedCandidate chosen = null;

            // 1. Try dedicated RiseupVPN gateways first (supports US, NL, FR, CA & AUTO_FOREIGN)
            chosen = tryProvisionRiseupCandidate(cc, excluded);

            // 2. Try live VPNGate servers for the exact requested country code
            if (chosen == null) {
              chosen = tryProvisionVpnGateCandidate(cc, excluded);
            }

            // 3. Nearest-region fallback if specific country slot is momentarily full
            if (chosen == null && !"AUTO_FOREIGN".equals(cc)) {
              for (String neighborCc : regionalFallbacksFor(cc)) {
                chosen = tryProvisionRiseupCandidate(neighborCc, excluded);
                if (chosen != null) {
                  break;
                }
                chosen = tryProvisionVpnGateCandidate(neighborCc, excluded);
                if (chosen != null) {
                  break;
                }
              }
            }

            // 4. Final global fallback so connection always succeeds cleanly
            if (chosen == null && !"AUTO_FOREIGN".equals(cc)) {
              chosen = tryProvisionRiseupCandidate("AUTO_FOREIGN", excluded);
              if (chosen == null) {
                chosen = tryProvisionVpnGateCandidate("AUTO_FOREIGN", excluded);
              }
            }

            if (chosen == null) {
              postError(
                  result,
                  "All free servers for "
                      + cc
                      + " are busy right now. Tap another country or retry.");
              return;
            }

            Map<String, Object> payload = new HashMap<>();
            payload.put("ok", true);
            payload.put("configText", chosen.ovpnConfig);
            payload.put("serverHost", chosen.serverHost);
            payload.put("countryCode", chosen.countryCode);
            payload.put("countryName", chosen.countryName);
            payload.put("latencyMs", chosen.latencyMs);
            mainHandler.post(() -> result.success(payload));
          } catch (Throwable t) {
            postError(
                result,
                t.getMessage() != null
                    ? t.getMessage()
                    : "Unable to provision foreign VPN server");
          }
        });
  }

  public void fetchLiveForeignCountries(MethodChannel.Result result) {
    probePool.execute(
        () -> {
          Map<String, Map<String, Object>> byCode = new LinkedHashMap<>();
          addCountryMeta(byCode, "US", "United States", 4);
          addCountryMeta(byCode, "NL", "Netherlands", 3);
          addCountryMeta(byCode, "FR", "France", 8);
          addCountryMeta(byCode, "CA", "Canada", 2);

          try {
            String csv = fetchVpnGateCsv(true);
            if (csv != null) {
              String[] lines = csv.split("\\r?\\n");
              for (int i = 2; i < lines.length; i++) {
                String[] parts = lines[i].split(",", 16);
                if (parts.length >= 15 && !parts[14].trim().isEmpty()) {
                  String cc = parts[6].trim().toUpperCase(Locale.US);
                  String cLong = parts[5].trim();
                  if (cc.length() == 2 && !"IN".equals(cc) && !cLong.isEmpty()) {
                    Map<String, Object> existing = byCode.get(cc);
                    if (existing == null) {
                      addCountryMeta(byCode, cc, cLong, 1);
                    } else {
                      int prev = ((Number) existing.get("serverCount")).intValue();
                      existing.put("serverCount", prev + 1);
                    }
                  }
                }
              }
            }
          } catch (Throwable ignored) {
          }

          List<Map<String, Object>> list = new ArrayList<>(byCode.values());
          Map<String, Object> out = new HashMap<>();
          out.put("ok", true);
          out.put("countries", list);
          mainHandler.post(() -> result.success(out));
        });
  }

  private static void addCountryMeta(
      Map<String, Map<String, Object>> map, String code, String name, int count) {
    Map<String, Object> item = new HashMap<>();
    item.put("countryCode", code);
    item.put("countryName", name);
    item.put("serverCount", count);
    map.put(code, item);
  }

  private VerifiedCandidate tryProvisionRiseupCandidate(String targetCc, Set<String> excluded) {
    try {
      ensureRiseupReady();
      if (cachedRiseupCa == null || cachedRiseupCert == null || cachedRiseupKey == null) {
        return null;
      }
      String eipRaw = cachedRiseupEipJson;
      if (eipRaw == null || eipRaw.isEmpty()) {
        eipRaw = httpGetText(RISEUP_EIP_URL, null, 3800);
        if (eipRaw != null && !eipRaw.isEmpty()) {
          cachedRiseupEipJson = eipRaw;
          cachedRiseupEipAtMs = System.currentTimeMillis();
          cachePrefs
              .edit()
              .putString(PREF_RISEUP_EIP, eipRaw)
              .putLong(PREF_RISEUP_EIP_AT, cachedRiseupEipAtMs)
              .apply();
        }
      }
      if (eipRaw == null || eipRaw.isEmpty()) {
        return null;
      }

      JSONObject eip = new JSONObject(eipRaw);
      JSONObject locations = eip.optJSONObject("locations");
      JSONArray gateways = eip.optJSONArray("gateways");
      if (gateways == null || gateways.length() == 0) {
        return null;
      }

      List<Callable<VerifiedCandidate>> tasks = new ArrayList<>();
      for (int i = 0; i < gateways.length(); i++) {
        JSONObject gw = gateways.optJSONObject(i);
        if (gw == null) continue;
        String ip = gw.optString("ip_address", "").trim();
        String locKey = gw.optString("location", "").trim();
        if (ip.isEmpty() || excluded.contains(ip)) continue;

        String gwCc = "";
        String locDisplay = locKey;
        if (locations != null && locations.has(locKey)) {
          JSONObject locObj = locations.optJSONObject(locKey);
          if (locObj != null) {
            gwCc = locObj.optString("country_code", "").trim().toUpperCase(Locale.US);
            locDisplay = locObj.optString("name", locKey);
          }
        }
        if (gwCc.isEmpty() || "IN".equals(gwCc)) continue;
        if (!"AUTO_FOREIGN".equals(targetCc) && !targetCc.equals(gwCc)) continue;

        final List<Integer> tcpPorts = extractRiseupOpenVpnPorts(gw, "tcp");
        final List<Integer> udpPorts = extractRiseupOpenVpnPorts(gw, "udp");
        final String finalCc = gwCc;
        final String finalCountryName = countryNameForCode(gwCc) + " (" + locDisplay + ")";

        tasks.add(
            () -> {
              // Fast parallel-friendly gateway check: try UDP 1194 first (1-RTT tunnel setup),
              // then immediately fall back to TCP 1194 / 53 if UDP is carrier-filtered.
              int chosenPort = -1;
              String chosenProto = "udp";
              long bestRtt = -1L;

              if (!udpPorts.isEmpty()) {
                int udpPort = udpPorts.get(0);
                long rtt = probeOpenVpnUdp(ip, udpPort, 850);
                if (rtt >= 0) {
                  bestRtt = rtt;
                  chosenPort = udpPort;
                  chosenProto = "udp";
                }
              }

              if (bestRtt < 0) {
                for (int port : tcpPorts) {
                  long rtt = probeOpenVpnTcp(ip, port, 1200);
                  if (rtt >= 0) {
                    bestRtt = rtt;
                    chosenPort = port;
                    chosenProto = "tcp-client";
                    break;
                  }
                }
              }

              if (bestRtt < 0 || chosenPort <= 0) {
                return null;
              }

              StringBuilder cfg = new StringBuilder();
              cfg.append("client\n");
              cfg.append("dev tun\n");
              cfg.append("proto ").append(chosenProto).append('\n');
              cfg.append("remote ").append(ip).append(' ').append(chosenPort).append('\n');
              cfg.append("nobind\n");
              cfg.append("persist-key\n");
              if ("udp".equals(chosenProto)) {
                cfg.append("fast-io\n");
              }
              cfg.append("sndbuf 393216\n");
              cfg.append("rcvbuf 393216\n");
              cfg.append("connect-timeout 5\n");
              cfg.append("connect-retry 1 2\n");
              cfg.append("connect-retry-max 2\n");
              cfg.append("hand-window 12\n");
              cfg.append("remote-cert-tls server\n");
              cfg.append("tls-version-min 1.2\n");
              cfg.append("cipher AES-256-GCM\n");
              cfg.append("data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305\n");
              cfg.append("auth SHA512\n");
              cfg.append("keepalive 10 30\n");
              cfg.append("verb 3\n");
              cfg.append("<ca>\n").append(cachedRiseupCa).append("\n</ca>\n");
              cfg.append("<cert>\n").append(cachedRiseupCert).append("\n</cert>\n");
              cfg.append("<key>\n").append(cachedRiseupKey).append("\n</key>\n");

              return new VerifiedCandidate(
                  cfg.toString(), ip, finalCc, finalCountryName, bestRtt, 250_000_000L);
            });
      }

      if (tasks.isEmpty()) {
        return null;
      }
      return pickFastestCandidate(tasks, 2600L);
    } catch (Throwable ignored) {
      return null;
    }
  }

  private static List<Integer> extractRiseupOpenVpnPorts(JSONObject gw, String wantedProto) {
    List<Integer> ordered = new ArrayList<>();
    JSONObject caps = gw.optJSONObject("capabilities");
    JSONArray transports = caps != null ? caps.optJSONArray("transport") : null;
    if (transports != null) {
      for (int i = 0; i < transports.length(); i++) {
        JSONObject tr = transports.optJSONObject(i);
        if (tr == null || !"openvpn".equalsIgnoreCase(tr.optString("type", ""))) {
          continue;
        }
        boolean protoSupported = false;
        JSONArray protos = tr.optJSONArray("protocols");
        if (protos != null) {
          for (int p = 0; p < protos.length(); p++) {
            if (wantedProto.equalsIgnoreCase(protos.optString(p, ""))) {
              protoSupported = true;
              break;
            }
          }
        }
        if (!protoSupported) {
          continue;
        }
        JSONArray ports = tr.optJSONArray("ports");
        if (ports != null) {
          for (int k = 0; k < ports.length(); k++) {
            try {
              int portNum = Integer.parseInt(ports.optString(k, "").trim());
              if (portNum > 0 && !ordered.contains(portNum)) {
                ordered.add(portNum);
              }
            } catch (NumberFormatException ignored) {
            }
          }
        }
      }
    }
    if (ordered.isEmpty()) {
      ordered.add(1194);
      if ("tcp".equalsIgnoreCase(wantedProto)) {
        ordered.add(53);
        ordered.add(80);
      }
    } else {
      // Prioritize 1194 first, then 53, then 80 (avoids transparent port-80 HTTP proxies).
      Collections.sort(
          ordered,
          (a, b) -> {
            int rankA = a == 1194 ? 0 : (a == 53 ? 1 : (a == 80 ? 2 : 3));
            int rankB = b == 1194 ? 0 : (b == 53 ? 1 : (b == 80 ? 2 : 3));
            return Integer.compare(rankA, rankB);
          });
    }
    return ordered;
  }

  private VerifiedCandidate tryProvisionVpnGateCandidate(String targetCc, Set<String> excluded) {
    try {
      String csv = fetchVpnGateCsv(false);
      if (csv == null || csv.isEmpty()) {
        return null;
      }

      final class RawRow {
        final String countryLong;
        final String countryCode;
        final long speedBps;
        final String b64Ovpn;

        RawRow(String countryLong, String countryCode, long speedBps, String b64Ovpn) {
          this.countryLong = countryLong;
          this.countryCode = countryCode;
          this.speedBps = speedBps;
          this.b64Ovpn = b64Ovpn;
        }
      }

      List<RawRow> matches = new ArrayList<>();
      String[] lines = csv.split("\\r?\\n");
      for (int i = 2; i < lines.length; i++) {
        String[] parts = lines[i].split(",", 16);
        if (parts.length < 15) continue;
        String b64 = parts[14].trim();
        String cc = parts[6].trim().toUpperCase(Locale.US);
        String cLong = parts[5].trim();
        if (b64.isEmpty() || cc.isEmpty() || "IN".equals(cc)) continue;
        if (!"AUTO_FOREIGN".equals(targetCc) && !targetCc.equals(cc)) continue;

        long speed = 0L;
        try {
          speed = Long.parseLong(parts[4].trim());
        } catch (NumberFormatException ignored) {
        }
        matches.add(new RawRow(cLong, cc, speed, b64));
      }

      if (matches.isEmpty()) {
        return null;
      }
      Collections.sort(matches, (a, b) -> Long.compare(b.speedBps, a.speedBps));

      List<Callable<VerifiedCandidate>> tasks = new ArrayList<>();
      int limit = Math.min(matches.size(), 8);
      for (int i = 0; i < limit; i++) {
        RawRow row = matches.get(i);
        tasks.add(
            () -> {
              byte[] decoded = Base64.decode(row.b64Ovpn, Base64.DEFAULT);
              String rawOvpn = new String(decoded, StandardCharsets.UTF_8);
              Matcher remM = OVPN_REMOTE_PATTERN.matcher(rawOvpn);
              if (!remM.find()) {
                return null;
              }
              String host = remM.group(1);
              int port = Integer.parseInt(remM.group(2));
              if (host == null || excluded.contains(host)) {
                return null;
              }
              Matcher protoM = OVPN_PROTO_PATTERN.matcher(rawOvpn);
              String proto = protoM.find() ? protoM.group(1).toLowerCase(Locale.US) : "tcp";

              long rtt =
                  proto.contains("udp")
                      ? probeOpenVpnUdp(host, port, 1300)
                      : probeOpenVpnTcp(host, port, 1300);
              if (rtt < 0) {
                return null;
              }

              // Normalize VPNGate .ovpn for OpenVPN 2.7 + OpenSSL 3.5:
              // Strip pre-existing data-ciphers / data-ciphers-fallback so openvpn_flutter 2.0.0's
              // addCipherFallback() configures the server's exact --cipher & legacy provider,
              // Keep a modern TLS minimum; incompatible legacy relays must fail closed.
              String normalizedOvpn = normalizeVpnGateOvpnForOpenSsl3(rawOvpn);
              return new VerifiedCandidate(
                  normalizedOvpn, host, row.countryCode, row.countryLong, rtt, row.speedBps);
            });
      }

      return pickFastestCandidate(tasks, 2600L);
    } catch (Throwable ignored) {
      return null;
    }
  }

  static String normalizeVpnGateOvpnForOpenSsl3(String rawOvpn) {
    String[] lines = rawOvpn.replace("\r\n", "\n").split("\n");
    StringBuilder out = new StringBuilder(rawOvpn.length() + 128);
    boolean hasConnectTimeout = false;
    boolean insidePemBlock = false;

    for (String line : lines) {
      String trimmed = line.trim();
      String lower = trimmed.toLowerCase(Locale.US);
      if (lower.startsWith("<ca>")
          || lower.startsWith("<cert>")
          || lower.startsWith("<key>")
          || lower.startsWith("<tls-auth>")
          || lower.startsWith("<tls-crypt>")) {
        insidePemBlock = true;
      } else if (lower.startsWith("</ca>")
          || lower.startsWith("</cert>")
          || lower.startsWith("</key>")
          || lower.startsWith("</tls-auth>")
          || lower.startsWith("</tls-crypt>")) {
        insidePemBlock = false;
        out.append(line).append('\n');
        continue;
      }

      if (!insidePemBlock) {
        if (lower.startsWith("data-ciphers ")
            || lower.startsWith("data-ciphers\t")
            || lower.startsWith("data-ciphers-fallback ")
            || lower.startsWith("data-ciphers-fallback\t")) {
          continue;
        }
        if (lower.startsWith("tls-cipher ") || lower.startsWith("tls-cipher\t")) {
          continue;
        }
        if (lower.startsWith("tls-version-min ") || lower.startsWith("remote-cert-tls ")) {
          continue;
        }
        if (lower.startsWith("connect-timeout ")) {
          hasConnectTimeout = true;
        }
      }
      out.append(line).append('\n');
    }

    out.append("tls-cipher DEFAULT:@SECLEVEL=2\n");
    out.append("tls-version-min 1.2\n");
    out.append("remote-cert-tls server\n");
    if (!hasConnectTimeout) {
      out.append("connect-timeout 8\n");
      out.append("connect-retry-max 2\n");
    }
    return out.toString();
  }

  /**
   * Races all candidate gateway probes concurrently and returns the VERY FIRST verified live
   * server immediately (cancelling slow/offline gateways instead of blocking for full timeoutMs!).
   */
  private VerifiedCandidate pickFastestCandidate(
      List<Callable<VerifiedCandidate>> tasks, long timeoutMs) {
    if (tasks.isEmpty()) {
      return null;
    }
    CompletionService<VerifiedCandidate> cs = new ExecutorCompletionService<>(probePool);
    List<Future<VerifiedCandidate>> submitted = new ArrayList<>(tasks.size());
    for (Callable<VerifiedCandidate> task : tasks) {
      submitted.add(cs.submit(task));
    }

    long deadline = System.currentTimeMillis() + timeoutMs;
    try {
      for (int i = 0; i < submitted.size(); i++) {
        long remaining = deadline - System.currentTimeMillis();
        if (remaining <= 0L) {
          break;
        }
        Future<VerifiedCandidate> done = cs.poll(remaining, TimeUnit.MILLISECONDS);
        if (done == null) {
          break;
        }
        try {
          VerifiedCandidate candidate = done.get();
          if (candidate != null) {
            return candidate;
          }
        } catch (Throwable ignored) {
        }
      }
      return null;
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return null;
    } finally {
      for (Future<VerifiedCandidate> f : submitted) {
        if (!f.isDone()) {
          f.cancel(true);
        }
      }
    }
  }

  private synchronized void ensureRiseupReady() {
    long now = System.currentTimeMillis();
    boolean credsFresh =
        cachedRiseupCa != null
            && cachedRiseupCert != null
            && cachedRiseupKey != null
            && (now - cachedRiseupCertAtMs) < 3600_000L * 12;
    boolean eipFresh =
        cachedRiseupEipJson != null
            && !cachedRiseupEipJson.isEmpty()
            && (now - cachedRiseupEipAtMs) < 3600_000L * 6;
    if (credsFresh && eipFresh) {
      return;
    }

    Future<String> caFuture =
        credsFresh ? null : probePool.submit(() -> httpGetText(RISEUP_CA_URL, null, 4500));
    Future<String> certFuture =
        credsFresh ? null : probePool.submit(() -> httpPostEmptyText(RISEUP_CERT_URL, 5000));
    Future<String> eipFuture =
        eipFresh ? null : probePool.submit(() -> httpGetText(RISEUP_EIP_URL, null, 4500));

    SharedPreferences.Editor editor = cachePrefs.edit();
    boolean wrote = false;

    if (!credsFresh && caFuture != null && certFuture != null) {
      try {
        String ca = caFuture.get(5200, TimeUnit.MILLISECONDS);
        String clientPem = certFuture.get(5500, TimeUnit.MILLISECONDS);
        if (ca != null && clientPem != null) {
          Matcher keyM = PEM_KEY_PATTERN.matcher(clientPem);
          Matcher certM = PEM_CERT_PATTERN.matcher(clientPem);
          if (keyM.find() && certM.find()) {
            cachedRiseupCa = ca.trim();
            cachedRiseupKey = keyM.group(1).trim();
            cachedRiseupCert = certM.group(1).trim();
            cachedRiseupCertAtMs = now;
            editor
                .putString(PREF_RISEUP_CA, cachedRiseupCa)
                .putLong(PREF_RISEUP_CERT_AT, now);
            VpnSecretStore.write(appContext, PREF_RISEUP_CERT, cachedRiseupCert);
            VpnSecretStore.write(appContext, PREF_RISEUP_KEY, cachedRiseupKey);
            wrote = true;
          }
        }
      } catch (Throwable ignored) {
      }
    }

    if (!eipFresh && eipFuture != null) {
      try {
        String eip = eipFuture.get(5000, TimeUnit.MILLISECONDS);
        if (eip != null && !eip.isEmpty()) {
          cachedRiseupEipJson = eip;
          cachedRiseupEipAtMs = now;
          editor.putString(PREF_RISEUP_EIP, eip).putLong(PREF_RISEUP_EIP_AT, now);
          wrote = true;
        }
      } catch (Throwable ignored) {
      }
    }

    if (wrote) {
      editor.apply();
    }
  }

  private synchronized String fetchVpnGateCsv(boolean forceRefresh) {
    long now = System.currentTimeMillis();
    if (!forceRefresh
        && cachedVpnGateCsv != null
        && (now - cachedVpnGateAtMs) < 300_000L) {
      return cachedVpnGateCsv;
    }
    if (!forceRefresh && lastVpnGateFailAtMs > 0L && (now - lastVpnGateFailAtMs) < 90_000L) {
      return cachedVpnGateCsv;
    }

    // Use only HTTPS with a strict 2.4s timeout so ISP filtering
    // on vpngate.net NEVER hangs the Refresh spinner or delays VPN connection!
    CompletionService<String> cs = new ExecutorCompletionService<>(probePool);
    List<Future<String>> futures = new ArrayList<>(1);
    futures.add(
        cs.submit(
            () -> {
              String s = httpGetText(VPNGATE_HTTPS_URL, null, 2400);
              return (s != null && s.contains("*vpn_servers")) ? s : null;
            }));

    String freshCsv = null;
    long deadline = System.currentTimeMillis() + 2600L;
    try {
      for (int i = 0; i < futures.size(); i++) {
        long rem = deadline - System.currentTimeMillis();
        if (rem <= 0L) break;
        Future<String> f = cs.poll(rem, TimeUnit.MILLISECONDS);
        if (f == null) break;
        try {
          String candidate = f.get();
          if (candidate != null) {
            freshCsv = candidate;
            break;
          }
        } catch (Throwable ignored) {
        }
      }
    } catch (InterruptedException ie) {
      Thread.currentThread().interrupt();
    } finally {
      for (Future<String> f : futures) {
        if (!f.isDone()) {
          f.cancel(true);
        }
      }
    }

    if (freshCsv != null) {
      cachedVpnGateCsv = freshCsv;
      cachedVpnGateAtMs = now;
      lastVpnGateFailAtMs = 0L;
      cachePrefs
          .edit()
          .putString(PREF_VPNGATE_CSV, freshCsv)
          .putLong(PREF_VPNGATE_AT, now)
          .apply();
      return freshCsv;
    }
    lastVpnGateFailAtMs = now;
    return cachedVpnGateCsv;
  }

  /**
   * Sends a genuine OpenVPN P_CONTROL_HARD_RESET_CLIENT_V2 (0x38) frame over TCP and verifies
   * the remote server replies with P_CONTROL_HARD_RESET_SERVER_V2 (opcode 8).
   */
  private long probeOpenVpnTcp(String host, int port, int timeoutMs) {
    long t0 = System.currentTimeMillis();
    try (Socket s = new Socket()) {
      s.connect(new InetSocketAddress(host, port), timeoutMs);
      s.setSoTimeout(timeoutMs);
      byte[] sessionId = new byte[8];
      secureRandom.nextBytes(sessionId);
      byte[] frame = new byte[16];
      frame[0] = 0x00;
      frame[1] = 0x0E; // 14-byte OpenVPN payload
      frame[2] = 0x38; // P_CONTROL_HARD_RESET_CLIENT_V2 << 3
      System.arraycopy(sessionId, 0, frame, 3, 8);

      OutputStream out = s.getOutputStream();
      out.write(frame);
      out.flush();

      InputStream in = s.getInputStream();
      int b0 = in.read();
      int b1 = in.read();
      int opcodeByte = in.read();
      if (b0 < 0 || b1 < 0 || opcodeByte < 0) {
        return -1L;
      }
      int opcode = (opcodeByte & 0xFF) >> 3;
      return opcode == 8 ? Math.max(1L, System.currentTimeMillis() - t0) : -1L;
    } catch (Throwable ignored) {
      return -1L;
    }
  }

  /**
   * Sends a genuine OpenVPN P_CONTROL_HARD_RESET_CLIENT_V2 (0x38) datagram over UDP and verifies
   * the remote server replies with P_CONTROL_HARD_RESET_SERVER_V2 (opcode 8).
   */
  private long probeOpenVpnUdp(String host, int port, int timeoutMs) {
    long t0 = System.currentTimeMillis();
    try (DatagramSocket ds = new DatagramSocket()) {
      ds.setSoTimeout(timeoutMs);
      byte[] pkt = new byte[14];
      pkt[0] = 0x38;
      byte[] sessionId = new byte[8];
      secureRandom.nextBytes(sessionId);
      System.arraycopy(sessionId, 0, pkt, 1, 8);

      InetAddress addr = InetAddress.getByName(host);
      ds.send(new DatagramPacket(pkt, pkt.length, addr, port));

      byte[] recvBuf = new byte[256];
      DatagramPacket resp = new DatagramPacket(recvBuf, recvBuf.length);
      ds.receive(resp);
      if (resp.getLength() < 1) {
        return -1L;
      }
      int opcode = (recvBuf[0] & 0xFF) >> 3;
      return opcode == 8 ? Math.max(1L, System.currentTimeMillis() - t0) : -1L;
    } catch (Throwable ignored) {
      return -1L;
    }
  }

  private static String httpGetText(
      String url, Map<String, String> extraHeaders, int timeoutMs) {
    HttpURLConnection conn = null;
    try {
      if (!url.startsWith("https://")) return null;
      conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
      conn.setInstanceFollowRedirects(false);
      conn.setRequestMethod("GET");
      conn.setConnectTimeout(timeoutMs);
      conn.setReadTimeout(timeoutMs);
      conn.setRequestProperty("User-Agent", "MaxPlayer/1.0");
      if (extraHeaders != null) {
        for (Map.Entry<String, String> e : extraHeaders.entrySet()) {
          conn.setRequestProperty(e.getKey(), e.getValue());
        }
      }
      int code = conn.getResponseCode();
      if (code < 200 || code >= 300) {
        return null;
      }
      StringBuilder sb = new StringBuilder();
      try (BufferedReader br =
          new BufferedReader(
              new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
        String line;
        while ((line = br.readLine()) != null) {
          if (sb.length() + line.length() > 4 * 1024 * 1024) return null;
          sb.append(line).append('\n');
        }
      }
      return sb.toString();
    } catch (Throwable ignored) {
      return null;
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
  }

  private static String httpPostEmptyText(String url, int timeoutMs) {
    HttpURLConnection conn = null;
    try {
      if (!url.startsWith("https://")) return null;
      conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
      conn.setInstanceFollowRedirects(false);
      conn.setRequestMethod("POST");
      conn.setConnectTimeout(timeoutMs);
      conn.setReadTimeout(timeoutMs);
      conn.setDoOutput(true);
      conn.setFixedLengthStreamingMode(0);
      conn.setRequestProperty("User-Agent", "MaxPlayer/1.0");
      try (OutputStream os = conn.getOutputStream()) {
        os.flush();
      }
      int code = conn.getResponseCode();
      if (code < 200 || code >= 300) {
        return null;
      }
      StringBuilder sb = new StringBuilder();
      try (BufferedReader br =
          new BufferedReader(
              new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
        String line;
        while ((line = br.readLine()) != null) {
          if (sb.length() + line.length() > 4 * 1024 * 1024) return null;
          sb.append(line).append('\n');
        }
      }
      return sb.toString();
    } catch (Throwable ignored) {
      return null;
    } finally {
      if (conn != null) {
        conn.disconnect();
      }
    }
  }

  private static String countryNameForCode(String cc) {
    if ("US".equals(cc)) return "United States";
    if ("NL".equals(cc)) return "Netherlands";
    if ("FR".equals(cc)) return "France";
    if ("CA".equals(cc)) return "Canada";
    if ("JP".equals(cc)) return "Japan";
    if ("KR".equals(cc)) return "South Korea";
    if ("HK".equals(cc)) return "Hong Kong";
    if ("TH".equals(cc)) return "Thailand";
    if ("SG".equals(cc)) return "Singapore";
    if ("GB".equals(cc)) return "United Kingdom";
    if ("DE".equals(cc)) return "Germany";
    if ("SE".equals(cc)) return "Sweden";
    if ("VN".equals(cc)) return "Vietnam";
    return cc;
  }

  public void provisionFreeWarpConfig(MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          HttpURLConnection conn = null;
          try {
            KeyPair keyPair = new KeyPair();
            String privateKeyB64 = keyPair.getPrivateKey().toBase64();
            String publicKeyB64 = keyPair.getPublicKey().toBase64();

            SimpleDateFormat iso =
                new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
            iso.setTimeZone(TimeZone.getTimeZone("UTC"));

            JSONObject body = new JSONObject();
            body.put("key", publicKeyB64);
            body.put("install_id", "");
            body.put("fcm_token", "");
            body.put("tos", iso.format(new Date()));
            body.put("model", "Android");
            body.put("type", "Android");
            body.put("locale", "en_US");

            byte[] payloadBytes = body.toString().getBytes(StandardCharsets.UTF_8);

            conn = (HttpURLConnection) URI.create(WARP_REG_URL).toURL().openConnection();
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(5500);
            conn.setReadTimeout(5500);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setRequestProperty("Accept", "application/json");
            conn.setRequestProperty("CF-Client-Version", "a-6.30-3596");
            conn.setRequestProperty("User-Agent", "okhttp/4.12.0");

            try (OutputStream os = conn.getOutputStream()) {
              os.write(payloadBytes);
            }

            int status = conn.getResponseCode();
            InputStream stream =
                status >= 200 && status < 300 ? conn.getInputStream() : conn.getErrorStream();
            StringBuilder sb = new StringBuilder();
            if (stream != null) {
              try (BufferedReader br =
                  new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                String line;
                while ((line = br.readLine()) != null) {
                  sb.append(line);
                }
              }
            }

            if (status < 200 || status >= 300) {
              postError(
                  result,
                  "WARP registration HTTP " + status + ". Connecting via OpenVPN fallback.");
              return;
            }

            JSONObject json = new JSONObject(sb.toString());
            JSONObject cfgObj = json.optJSONObject("config");
            if (cfgObj == null) {
              postError(result, "Unexpected WARP config response");
              return;
            }

            JSONObject iface = cfgObj.optJSONObject("interface");
            JSONObject addrs = iface != null ? iface.optJSONObject("addresses") : null;
            String v4 = addrs != null ? addrs.optString("v4", "172.16.0.2") : "172.16.0.2";
            String v6 = addrs != null ? addrs.optString("v6", "") : "";

            JSONArray peers = cfgObj.optJSONArray("peers");
            JSONObject peer0 = (peers != null && peers.length() > 0) ? peers.optJSONObject(0) : null;
            String peerPubKey =
                peer0 != null
                    ? peer0.optString("public_key", WARP_PEER_PUBKEY)
                    : WARP_PEER_PUBKEY;

            int preferredPort = 2408;
            String endpointHost = "162.159.192.2:2408";
            if (peer0 != null) {
              JSONObject ep = peer0.optJSONObject("endpoint");
              if (ep != null) {
                JSONArray portsArr = ep.optJSONArray("ports");
                if (portsArr != null) {
                  for (int i = 0; i < portsArr.length(); i++) {
                    int candidatePort = portsArr.optInt(i, -1);
                    if (candidatePort > 0) {
                      preferredPort = candidatePort;
                      break;
                    }
                  }
                }
                String rawV4 = ep.optString("v4", "").trim();
                if (!rawV4.isEmpty()) {
                  endpointHost = normalizeEndpointPort(rawV4, preferredPort);
                }
              }
            }

            StringBuilder wgConf = new StringBuilder();
            wgConf.append("[Interface]\n");
            wgConf.append("PrivateKey = ").append(privateKeyB64).append('\n');
            wgConf.append("Address = ").append(v4).append("/32");
            if (!v6.isEmpty()) {
              wgConf.append(", ").append(v6).append("/128");
            }
            wgConf.append('\n');
            wgConf.append("DNS = 1.1.1.1, 1.0.0.1\n");
            wgConf.append("MTU = 1280\n\n");
            wgConf.append("[Peer]\n");
            wgConf.append("PublicKey = ").append(peerPubKey).append('\n');
            wgConf.append("AllowedIPs = 0.0.0.0/0\n");
            wgConf.append("Endpoint = ").append(endpointHost).append('\n');
            wgConf.append("PersistentKeepalive = 25\n");

            Map<String, Object> payload = new HashMap<>();
            payload.put("ok", true);
            payload.put("configText", wgConf.toString());
            payload.put("clientIpv4", v4);
            payload.put("endpoint", endpointHost);
            mainHandler.post(() -> result.success(payload));
          } catch (Throwable t) {
            postError(
                result,
                t.getMessage() != null ? t.getMessage() : "Unable to provision free VPN profile");
          } finally {
            if (conn != null) {
              conn.disconnect();
            }
          }
        });
  }

  static String normalizeEndpointPort(String endpoint, int defaultPort) {
    if (endpoint == null || endpoint.trim().isEmpty()) {
      return "162.159.192.2:" + defaultPort;
    }
    String clean = endpoint.trim();
    int lastColon = clean.lastIndexOf(':');
    int rightBracket = clean.lastIndexOf(']');
    if (lastColon > rightBracket && lastColon > 0) {
      String hostPart = clean.substring(0, lastColon).trim();
      String portPart = clean.substring(lastColon + 1).trim();
      try {
        int p = Integer.parseInt(portPart);
        if (p > 0 && p <= 65535) {
          return hostPart + ":" + p;
        }
      } catch (NumberFormatException ignored) {
      }
      return hostPart + ":" + defaultPort;
    }
    return clean + ":" + defaultPort;
  }

  static String sanitizeWireGuardEndpoints(String rawText) {
    String[] lines = rawText.replace("\r\n", "\n").split("\n");
    StringBuilder out = new StringBuilder(rawText.length() + 16);
    for (String line : lines) {
      String trimmed = line.trim();
      if (trimmed.toLowerCase(Locale.US).startsWith("endpoint")) {
        int eq = trimmed.indexOf('=');
        if (eq > 0) {
          String rhs = trimmed.substring(eq + 1).trim();
          out.append("Endpoint = ").append(normalizeEndpointPort(rhs, 2408)).append('\n');
          continue;
        }
      }
      out.append(line).append('\n');
    }
    return out.toString();
  }

  static String replaceWireGuardEndpoint(String rawText, String newEndpoint) {
    String[] lines = rawText.replace("\r\n", "\n").split("\n");
    StringBuilder out = new StringBuilder(rawText.length() + 32);
    for (String line : lines) {
      String trimmed = line.trim();
      if (trimmed.toLowerCase(Locale.US).startsWith("endpoint")) {
        out.append("Endpoint = ").append(newEndpoint).append('\n');
      } else if (trimmed.toLowerCase(Locale.US).startsWith("allowedips")
          && rawText.contains(WARP_PEER_PUBKEY)) {
        // Route IPv4 cleanly without IPv6 leak/blackhole on IPv4-only mobile APNs.
        out.append("AllowedIPs = 0.0.0.0/0\n");
      } else {
        out.append(line).append('\n');
      }
    }
    return out.toString();
  }

  public void validateWireGuardConfig(String configText, MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          try {
            Config parsed = parseConfig(sanitizeWireGuardEndpoints(configText), false);
            String endpoint = "";
            for (Peer p : parsed.getPeers()) {
              InetEndpoint ep = p.getEndpoint().orElse(null);
              if (ep != null) {
                endpoint = ep.toString();
                break;
              }
            }
            StringBuilder addrs = new StringBuilder();
            for (InetNetwork net : parsed.getInterface().getAddresses()) {
              if (addrs.length() > 0) {
                addrs.append(", ");
              }
              addrs.append(net.toString());
            }
            Map<String, Object> res = new HashMap<>();
            res.put("valid", true);
            res.put("endpoint", endpoint);
            res.put("addresses", addrs.toString());
            mainHandler.post(() -> result.success(res));
          } catch (Throwable t) {
            Map<String, Object> res = new HashMap<>();
            res.put("valid", false);
            res.put(
                "error",
                t.getMessage() != null ? t.getMessage() : "Invalid WireGuard configuration");
            mainHandler.post(() -> result.success(res));
          }
        });
  }

  public void connectVpn(
      Activity activity,
      String configText,
      String profileName,
      boolean browserOnly,
      MethodChannel.Result result) {
    if (configText == null || configText.trim().isEmpty()) {
      postError(result, "Missing WireGuard VPN configuration");
      return;
    }

    Intent prepareIntent = VpnService.prepare(appContext);
    if (prepareIntent != null) {
      if (activity == null) {
        postError(result, "Activity unavailable to grant VPN permission");
        return;
      }
      this.pendingConnect =
          new PendingConnectRequest(configText, profileName, browserOnly, result);
      activity.startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE);
      return;
    }

    activateTunnelAsync(configText, profileName, browserOnly, result);
  }

  public boolean onActivityResult(int requestCode, int resultCode) {
    if (requestCode != VPN_PERMISSION_REQUEST_CODE) {
      return false;
    }
    PendingConnectRequest req = this.pendingConnect;
    this.pendingConnect = null;
    if (req == null) {
      return true;
    }
    if (resultCode == Activity.RESULT_OK) {
      activateTunnelAsync(req.configText, req.profileName, req.browserOnly, req.result);
    } else {
      postError(req.result, "VPN connection permission was declined");
    }
    return true;
  }

  private void activateTunnelAsync(
      String rawConfigText,
      String profileName,
      boolean browserOnly,
      MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          GoBackend backend = ensureBackend();
          try {
            String sanitized = sanitizeWireGuardEndpoints(rawConfigText);
            boolean isWarpConfig = sanitized.contains(WARP_PEER_PUBKEY);

            List<String> candidateConfigs = new ArrayList<>();
            candidateConfigs.add(sanitized);
            if (isWarpConfig) {
              for (String altEp : WARP_FALLBACK_ENDPOINTS) {
                String altCfg = replaceWireGuardEndpoint(sanitized, altEp);
                if (!candidateConfigs.contains(altCfg)) {
                  candidateConfigs.add(altCfg);
                }
              }
            }

            String label =
                (profileName != null && !profileName.trim().isEmpty())
                    ? profileName.trim()
                    : "RunX Player VPN";

            for (int idx = 0; idx < candidateConfigs.size(); idx++) {
              String candidateText = candidateConfigs.get(idx);
              Config parsed = parseConfig(candidateText, browserOnly);

              if (backend.getState(wgTunnel) == Tunnel.State.UP) {
                backend.setState(wgTunnel, Tunnel.State.DOWN, null);
              }
              Tunnel.State state = backend.setState(wgTunnel, Tunnel.State.UP, parsed);
              if (state != Tunnel.State.UP) {
                continue;
              }

              // For user-imported custom WireGuard configs, keep the user's tunnel up directly;
              // for built-in WARP configs, cryptographically verify a real peer handshake quickly
              // so we never leave a UDP-blocked carrier tunnel in a black-hole state.
              if (!isWarpConfig || waitForWireGuardPeerHandshake(backend, 1500L)) {
                currentState = Tunnel.State.UP;
                activeProfileName = label;
                showConnectedNotification(activeProfileName, browserOnly);

                Map<String, Object> out = new HashMap<>();
                out.put("ok", true);
                out.put("connected", true);
                out.put("profileName", activeProfileName);
                out.put("activeConfigText", candidateText);
                mainHandler.post(() -> result.success(out));
                return;
              }

              // No handshake received on this UDP endpoint — tear down before trying next port.
              try {
                backend.setState(wgTunnel, Tunnel.State.DOWN, null);
              } catch (Throwable ignored) {
              }
            }

            currentState = Tunnel.State.DOWN;
            cancelStatusNotification();
            postError(
                result,
                "WireGuard UDP ports are blocked on this network. Switching to OpenVPN TCP.");
          } catch (Throwable t) {
            try {
              backend.setState(wgTunnel, Tunnel.State.DOWN, null);
            } catch (Throwable ignored) {
            }
            currentState = Tunnel.State.DOWN;
            cancelStatusNotification();
            postError(
                result,
                t.getMessage() != null ? t.getMessage() : "Failed to establish WireGuard tunnel");
          }
        });
  }

  private boolean waitForWireGuardPeerHandshake(GoBackend backend, long maxWaitMs) {
    // Trigger an immediate UDP datagram + HTTPS probe through tun0 so wg-go sends
    // Noise_IKpsk2 HandshakeInitiation in <1ms instead of waiting for TCP SYN backoff.
    probePool.execute(
        () -> {
          try (DatagramSocket ds = new DatagramSocket()) {
            byte[] wake = new byte[] {0x00};
            ds.send(new DatagramPacket(wake, 1, InetAddress.getByName("1.1.1.1"), 53));
          } catch (Throwable ignored) {
          }
          try {
            httpGetText("https://1.1.1.1/cdn-cgi/trace", null, 1300);
          } catch (Throwable ignored) {
          }
        });

    long deadline = System.currentTimeMillis() + maxWaitMs;
    while (System.currentTimeMillis() < deadline) {
      try {
        Statistics stats = backend.getStatistics(wgTunnel);
        if (stats != null) {
          if (stats.totalRx() > 0L) {
            return true;
          }
          Key[] peers = stats.peers();
          if (peers != null) {
            for (Key k : peers) {
              Statistics.PeerStats ps = stats.peer(k);
              if (ps != null && (ps.rxBytes() > 0L || ps.latestHandshakeEpochMillis() > 0L)) {
                return true;
              }
            }
          }
        }
        Thread.sleep(60L);
      } catch (InterruptedException ie) {
        Thread.currentThread().interrupt();
        return false;
      } catch (Throwable ignored) {
      }
    }
    return false;
  }

  public void disconnectVpn(MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          try {
            if (goBackend != null) {
              goBackend.setState(wgTunnel, Tunnel.State.DOWN, null);
            }
          } catch (Throwable ignored) {
            // Ensure clean state even if tunnel already stopped.
          }
          currentState = Tunnel.State.DOWN;
          cancelStatusNotification();
          Map<String, Object> out = new HashMap<>();
          out.put("ok", true);
          out.put("connected", false);
          mainHandler.post(() -> result.success(out));
        });
  }

  public void getVpnStatus(MethodChannel.Result result) {
    vpnExecutor.execute(
        () -> {
          boolean up = false;
          long rx = 0L;
          long tx = 0L;
          try {
            if (goBackend != null) {
              up = goBackend.getState(wgTunnel) == Tunnel.State.UP;
              currentState = up ? Tunnel.State.UP : Tunnel.State.DOWN;
              if (up) {
                Statistics stats = goBackend.getStatistics(wgTunnel);
                rx = stats.totalRx();
                tx = stats.totalTx();
              }
            }
          } catch (Throwable ignored) {
            up = currentState == Tunnel.State.UP;
          }
          Map<String, Object> out = new HashMap<>();
          out.put("connected", up);
          out.put("rxBytes", rx);
          out.put("txBytes", tx);
          out.put("profileName", activeProfileName);
          mainHandler.post(() -> result.success(out));
        });
  }

  private Config parseConfig(String rawText, boolean browserOnly) throws Exception {
    String[] lines = rawText.replace("\r\n", "\n").split("\n");
    StringBuilder rewritten = new StringBuilder();
    boolean injectedSplitTunnel = false;

    for (String rawLine : lines) {
      String trimmed = rawLine.trim();
      String lower = trimmed.toLowerCase(Locale.US);
      if (lower.startsWith("includedapplications")
          || lower.startsWith("excludedapplications")) {
        continue;
      }
      rewritten.append(rawLine).append('\n');
      if (!injectedSplitTunnel && "[interface]".equalsIgnoreCase(trimmed) && browserOnly) {
        rewritten
            .append("IncludedApplications = ")
            .append(appContext.getPackageName())
            .append('\n');
        injectedSplitTunnel = true;
      }
    }

    byte[] bytes = rewritten.toString().getBytes(StandardCharsets.UTF_8);
    return Config.parse(new ByteArrayInputStream(bytes));
  }

  @SuppressWarnings("deprecation")
  private void showConnectedNotification(String profileName, boolean browserOnly) {
    try {
      NotificationManager nm =
          (NotificationManager) appContext.getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm == null) {
        return;
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        NotificationChannel ch =
            new NotificationChannel(
                VPN_NOTIF_CHANNEL,
                "RunX Player VPN Status",
                NotificationManager.IMPORTANCE_LOW);
        ch.setDescription("Shows encrypted RunX Player VPN tunnel status");
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);
      }

      Intent launchIntent =
          appContext.getPackageManager().getLaunchIntentForPackage(appContext.getPackageName());
      PendingIntent pi = null;
      if (launchIntent != null) {
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        pi = PendingIntent.getActivity(appContext, 7701, launchIntent, flags);
      }

      Notification.Builder builder =
          Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
              ? new Notification.Builder(appContext, VPN_NOTIF_CHANNEL)
              : new Notification.Builder(appContext);

      String scope = browserOnly ? "RunX Player only" : "Device-Wide Tunnel";
      builder
          .setSmallIcon(android.R.drawable.ic_lock_lock)
          .setContentTitle("RunX Player VPN Active - " + profileName)
          .setContentText("Encrypted Tunnel (" + scope + ")")
          .setOngoing(true);
      if (pi != null) {
        builder.setContentIntent(pi);
      }
      nm.notify(VPN_NOTIF_ID, builder.build());
    } catch (Throwable ignored) {
      // Non-fatal if notifications are suppressed by system settings.
    }
  }

  private void cancelStatusNotification() {
    try {
      NotificationManager nm =
          (NotificationManager) appContext.getSystemService(Context.NOTIFICATION_SERVICE);
      if (nm != null) {
        nm.cancel(VPN_NOTIF_ID);
      }
    } catch (Throwable ignored) {
    }
  }

  private static String[] regionalFallbacksFor(String cc) {
    switch (cc) {
      case "GB":
      case "IE":
      case "DE":
      case "NL":
      case "FR":
      case "CH":
      case "SE":
      case "NO":
      case "FI":
      case "DK":
      case "ES":
      case "IT":
      case "AT":
      case "BE":
      case "PT":
      case "PL":
      case "RO":
      case "CZ":
        return new String[] {"NL", "FR", "GB"};
      case "JP":
      case "KR":
      case "SG":
      case "HK":
      case "TW":
      case "TH":
      case "VN":
      case "MY":
      case "ID":
      case "PH":
      case "AU":
      case "NZ":
        return new String[] {"JP", "KR", "TH"};
      case "US":
      case "CA":
      case "MX":
      case "BR":
      case "AR":
      case "CL":
      case "CO":
        return new String[] {"US", "CA"};
      default:
        return new String[] {"US", "NL", "FR", "JP"};
    }
  }

  private void postError(MethodChannel.Result result, String message) {
    Map<String, Object> out = new HashMap<>();
    out.put("ok", false);
    out.put("connected", false);
    out.put("error", message);
    mainHandler.post(() -> result.success(out));
  }
}
