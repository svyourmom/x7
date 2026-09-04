# Reference → Dart port map

<!-- Licensed CC BY 4.0 -->

x7's protocol code is a faithful port of the working Python tools in
[x7-vesc](https://github.com/svyourmom/x7-vesc) `tools/`.

| concept | reference (Python) | x7 (Dart) |
|---|---|---|
| CRC-16/XMODEM | `vesc-ble.py: crc16()` | `vesc_protocol.dart: crc16()` |
| frame / unframe | `frame()` / `Unframer` | `frame()` / `Unframer` |
| command ids | `COMM {...}` | `class Comm` |
| GET_VALUES parse | `values` / dump decoders | `VescClient._parseValues()` |
| terminal command | `term "<cmd>"` | `terminalCmd()` / `VescClient.terminal()` |
| wheel-lift limiter (`vwheelie_diag`) | x7-vesc `docs/04-terminal-commands.md` | `class Wheelie` (commands + reply parser) |
| CAN-RX injection (patch) | `raw "71 ...."` | `canRxInject()` / `Ebmx.*` |
| EBMX CAN ids | x7-vesc `docs/02-ebmx-can-protocol.md` | `class Ebmx` |

The VESC protocol is big-endian; CRC is over the payload only. Keep the Dart in lockstep with the
reference doc so the two stay verifiable against each other.
