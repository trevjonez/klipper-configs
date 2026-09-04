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
  └── USB ── CAN adapter (budgetcan gs_usb, 120R jumper ON)
               └── CEB V1.0  (passive hub, 120R jumper OFF)
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
CAN bus wants **exactly two terminated ends** -- not one per board. All four
states were traced on 2026-09-04:

| Device | Terminator | State |
|---|---|---|
| CAN adapter | **physical jumper** | **ON** -- one end `[owner]` |
| CEB V1.0 | jumper | **OFF** -- mid-bus, correct `[owner]` |
| MMB (`mmu`) | selectable 120 R | **OFF** -- mid-bus, correct `[owner]` |
| MMB (`DRYBOX`) | selectable 120 R | **ON** -- other end `[owner]` |

Two terminators, at the two ends. **Measured 60 R across CANH-CANL** `[owner]`,
which is the number to confirm after any work. 120 R means one end has lost its
terminator.

Do **not** add the mmu MMB's jumper to "match" the drybox. Three terminators pull
the bus to 40 R and the transceivers can no longer drive it dominant, which
produces its own error storm.

### The adapter jumper falls off, and it took a night to find

**2026-09-04.** The CAN bus stopped working entirely during the 5 V PSU
relocation and rewire. Root cause: **the adapter's 120 R jumper had been knocked
off the PCB** and was found on the floor. One terminator instead of two, and the
bus never came back.

What made it expensive to diagnose:

* `ip` reported `termination 0` throughout -- both while the jumper was correctly
  fitted and after it fell off. That field is unbacked firmware advertising on
  this adapter; see [can-adapter.md](can-adapter.md). Enabling termination *in
  software* changed nothing and produced one non-reproducible clean reading that
  sent the investigation down a blind alley.
* The symptom shifted as the bus was disturbed -- `tx-recessive-bit-error` with
  the rail up, `bit-stuffing-error` with everything unpowered -- which reads like
  an intermittent fault rather than a missing part.
* `canbus_query` returning 0 looks like dead nodes but is also the normal result
  for healthy assigned nodes (noted at the end of this file). It cannot
  distinguish the two.

**After any mechanical work on the printer, eyeball the adapter jumper and meter
60 R before debugging anything else.** A rewire is exactly the kind of job that
dislodges it.

The one reliable signal throughout: the RX error counter pegged at 127 with TX at
0 and zero data frames. That combination means the adapter is receiving garbage
and nothing is answering -- a bus-integrity fault, not a node fault.

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
