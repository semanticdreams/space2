# libtorrent

## Canonical Import

```fennel
(local libtorrent (require :libtorrent))
```

## Source Files

- `src/lua_libtorrent.cpp`

## What It Provides

`libtorrent` exposes the optional libtorrent-rasterbar binding for creating/loading torrent metadata, running sessions, managing torrent handles, reading alerts, DHT operations, bencoding, resume/session state, and selected libtorrent constants.

## API Summary

- Availability: `available` is true when built with libtorrent support; otherwise functions throw and `missing-reason` explains the disabled build.
- Session creation: `Session(opts)` and `session([opts])` return `SessionHandle` objects. `session-params([opts])` creates reusable session parameters.
- Metadata helpers include `create-torrent(opts)`, `load-torrent-file(path)`, `load-torrent-buffer(buffer)`, `parse-magnet-uri(uri)`, `make-magnet-uri(path)`, parameter loaders, resume-data readers/writers, session-param readers/writers, `bencode(value)`, and `bdecode(buffer)`.
- `SessionHandle` methods cover add/find/remove torrents, per-torrent limits/priorities/status/info, pause/resume, DHT start/stop/queries/puts/direct requests, settings, session status/state, alerts, stats requests, and `drop`/`is-closed`.
- `AddTorrentParamsHandle` and `SessionParamsHandle` expose mutation and `to-table` helpers for parameter workflows.
- Constants/tables include `torrent-flags`, `storage-modes`, `save-state-flags`, and `dht-announce-flags`; version/category helpers expose native library information.

## Examples

```fennel
(local libtorrent (require :libtorrent))

(when libtorrent.available
  (local session (libtorrent.session {:listen-interfaces "0.0.0.0:0"}))
  (local parsed (libtorrent.parse-magnet-uri "magnet:?xt=urn:btih:0123456789012345678901234567890123456789"))
  (print parsed.info-hash)
  (session:drop))
```

## Errors and Platform Notes

When libtorrent is not compiled in, `available` is false and API calls raise `libtorrent unavailable (install libtorrent-rasterbar-dev and rebuild)`. Required option errors are explicit, such as missing `torrent-path`, `save-path`, `info-hash`, DHT `host`/`port`, or malformed hex strings. Many operations perform network and filesystem I/O and may raise native libtorrent error messages. `verify-mutable-item` currently raises that it is unavailable in this build.

## Related Modules

- [`fs`](/sdk/modules/fs) for preparing torrent source/output paths.
- [`http`](/sdk/modules/http) for tracker or metadata service integration outside the libtorrent session.

## Aliases and Search Terms

Search terms: libtorrent, BitTorrent, torrent, magnet URI, DHT, bencode, resume data, peer-to-peer, rasterbar.
