#!/usr/bin/env python3
"""Convert Xray JSON subscription (single object or array of profiles)
into sing-box-extended outbounds JSON: {"outbounds": [...]}.

Usage:
  curl ... | python3 xray-to-singbox.py
  python3 xray-to-singbox.py input.json
  python3 xray-to-singbox.py --no-dedup < input.json
"""

import json
import sys


def convert_xmux(xmux):
    if not isinstance(xmux, dict):
        return None
    out = {}
    mapping = {
        "maxConcurrency": "max_concurrency",
        "maxConnections": "max_connections",
        "cMaxReuseTimes": "c_max_reuse_times",
        "hMaxRequestTimes": "h_max_request_times",
        "hMaxReusableSecs": "h_max_reusable_secs",
        "hKeepAlivePeriod": "h_keep_alive_period",
    }
    for src, dst in mapping.items():
        if src in xmux and xmux[src] is not None:
            val = xmux[src]
            # sing-box-extended forbids setting both max_connections and max_concurrency > 0
            if val == 0 or val == "0" or val == "":
                continue
            out[dst] = str(val) if dst != "h_keep_alive_period" else int(val)
    return out or None


def convert_xhttp_base(settings, extra):
    base = {}
    host = settings.get("host") or extra.get("host")
    if host:
        base["host"] = host

    path = settings.get("path") or extra.get("path")
    if path:
        base["path"] = path

    headers = settings.get("headers") or extra.get("headers")
    if isinstance(headers, dict):
        cleaned = {
            k: str(v) for k, v in headers.items() if k.lower() != "host"
        }
        if cleaned:
            base["headers"] = cleaned

    x_pad = extra.get("xPaddingBytes") or settings.get("xPaddingBytes")
    base["x_padding_bytes"] = str(x_pad) if x_pad else "100-1000"

    bool_fields = {
        "noGRPCHeader": "no_grpc_header",
        "noSSEHeader": "no_sse_header",
        "xPaddingObfsMode": "x_padding_obfs_mode",
    }
    for src, dst in bool_fields.items():
        val = extra.get(src, settings.get(src))
        if isinstance(val, bool) and val:
            base[dst] = True

    range_fields = {
        "scMaxEachPostBytes": "sc_max_each_post_bytes",
        "scMinPostsIntervalMs": "sc_min_posts_interval_ms",
        "scStreamUpServerSecs": "sc_stream_up_server_secs",
        "uplinkChunkSize": "uplink_chunk_size",
    }
    for src, dst in range_fields.items():
        val = extra.get(src, settings.get(src))
        if val is None or val == "" or val == 0 or val == "0":
            continue
        base[dst] = str(val)

    int_fields = {
        "scMaxBufferedPosts": "sc_max_buffered_posts",
        "cwnd": "cwnd",
    }
    for src, dst in int_fields.items():
        val = extra.get(src, settings.get(src))
        if isinstance(val, int) and val > 0:
            base[dst] = val

    str_fields = {
        "xPaddingKey": "x_padding_key",
        "xPaddingHeader": "x_padding_header",
        "xPaddingPlacement": "x_padding_placement",
        "xPaddingMethod": "x_padding_method",
        "uplinkHTTPMethod": "uplink_http_method",
        "seqPlacement": "seq_placement",
        "seqKey": "seq_key",
        "uplinkDataPlacement": "uplink_data_placement",
        "uplinkDataKey": "uplink_data_key",
        "congestionController": "congestion_controller",
    }
    for src, dst in str_fields.items():
        val = extra.get(src, settings.get(src))
        if isinstance(val, str) and val:
            base[dst] = val

    sess_place = (
        extra.get("sessionPlacement")
        or extra.get("sessionIDPlacement")
        or settings.get("sessionPlacement")
    )
    if isinstance(sess_place, str) and sess_place:
        base["session_placement"] = sess_place

    sess_key = (
        extra.get("sessionKey")
        or extra.get("sessionIDKey")
        or settings.get("sessionKey")
    )
    if isinstance(sess_key, str) and sess_key:
        base["session_key"] = sess_key

    xmux = convert_xmux(extra.get("xmux") or settings.get("xmux"))
    if xmux:
        base["xmux"] = xmux

    return base


def convert_tls(stream):
    security = stream.get("security", "")
    if security == "reality":
        rs = stream.get("realitySettings") or {}
        tls = {
            "enabled": True,
            "reality": {
                "enabled": True,
                "public_key": rs.get("publicKey", ""),
            },
        }
        if rs.get("shortId"):
            tls["reality"]["short_id"] = rs["shortId"]
        if rs.get("serverName"):
            tls["server_name"] = rs["serverName"]
        fp = rs.get("fingerprint")
        if fp:
            tls["utls"] = {"enabled": True, "fingerprint": fp}
        return tls

    if security == "tls":
        ts = stream.get("tlsSettings") or {}
        tls = {"enabled": True}
        if ts.get("serverName"):
            tls["server_name"] = ts["serverName"]
        if ts.get("allowInsecure"):
            tls["insecure"] = True
        alpn = ts.get("alpn")
        if isinstance(alpn, list) and alpn:
            tls["alpn"] = alpn
        elif isinstance(alpn, str) and alpn:
            tls["alpn"] = [alpn]
        fp = ts.get("fingerprint")
        if fp:
            tls["utls"] = {"enabled": True, "fingerprint": fp}
        return tls

    return None


