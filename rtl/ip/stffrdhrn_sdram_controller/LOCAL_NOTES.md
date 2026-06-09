# Local Integration Notes

Source: https://github.com/stffrdhrn/sdram-controller

This directory vendors the BSD SDR SDRAM controller used as the physical
SDRAM IP core for the DE0-CV path. The original README is kept as
`README.upstream.md`.

Local patches:

- `busy <= (next != IDLE);`

Reason: the upstream `busy` only covered read/write states. The local Avalon
adapter must also see init and refresh as busy so it can assert
`za_waitrequest` and avoid losing commands.

- `busy` is now combinationally asserted while the controller is not IDLE or
  while a refresh is pending in IDLE.

Reason: a command issued in the cycle where refresh becomes pending can be
ignored by the controller because refresh has priority over read/write. The
wrapper would then wait forever for `rd_ready`. Blocking refresh-pending cycles
prevents lost SDRAM commands during long tile-loader sweeps.
