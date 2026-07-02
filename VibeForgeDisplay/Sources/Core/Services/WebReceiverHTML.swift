import Foundation

/// The HTML served to browser-based receivers (smart TVs, phones, sticks with a browser).
/// Apple devices play HLS natively via <video>; other browsers fall back to hls.js.
/// This is embedded (not bundle-loaded) so the server has no filesystem dependency.
enum WebReceiver {
    static let html = ##"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<title>VibeForge Display — Receiver</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: #0a0a0d; color: #eee;
    font-family: -apple-system, system-ui, Segoe UI, Roboto, sans-serif; }
  #stage { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center; background: #000; }
  video { width: 100%; height: 100%; object-fit: contain; background: #000; }
  #picker { padding: 6vh 6vw; }
  h1 { font-weight: 600; font-size: clamp(20px, 3vw, 34px); margin: 0 0 4px; }
  p.sub { color: #8a8a92; margin: 0 0 4vh; font-size: clamp(13px, 1.6vw, 18px); }
  a.tile { display: block; text-decoration: none; color: #eee; background: #15151a;
    border: 1px solid #26262c; border-radius: 14px; padding: 20px 22px; margin: 0 0 14px;
    font-size: clamp(16px, 2vw, 22px); transition: background .15s, border-color .15s; }
  a.tile:hover, a.tile:focus { background: #1c1c24; border-color: #5a8cff; outline: none; }
  .dot { display:inline-block; width:9px; height:9px; border-radius:50%; background:#4cc072; margin-right:10px; }
  #status { position: fixed; left: 0; right: 0; bottom: 0; text-align: center;
    color: #8a8a92; font-size: 13px; padding: 10px; pointer-events: none; }
  .err { color: #e05a5f; }
</style>
</head>
<body>
<div id="stage" style="display:none"><video id="v" autoplay playsinline muted controls></video></div>
<div id="picker">
  <h1>VibeForge Display</h1>
  <p class="sub">Choose a screen to show on this TV.</p>
  <div id="list">Looking for streams…</div>
</div>
<div id="status"></div>
<script>
  const qs = new URLSearchParams(location.search);
  const key = qs.get('s');
  const statusEl = document.getElementById('status');
  const setStatus = (t, isErr) => { statusEl.textContent = t || ''; statusEl.className = isErr ? 'err' : ''; };

  async function showPicker() {
    try {
      const res = await fetch('/streams.json', { cache: 'no-store' });
      const streams = await res.json();
      const list = document.getElementById('list');
      if (!streams.length) { list.textContent = 'No active streams yet. Start one from the Mac.'; setTimeout(showPicker, 2000); return; }
      list.innerHTML = '';
      for (const s of streams) {
        const a = document.createElement('a');
        a.className = 'tile'; a.href = '/?s=' + encodeURIComponent(s.key);
        a.innerHTML = '<span class="dot"></span>' + (s.name || s.key);
        list.appendChild(a);
      }
    } catch (e) { setTimeout(showPicker, 2000); }
  }

  function play(streamKey) {
    document.getElementById('picker').style.display = 'none';
    document.getElementById('stage').style.display = 'flex';
    const v = document.getElementById('v');
    const src = '/s/' + encodeURIComponent(streamKey) + '/media.m3u8';
    setStatus('Connecting…');
    v.addEventListener('playing', () => setStatus(''));
    v.addEventListener('waiting', () => setStatus('Buffering…'));

    if (v.canPlayType('application/vnd.apple.mpegurl')) {
      // Native HLS (Safari / iOS / macOS)
      v.src = src;
      v.play().catch(() => setStatus('Tap to start playback'));
      return;
    }
    // Fallback: hls.js for browsers without native HLS (Android/Fire TV/Chrome)
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.13/dist/hls.min.js';
    script.onload = () => {
      if (window.Hls && window.Hls.isSupported()) {
        const hls = new window.Hls({ lowLatencyMode: true, liveSyncDurationCount: 2, maxLiveSyncPlaybackRate: 1.5 });
        hls.loadSource(src);
        hls.attachMedia(v);
        hls.on(window.Hls.Events.ERROR, (_, d) => { if (d.fatal) setStatus('Stream error — retrying…', true); });
      } else { setStatus('This browser cannot play the stream.', true); }
    };
    script.onerror = () => setStatus('Could not load player (no internet on this device?).', true);
    document.head.appendChild(script);
  }

  if (key) play(key); else showPicker();
</script>
</body>
</html>
"""##
}