def convert_transport(stream):
    net = stream.get("network", "tcp")
    if net in ("", "tcp", "raw"):
        return None

    if net in ("xhttp", "splithttp"):
        xs = stream.get("xhttpSettings") or stream.get("splithttpSettings") or {}
        extra = xs.get("extra") if isinstance(xs.get("extra"), dict) else {}
        tr = {"type": "xhttp"}
        mode = xs.get("mode") or extra.get("mode")
        if mode:
            tr["mode"] = mode
        tr.update(convert_xhttp_base(xs, extra))

        dl = extra.get("downloadSettings")
        if isinstance(dl, dict):
            dl_xs = dl.get("xhttpSettings") or {}
            dl_extra = dl_xs.get("extra") if isinstance(dl_xs.get("extra"), dict) else {}
            dl_out = convert_xhttp_base(dl_xs, dl_extra)
            if dl.get("address"):
                dl_out["server"] = dl["address"]
            if dl.get("port"):
                dl_out["server_port"] = int(dl["port"])
            dl_tls = convert_tls(dl)
            if dl_tls:
                dl_out["tls"] = dl_tls
            if dl_out:
                tr["download"] = dl_out
        return tr

    if net == "ws":
        ws = stream.get("wsSettings") or {}
        tr = {"type": "ws"}
        if ws.get("path"):
            tr["path"] = ws["path"]
        headers = dict(ws.get("headers") or {})
        if ws.get("host") and "Host" not in headers:
            headers["Host"] = ws["host"]
        if headers:
            tr["headers"] = headers
        return tr

    if net == "grpc":
        gs = stream.get("grpcSettings") or {}
        tr = {"type": "grpc"}
        if gs.get("serviceName"):
            tr["service_name"] = gs["serviceName"]
        return tr

    if net == "httpupgrade":
        hs = stream.get("httpupgradeSettings") or {}
        tr = {"type": "httpupgrade"}
        if hs.get("host"):
            tr["host"] = hs["host"]
        if hs.get("path"):
            tr["path"] = hs["path"]
        if hs.get("headers"):
            tr["headers"] = hs["headers"]
        return tr

    return None


def convert_vless_outbound(ob, tag):
    vnext = (ob.get("settings") or {}).get("vnext") or []
    if not vnext:
        return None
    node = vnext[0]
    users = node.get("users") or []
    if not users:
        return None
    user = users[0]

    sb = {
        "type": "vless",
        "tag": tag,
        "server": node["address"],
        "server_port": int(node["port"]),
        "uuid": user["id"],
    }
    flow = user.get("flow")
    if flow:
        sb["flow"] = flow

    stream = ob.get("streamSettings") or {}
    tls = convert_tls(stream)
    if tls:
        sb["tls"] = tls

    transport = convert_transport(stream)
    if transport:
        sb["transport"] = transport

    return sb


def dedup_key(sb):
    clone = {k: v for k, v in sb.items() if k != "tag"}
    return json.dumps(clone, sort_keys=True, separators=(",", ":"))


def make_unique_tag(base_tag, used_tags):
    if base_tag not in used_tags:
        used_tags.add(base_tag)
        return base_tag
    n = 2
    while f"{base_tag} ({n})" in used_tags:
        n += 1
    tag = f"{base_tag} ({n})"
    used_tags.add(tag)
    return tag


def main():
    args = sys.argv[1:]
    dedup = True
    if "--no-dedup" in args:
        dedup = False
        args.remove("--no-dedup")

    if args and args[0] != "-":
        with open(args[0], "r", encoding="utf-8") as f:
            raw = json.load(f)
    else:
        raw = json.load(sys.stdin)

    profiles = raw if isinstance(raw, list) else [raw]

    result = []
    seen_keys = set()
    used_tags = set()

    for idx, prof in enumerate(profiles):
        if not isinstance(prof, dict):
            continue
        remark = (prof.get("remarks") or f"profile-{idx + 1}").strip()
        vless_obs = [
            ob
            for ob in (prof.get("outbounds") or [])
            if isinstance(ob, dict) and ob.get("protocol") == "vless"
        ]
        single = len(vless_obs) == 1
        for ob in vless_obs:
            orig_tag = (ob.get("tag") or "proxy").strip()
            candidate_tag = remark if single else f"{remark} [{orig_tag}]"
            sb = convert_vless_outbound(ob, candidate_tag)
            if sb is None:
                continue
            if dedup:
                key = dedup_key(sb)
                if key in seen_keys:
                    continue
                seen_keys.add(key)
            sb["tag"] = make_unique_tag(candidate_tag, used_tags)
            result.append(sb)

    json.dump({"outbounds": result}, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
