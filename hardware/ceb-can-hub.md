# BIGTREETECH CEB V1.0 (CAN expansion board)

Passive CAN hub. Sits between the [CAN adapter](can-adapter.md) and both MMB
boards, and is where spare CAN capacity lives.

| | |
|---|---|
| Type | **Passive** -- no MCU, no transceiver `[sch]` |
| CAN ports | **5x XH2.54 2-pin, 1x XT30, 1x RJ11** `[vendor]` |
| Power input | DC 12-24 V, 5 pcs `[vendor]` |
| Terminator | **120 R, jumper-selectable** `[vendor]` |
| Protection | ESD chip + filter caps on **each** CAN port; TVS diodes on power inputs `[vendor]` |
| Mounting | Slots into printer aluminium extrusion `[vendor]` |

"Passive" is from the schematic: its text layer contains only PCB designators and
passives -- no STM32, no RP2040, no CAN transceiver. Nothing on this board
appears on any bus as a device; it is wiring plus protection.

## Topology

```
Pi 4B (voron.lan)
  └── USB ── CAN adapter (budgetcan gs_usb, termination OFF)
               └── CEB V1.0  (passive hub, 120R jumper)
                     ├── MMB CAN V1.0   uuid ff345a743db9   [mcu mmu]
                     └── MMB CAN V1.0   uuid d9626e1b839e   [mcu DRYBOX]
```

7 CAN connection points total. One is the feed from the adapter and two go to
the MMBs, leaving **~4 spare** for future CAN devices -- the reason this board is
here rather than a plain splice.

**Unverified:** which physical connector serves which role. The port *inventory*
is from the manual `[vendor]`; the allocation on this machine has not been
traced. Check before assuming a given socket is free.

## Termination -- verify this before blaming CAN

Three of the four devices on this bus have a selectable 120 R terminator, and a
CAN bus wants **exactly two terminated ends**:

| Device | Terminator | State |
|---|---|---|
| CAN adapter | software-switchable | **OFF** -- `termination 0 [ 0, 120 ]` `[live]` |
| CEB V1.0 | jumper | **unverified** |
| MMB (`mmu`) | selectable 120 R | **unverified** |
| MMB (`DRYBOX`) | selectable 120 R | **unverified** |

The adapter end is confirmed off, so termination is coming from the CEB and/or
the MMBs. The bus is currently error-free -- 6.2 M RX / 1.9 M TX packets with
zero across every error counter `[live]` -- so whatever the jumpers are, they
work today.

The vendor manual gives the rule plainly: *"Exercise good judgement when choosing
terminal resistors. Determine [whether the device already has a] resistor. If so,
do not use a jumper for the terminal resistor."* `[vendor]`

Worth physically tracing the four jumper states **before** adding a fifth device,
since adding a node changes which ends are the ends.

## Source

`bigtreetech/CEB`. `Hardware/BIGTREETECH CEB V1.0.pdf` is the schematic (text
layer present but only designators) and
`Hardware/BIGTREETECH CEB V1.0 User Manual.pdf` carries the specification table
above. `Hardware/CEB V1.0-Pin.png` is a bitmap -- corroboration only, per this
repo's provenance rules.
