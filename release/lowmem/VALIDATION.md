# Validation

Environment: Linux amd64, Go 1.24.1. Allocation benchmarks use
`GOMAXPROCS=1`; these are not measurements on the target VPS.

| Operation | Before | After |
| --- | ---: | ---: |
| Existing user/IP, no speed limit | 304 B/op, 6 allocations | 0 B/op, 0 allocations |
| Existing user/IP, with speed limit | 400 B/op, 8 allocations | 0 B/op, 0 allocations |
| Compare 1,000 users, one changed | 1,146,210 B/op | 229,651 B/op |
| Compare 10,000 users, one changed | 11,601,481 B/op | 1,835,856 B/op |

Original limiter was benchmarked before its modification. Original user diff
was extracted from HEAD into a temporary file and run with the same benchmark.
Timings are excluded because concurrent compilation and shared-host scheduling
make them unsuitable as network performance evidence. Bytes per operation are
temporary heap allocations, not resident memory saved per active connection.

Verified:

- `CGO_ENABLED=0 go build -p 4 -trimpath -ldflags='-s -w'`
- Limiter and dispatcher tests with the race detector.
- User list comparison tests, including changed records.
- Local certificate renewal calculation tests and lowmem provider rejection.
- Existing V2Ray and Trojan inbound builder tests.
- VLESS Vision + REALITY inbound configuration and preservation of Vision flow,
  using an ephemeral generated key without contacting a live panel.
- Local HTTP response forwarded through the built binary's SOCKS inbound and
  freedom outbound; graceful shutdown via SIGTERM. No panel was used.

Known limitations:

- Existing `TestBuildSS` fails with `unknown cipher method` because its fixture
  has no `CypherMethod`. Reproduced using the original controller/limiter code
  through a Go build overlay; unrelated to these changes. The fixture was not
  changed to conceal the failure.
- Only the optimized distribution is now provided. The default build omits
  the DNS provider SDKs; there is no full/lowmem build selection.
- Linux arm64 is cross-compiled; execution tests run on Linux amd64 only.
- External panel and live ACME tests were not run.
- No Debian VPS access, production traffic test, kernel change, or deployment
  was performed. Throughput, latency and RSS on the target must be measured
  before declaring the production performance requirement satisfied.

Update lowmem.2:
- Reproduced the SSpanel panic using a single-field server string.
- Regression tests cover absent/old version with modern custom_config,
  valid legacy replies, explicit legacy override, invalid ports/options,
  and suppression of private node payloads in errors (with race detection).
- Installer tests simulate success, failed restart, inactive service, and
  failed rollback startup. They verify restoration, owner-only diagnostic
  logs, and clearing the systemd start-rate limit without invoking systemd.
- The real VPS API payload is not available locally; production compatibility
  must still be checked after installation. No customer credentials are used.

Update lowmem.3:
- The supplied redacted schema identified numeric offset_port_node and boolean
  enable_vless/allow_insecure. Added a strict CustomConfig scalar decoder that
  also preserves legacy string representations.
- Race-enabled tests cover the supplied field types/version, mixed scalar
  representations and invalid values. VLESS Vision and REALITY flags remain set.
- A local mock SSpanel response now drives a real Panel.Start: fetch typed node
  JSON, create REALITY inbound, fetch/add a fixture user, bind the listener and
  shut down cleanly. Timeouts and the 1024 KiB buffer match the supplied config.
- External production connectivity and throughput still require VPS validation.
