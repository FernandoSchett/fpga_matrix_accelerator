# Local Integration Notes

Source: https://github.com/stffrdhrn/sdram-controller

This directory vendors the BSD SDR SDRAM controller used as the physical
SDRAM IP core for the DE0-CV path. The original README is kept as
`README.upstream.md`.

Local patch:

- `busy <= (next != IDLE);`

Reason: the upstream `busy` only covered read/write states. The local Avalon
adapter must also see init and refresh as busy so it can assert
`za_waitrequest` and avoid losing commands.

