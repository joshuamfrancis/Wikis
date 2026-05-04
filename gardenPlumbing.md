# Rainwater Tank to Garden Drip Irrigation System
## Complete Bill of Materials & Installation Guide

---

## System Overview

**Purpose:** Automated drip irrigation system using 5000L rainwater tank with pressure pump  
**Distance:** 25 meters from tank to garden  
**Pipe Turns:** 3-4 x 90° bends  
**Pump:** Ozito 800W Constant Pressure Pump (OZL-800)  
**Control:** Inline tap timer (non-WiFi)  
**Safety:** Flow sensor with pump cutoff (future installation)

---

## System Specifications

- **Main Pipe:** 25mm poly pipe (PN12.5 rated)
- **Drip Line:** 13mm Drip Eze tube
- **System Pressure:** Maximum 300 kPa (3 bar) after pressure reducer
- **Pump Output:** Max 3600 L/hour (60 L/min), 10 bar max pressure
- **Normal Flow:** 20-40 L/min during irrigation
- **Leak Threshold:** >100 L/min triggers pump cutoff

---

## Complete System Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  5000L RAINWATER TANK                                           │
│  Outlet: 25mm (1") BSP Female Thread                           │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 │ 25mm BSP threaded connection
                 ↓
        ┌────────────────────┐
        │  BALL VALVE        │ ⚠️ MANUAL ISOLATION/EMERGENCY SHUTOFF
        │  25mm (1") BSP     │
        │  Female x Male     │
        └────────┬───────────┘
                 │
                 │ 25mm BSP Male Thread
                 ↓
        ┌────────────────────────────────────┐
        │  OZITO 800W CONSTANT PRESSURE PUMP │ ⚡ WITH DRY-RUN PROTECTION
        │  Inlet: 25mm (1") BSP Female       │    + FLOW SENSOR CUTOFF
        │  Outlet: 25mm (1") BSP Male        │
        │  Max Pressure: 1MPa (10 bar)       │
        │  Power: 240V AC                    │
        └────────────┬───────────────────────┘
                     │                        ↑
                     │ 25mm BSP Male Thread   │ Power control wire
                     ↓                        │
            ┌─────────────────────────────────────────┐
            │  PUMP OUTLET ADAPTER                    │
            │  25mm BSP Male x 25mm Poly Barb         │
            │  (Philmac or Ladco)                     │
            └────────┬────────────────────────────────┘
                     │
                     │ 25mm POLY PIPE (PN12.5 or PN16 rated)
                     │ ← Ratchet clamp here
                     ↓
            ┌──────────────────────────────────────────┐
            │  🌊 ULTRASONIC FLOW SENSOR               │ 💧 LEAK DETECTION
            │  Clamp-on or Inline Type                 │    & PUMP CUTOFF
            │  25mm pipe diameter                      │
            │  Output: Relay or 4-20mA signal          │
            │                                          │
            │  ┌────────────────────────────┐          │
            │  │ FLOW CONTROLLER/RELAY      │          │
            │  │ - Normal flow: 0-60 L/min  │          │
            │  │ - Leak threshold: >100 L/min│         │
            │  │ - Cutoff relay → pump power│──────────┤
            │  └────────────────────────────┘          │
            └────────┬─────────────────────────────────┘
                     │
                     │ 25mm poly pipe (continues after sensor)
                     │ ← Ratchet clamp
                     ↓
            ═════════════════════════════
            ║   25mm POLY PIPE RUN      ║
            ║   Length: ~25-30 meters   ║
            ║   3-4 x 90° ELBOWS        ║
            ║   (25mm barbed elbows     ║
            ║    with ratchet clamps)   ║
            ═════════════════════════════
                     │
                     │ 25mm poly pipe
                     ↓
            ┌─────────────────────────┐
            │  FILTER                 │ 🔍 SEDIMENT REMOVAL
            │  Pope 19mm In-Line      │
            │  Barbed Filter          │
            │  Inlet: 25mm barb       │
            │  Outlet: 19mm barb      │
            └────────┬────────────────┘
                     │
                     │ 19mm poly pipe section (short ~30cm)
                     ↓
            ┌─────────────────────────┐
            │  PRESSURE REDUCER       │ 🛡️ LIMITS TO 300kPa (3 bar)
            │  Pope 300kPa            │
            │  3/4" BSP Female inlet  │
            │  3/4" BSP Male outlet   │
            └────────┬────────────────┘
                     │
                     │ 3/4" (20mm) BSP Male Thread
                     ↓
            ┌─────────────────────────┐
            │  NUT & TAIL ADAPTER #1  │
            │  Pope 25mm Poly         │
            │  Nut & Tail             │
            │  25mm poly barb to      │
            │  3/4" BSP Male thread   │
            └────────┬────────────────┘
                     │
                     │ 3/4" (20mm) BSP Male Thread
                     ↓
            ┌─────────────────────────────┐
            │  TAP TIMER                  │ ⏱️ SCHEDULES WATERING
            │  Holman Low Pressure        │
            │  Inlet: 3/4" BSP Female     │
            │  Outlet: 3/4" BSP Male      │
            └────────┬────────────────────┘
                     │
                     │ 3/4" (20mm) BSP Male Thread
                     ↓
            ┌─────────────────────────┐
            │  NUT & TAIL ADAPTER #2  │
            │  Pope 25mm Poly         │
            │  Nut & Tail             │
            │  3/4" BSP Female to     │
            │  25mm poly barb         │
            └────────┬────────────────┘
                     │
                     │ 25mm poly pipe (short section ~30cm)
                     │ ← Ratchet clamp
                     ↓
            ┌─────────────────────────┐
            │  REDUCING FITTING       │
            │  Pope 25mm x 13mm       │
            │  Barbed Reducing Joiner │
            │  25mm barb to 13mm barb │
            └────────┬────────────────┘
                     │
                     │ 13mm poly pipe
                     │ ← Ratchet clamp (13mm)
                     ↓
            ═════════════════════════════
            ║   13mm DRIP EZE TUBE      ║
            ║   Pope 13mm x 30m         ║
            ║   Drip Irrigation Tube    ║
            ║   + 13mm fittings (tees,  ║
            ║     elbows, end plugs)    ║
            ║   + Pope Veriflow         ║
            ║     Drippers              ║
            ═════════════════════════════
                     │
                     ↓
            🌱 GARDEN IRRIGATION 🌱
```

---

## Connection Details & Sizes

### 1. Tank to Ball Valve
- **Connection Type:** BSP threaded
- **Size:** 25mm (1 inch) Female to Male
- **Part:** Philmac 25mm Ball Valve

### 2. Ball Valve to Pump
- **Connection Type:** BSP threaded
- **Size:** 25mm (1 inch) Male thread
- **Part:** Direct threaded connection

### 3. Pump Outlet to Poly Pipe
- **Connection Type:** BSP to Poly Barb adapter
- **Size:** 25mm BSP Male to 25mm Poly Barb
- **Parts:** Ladco 12 x 25mm Click To Pipe Adapter (p3120484)
- **Clamp:** 25mm ratchet clamp

### 4. Main Poly Pipe Run
- **Pipe:** 25mm poly pipe (PN12.5 minimum)
- **Length:** 50m roll (use ~25-30m)
- **Elbows:** Pope 25mm Barbed Elbow x 4
- **Clamps:** Pope 25mm Ratchet Clamp x 10

### 5. Filter Connection
- **Inlet:** 25mm poly barb
- **Outlet:** 19mm poly barb
- **Pipe Change:** 25mm poly → 19mm poly (short section)
- **Clamps:** 25mm clamp (inlet), 19mm clamp (outlet)

### 6. Filter to Pressure Reducer
- **Connection Type:** 19mm poly to BSP adapter
- **Size:** 19mm poly barb to 3/4" BSP Female
- **Part:** Pope 19mm Nut & Tail
- **Pressure Reducer:** 3/4" BSP Female inlet / 3/4" BSP Male outlet

### 7. Pressure Reducer to Timer
- **Connection:** 25mm poly pipe short section
- **Adapters:** 2x Pope 25mm Nut & Tail
  - First: 3/4" BSP Male to 25mm poly barb
  - 25mm poly pipe: Short section (~20cm)
  - Second: 25mm poly barb to 3/4" BSP Male
- **Clamps:** 25mm ratchet clamp x 2

### 8. Timer to Drip System
- **Timer Outlet:** 3/4" BSP Male
- **Adapter:** Pope 25mm Nut & Tail (3/4" BSP Female to 25mm poly barb)
- **Clamp:** 25mm ratchet clamp

### 9. Reducer to Drip Line
- **Connection Type:** Barbed reducing fitting
- **Size:** 25mm → 19mm → 13mm (staged reduction)
- **Parts:** 
  - Pope 25mm x 19mm Barbed Reducing Joiner
  - Pope 19mm x 13mm Barbed Reducing Joiner
- **Clamps:** Appropriate size for each connection

### 10. Drip Irrigation Network
- **Main Line:** 13mm Drip Eze tube
- **Fittings:** All 13mm barbed (tees, elbows, end plugs)
- **Drippers:** Pope Veriflow Drippers (barbed into 13mm tube)
- **Clamps:** 13mm ratchet clamps throughout

---

## Pipe & Thread Sizes Summary

| Location | Size | Type |
|----------|------|------|
| Tank outlet | 25mm (1") | BSP Female |
| Ball valve | 25mm (1") | BSP F x M |
| Pump inlet | 25mm (1") | BSP Female |
| Pump outlet | 25mm (1") | BSP Male |
| Main poly run | 25mm | Poly pipe (PN12.5+) |
| Filter inlet | 25mm | Poly barb |
| Filter to PR | 19mm | Poly pipe (short) |
| Pressure reducer | 3/4" (20mm) | BSP F x M |
| Timer | 3/4" (20mm) | BSP F x M |
| Timer to reducer | 25mm | Poly pipe (short) |
| Drip line | 13mm | Poly pipe |

---

## Complete Bill of Materials - In Installation Sequence

### SECTION 1: TANK TO PUMP

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 1.1 | Philmac 25mm x 1" Ball Valve | 1 | p4813xxx | $37.40 | **$37.40** | Manual isolation valve |
| 1.2 | Thread Seal Tape (PTFE) | 1 | Generic | $3.00 | **$3.00** | For BSP threads |

**Subtotal Section 1: $40.40**

---

### SECTION 2: PUMP

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 2.1 | Ozito 800W Constant Pressure Pump | 1 | OZL-800 | $199.00 | **$199.00** | Already owned |

**Subtotal Section 2: $199.00** *(Already owned)*

---

### SECTION 3: PUMP OUTLET CONNECTION

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 3.1 | Ladco 12 x 25mm Click To Pipe Hose Fitting Adapter | 1 | p3120484 | $5.49 | **$5.49** | 25mm BSP Male to 25mm poly barb |
| 3.2 | Pope 25mm Single Poly Ratchet Clamp | 1 | p3126992 | $0.49 | **$0.49** | Secure barb connection |

**Subtotal Section 3: $5.98**

---

### SECTION 4: FLOW SENSOR (FUTURE INSTALLATION)

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 4.1 | Clamp-on Ultrasonic Flow Sensor 25mm | 1 | TBD - Online | $250.00 | **$250.00** | To be added later |
| 4.2 | 12V DC Power Supply (2A) | 1 | TBD - Online | $25.00 | **$25.00** | For flow sensor |
| 4.3 | 10A Relay Module (240V AC) | 1 | TBD - Online | $30.00 | **$30.00** | Pump control relay |
| 4.4 | Weatherproof Enclosure (IP65) | 1 | TBD - Online | $25.00 | **$25.00** | Electronics housing |
| 4.5 | Electrical Wire 2.5mm² (10m) | 1 | Generic | $15.00 | **$15.00** | Pump power control |
| 4.6 | Waterproof Cable Connectors | 5 | Generic | $10.00 | **$10.00** | Electrical connections |

**Subtotal Section 4: $355.00** *(FUTURE - NOT PURCHASED NOW)*

---

### SECTION 5: MAIN POLY PIPE RUN (25m to Garden)

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 5.1 | Holman 25mm x 50m Black Poly Pipe | 1 | p3120670 | $50.92 | **$50.92** | PN12.5 rated, use ~30m |
| 5.2 | Pope 25mm Single Poly Barbed Elbow | 4 | p3127029 | $1.35 | **$5.40** | For 90° turns |
| 5.3 | Pope 25mm Single Poly Ratchet Clamp | 10 | p3126992 | $0.49 | **$4.90** | 2 per elbow + spares |
| 5.4 | Pope 25mm Barbed Joiner - Single | 2 | Generic | $1.10 | **$2.20** | For joining pipe sections |

**Subtotal Section 5: $63.42**

---

### SECTION 6: FILTER

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 6.1 | Pope 19mm In-Line Barbed Filter | 1 | p3127273 | $12.00 | **$12.00** | Sediment filtration |
| 6.2 | Pope 19mm Locking Clamps - 25 Pack | 1 | p3130453 | $8.38 | **$8.38** | For filter connections |
| 6.3 | Holman 19mm x 1m Black Poly Pipe | 1 | Generic | $3.00 | **$3.00** | Short section filter to PR |

**Subtotal Section 6: $23.38**

---

### SECTION 7: PRESSURE REDUCER

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 7.1 | Pope 300kPa Pressure Reducer | 1 | p3121926 | $15.79 | **$15.79** | Reduces to 3 bar max |
| 7.2 | Pope 19mm Nut And Tail | 1 | Generic | $3.00 | **$3.00** | 19mm poly to 3/4" BSP |

**Subtotal Section 7: $18.79**

---

### SECTION 8: TIMER CONNECTION

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 8.1 | Holman 25mm x 1m Black Poly Pipe | 1 | Generic | $2.50 | **$2.50** | Short sections for timer |
| 8.2 | Pope 25mm Poly Nut And Tail | 2 | Generic | $5.62 | **$11.24** | Before & after timer |
| 8.3 | Pope 25mm Single Poly Ratchet Clamp | 2 | p3126992 | $0.49 | **$0.98** | Secure nut & tail |

**Subtotal Section 8: $14.72**

---

### SECTION 9: TAP TIMER

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 9.1 | Holman Electronic Low Pressure Tap Timer | 1 | p3120874 | $64.48 | **$64.48** | Designed for rainwater tanks |
| 9.2 | AAA Batteries (2 pack) | 1 | Generic | $4.00 | **$4.00** | Timer power |

**Subtotal Section 9: $68.48**

---

### SECTION 10: TRANSITION TO DRIP SYSTEM

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 10.1 | Pope 25 x 19mm Barbed Reducing Joiner - Single | 1 | Generic | $1.29 | **$1.29** | 25mm to 19mm transition |
| 10.2 | Pope 19 x 13mm Barbed Reducing Joiner | 1 | Generic | $1.20 | **$1.20** | 19mm to 13mm transition |
| 10.3 | Pope 13mm Locking Clamp - 25 Pack | 1 | Generic | $7.09 | **$7.09** | For 13mm connections |

**Subtotal Section 10: $9.58**

---

### SECTION 11: DRIP IRRIGATION SYSTEM

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 11.1 | Pope 13mm x 30m Drip Eze Drip Irrigation Tube | 1 | p3120300 | $35.00 | **$35.00** | 2L/hr @ 100kPa |
| 11.2 | Pope Veriflow Dripper - 25 Pack | 1 | Generic | $31.50 | **$31.50** | Pressure compensating |
| 11.3 | Pope 13mm Single Barbed Poly Tee | 5 | Generic | $0.70 | **$3.50** | Branch connections |
| 11.4 | Pope 13mm Single Poly Barbed Elbow | 5 | Generic | $0.64 | **$3.20** | Direction changes |
| 11.5 | Pope 13mm Single Barbed End Plug | 3 | Generic | $0.36 | **$1.08** | Line termination |

**Subtotal Section 11: $74.28**

---

### SECTION 12: OPTIONAL/RECOMMENDED ADDITIONS

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes |
|-----|------|-----|-------------|------------|-------|-------|
| 12.1 | GARDENA AquaCount Water Meter | 1 | p0737647 | $51.98 | **$51.98** | Optional: Flow monitoring |
| 12.2 | Pope Universal Poly Pipe Cutter | 1 | Generic | $19.76 | **$19.76** | Recommended: Clean cuts |
| 12.3 | Extra 25mm Ratchet Clamps (25 pack) | 1 | Generic | $9.75 | **$9.75** | Spares recommended |
| 12.4 | Extra 13mm Locking Clamps (25 pack) | 1 | Generic | $7.09 | **$7.09** | Spares recommended |

**Subtotal Section 12: $88.58** *(OPTIONAL)*

---

## Cost Summary

### Essential Components (Purchase Now):

| Section | Description | Subtotal |
|---------|-------------|----------|
| Section 1 | Tank to Pump | $40.40 |
| Section 2 | Pump | *$0.00* (Already owned) |
| Section 3 | Pump Outlet Connection | $5.98 |
| Section 5 | Main Poly Pipe Run | $63.42 |
| Section 6 | Filter | $23.38 |
| Section 7 | Pressure Reducer | $18.79 |
| Section 8 | Timer Connection | $14.72 |
| Section 9 | Tap Timer | $68.48 |
| Section 10 | Transition to Drip | $9.58 |
| Section 11 | Drip Irrigation | $74.28 |
| **ESSENTIAL TOTAL** | | **$319.03** |

### Recommended Additions:

| Section | Description | Subtotal |
|---------|-------------|----------|
| Section 12 | Optional Tools & Spares | $88.58 |
| **WITH RECOMMENDED** | | **$407.61** |

### Future Additions:

| Section | Description | Subtotal |
|---------|-------------|----------|
| Section 4 | Flow Sensor System | $355.00 |
| **COMPLETE SYSTEM** | | **$762.61** |

---

## Flow Sensor System Details

### Flow Sensor Electrical Control Diagram

```
┌─────────────┐
│   240V AC   │
│   MAINS     │
└──────┬──────┘
       │
       │ Active (Live)
       ↓
┌──────────────────────────────┐
│  FLOW SENSOR RELAY CONTROL   │
│                              │
│  ┌────────────────────────┐  │
│  │ Relay (Normally Closed)│  │──┐ Controlled by
│  │ Contact Rating:        │  │  │ flow sensor
│  │ 10A @ 240V AC minimum  │  │  │
│  └────────────────────────┘  │  │
└──────────────┬───────────────┘  │
               │                  │
               ↓                  │
      ┌────────────────┐          │
      │  OZITO 800W    │          │ Signal from
      │  PUMP          │          │ ultrasonic
      │  (10A max)     │          │ flow sensor
      └────────┬───────┘          │
               │                  │
               ↓                  │
         Neutral ←────────────────┘
               │
               ↓
         Earth/Ground
```

### Flow Sensor Logic:
- **Normal Operation (0-60 L/min):** Relay CLOSED → Pump runs
- **Leak Detected (>100 L/min):** Relay OPENS → Pump stops
- **Manual Reset:** Reset button to restart after leak fixed

### Flow Sensor Installation Requirements:

1. **Straight pipe section:** Minimum 500mm straight section after pump
2. **No bends/elbows:** Within 500mm upstream or downstream of sensor
3. **Pipe must be FULL:** Horizontal installation or upward flow
4. **Sensor orientation:** Follow manufacturer specs (usually clamps on side of pipe)

### Recommended Flow Thresholds:

**Normal Operation:**
- Drip irrigation: 20-40 L/min typical
- Maximum expected: 60 L/min (if all drippers open)

**Alarm/Cutoff Thresholds:**
- **Warning Alarm:** >80 L/min (possible minor leak)
- **Pump Cutoff:** >100 L/min (major leak/blowout)

---

## Installation Sequence Checklist

```
□ 1. Install ball valve on tank outlet
□ 2. Connect pump to ball valve
□ 3. Install pump outlet adapter (BSP to poly barb)
□ 4. Connect 25mm poly pipe to pump adapter with clamp
□ 5. [FUTURE: Install flow sensor on straight pipe section]
□ 6. Run 25mm poly pipe to garden (install elbows as needed)
□ 7. Install filter at garden end
□ 8. Connect 19mm poly pipe from filter to pressure reducer
□ 9. Install pressure reducer
□ 10. Connect 25mm poly pipe section after pressure reducer
□ 11. Install first nut & tail adapter (poly to BSP)
□ 12. Install tap timer
□ 13. Install second nut & tail adapter (BSP to poly)
□ 14. Connect 25mm poly pipe section
□ 15. Install reducing fittings (25mm → 19mm → 13mm)
□ 16. Layout and connect 13mm drip tube network
□ 17. Install tees, elbows, and drippers as needed
□ 18. Install end plugs on all termination points
□ 19. Pressure test system before burying pipe
□ 20. Program tap timer for watering schedule
```

---

## Shopping List - Organized for Bunnings

### IRRIGATION AISLE:
- Holman 25mm x 50m Black Poly Pipe (p3120670) - 1
- Holman 25mm x 1m Black Poly Pipe - 1
- Holman 19mm x 1m Black Poly Pipe - 1
- Pope 25mm Single Poly Barbed Elbow (p3127029) - 4
- Pope 25mm Barbed Joiner - Single - 2
- Pope 25mm Poly Nut And Tail - 2
- Pope 25mm Single Poly Ratchet Clamp (p3126992) - 15+
- Pope 19mm In-Line Barbed Filter (p3127273) - 1
- Pope 19mm Locking Clamps - 25 Pack (p3130453) - 1
- Pope 19mm Nut And Tail - 1
- Pope 300kPa Pressure Reducer (p3121926) - 1
- Pope 13mm x 30m Drip Eze Tube (p3120300) - 1
- Pope Veriflow Dripper - 25 Pack - 1
- Pope 13mm Single Barbed Poly Tee - 5
- Pope 13mm Single Poly Barbed Elbow - 5
- Pope 13mm Single Barbed End Plug - 3
- Pope 13mm Locking Clamp - 25 Pack - 1
- Pope 25 x 19mm Barbed Reducing Joiner - 1
- Pope 19 x 13mm Barbed Reducing Joiner - 1
- Holman Electronic Low Pressure Tap Timer (p3120874) - 1

### GARDEN HOSES & SPRINKLERS AISLE:
- Ladco 12 x 25mm Click To Pipe Adapter (p3120484) - 1
- GARDENA AquaCount Water Meter (p0737647) - 1 *(Optional)*

### PLUMBING AISLE:
- Philmac 25mm Ball Valve - 1
- Thread Seal Tape (PTFE) - 1 roll

### TOOLS:
- Pope Universal Poly Pipe Cutter - 1 *(Recommended)*

### ELECTRICAL (for batteries):
- AAA Batteries 2-pack - 1

---

## Safety Features

### Built-in Protection:
1. **Dry Run Protection:** Ozito pump has built-in thermal overload protection
2. **Overpressure Protection:** Pope 300kPa pressure reducer limits system to 3 bar
3. **Manual Shutoff:** Ball valve at pump for emergency isolation
4. **Scheduled Control:** Tap timer limits daily run time

### Future Addition - Flow Sensor:
1. **Leak Detection:** Ultrasonic flow sensor monitors consumption
2. **Automatic Shutoff:** Relay cuts pump power if flow exceeds 100 L/min
3. **Protection Against:**
   - Pipe blowouts
   - Joint failures
   - Major leaks
   - System damage

---

## Installation Best Practices

### Pipe Installation:
1. **Burial depth:** 300mm minimum to protect from UV and damage
2. **Straight sections:** Use gradual bends where possible instead of 90° elbows
3. **Support:** Support above-ground sections every 1-2 meters
4. **Marking:** Mark buried pipe route to prevent accidental damage

### Connection Best Practices:
1. **Clean cuts:** Use pipe cutter, not knife, for clean perpendicular cuts
2. **Barb insertion:** Heat pipe end in hot water for easier barb insertion
3. **Clamp position:** Position clamps 5-10mm from pipe end
4. **Thread seal:** Use 3-4 wraps of PTFE tape on all BSP threads
5. **Hand tight:** Don't over-tighten threaded connections

### Testing:
1. **Pressure test:** Run system at full pressure for 30 minutes
2. **Check all joints:** Inspect every connection for leaks
3. **Fix issues:** Repair any leaks before burying pipe
4. **Flow test:** Verify even distribution across all drippers

---

## Maintenance Schedule

### Monthly:
- Check timer battery level
- Inspect visible connections for leaks
- Verify drippers are working evenly

### Quarterly:
- Clean inline filter (remove and rinse mesh)
- Check pressure reducer operation
- Inspect pipe for damage

### Annually:
- Replace timer batteries
- Full system pressure test
- Clean all drippers
- Inspect buried pipe sections (if accessible)

### As Needed:
- Adjust timer schedule seasonally
- Add/relocate drippers for new plants
- Clear blocked emitters

---

## Troubleshooting Guide

### Problem: No water flow
**Possible Causes:**
- Timer not programmed or battery dead
- Pump not running (check power)
- Ball valve closed
- Blocked filter

**Solutions:**
1. Check timer display and batteries
2. Verify pump power and operation
3. Open ball valve fully
4. Clean filter

### Problem: Uneven dripper flow
**Possible Causes:**
- Insufficient pressure (check pressure reducer)
- Blocked drippers
- Pipe too small for number of drippers
- Air in lines

**Solutions:**
1. Verify pressure reducer set to 300kPa
2. Clean or replace blocked drippers
3. Reduce number of drippers or increase pipe size
4. Flush system to remove air

### Problem: Low system pressure
**Possible Causes:**
- Low tank water level
- Pump not reaching full pressure
- Leaks in system
- Filter heavily clogged

**Solutions:**
1. Check tank level
2. Check pump operation
3. Inspect all connections for leaks
4. Clean or replace filter

### Problem: Pump runs continuously
**Possible Causes:**
- Major leak in system
- Pump pressure switch failure
- Timer stuck open

**Solutions:**
1. Close ball valve and check if pump stops
2. If pump stops, locate and repair leak
3. If pump continues, check pump pressure switch
4. Check timer operation

---

## Winter Preparation (if applicable)

### Before Freezing Temperatures:
1. Drain all pipes and components
2. Remove and store timer indoors
3. Leave ball valve partially open
4. Disconnect pump if extended freeze expected
5. Blow out lines with compressed air (optional)

### Spring Startup:
1. Inspect all connections
2. Reinstall timer with fresh batteries
3. Slowly refill system
4. Check for leaks
5. Verify all drippers working

---

## Notes on Part Numbers

1. **"Generic" entries:** These are standard items where specific Bunnings part numbers weren't available. Ask staff for equivalent Pope/Holman products.

2. **Alternative suppliers for flow sensor (Section 4):**
   - eBay Australia
   - AliExpress
   - RS Components Australia
   - Element14 Australia
   - Industrial automation suppliers

3. **Substitutions allowed:**
   - Pope ↔ Holman ↔ K-Rain (similar quality)
   - Individual clamps ↔ 25-packs (buy packs, more economical)

4. **Thread tape:** Buy quality PTFE tape rated for water applications

---

## Recommended Phased Implementation

### Phase 1: Basic System (Install Now)
**Cost:** ~$320
- Install system without flow sensor
- Use pump's built-in thermal protection
- Manual monitoring with daily checks
- Ball valve for emergency shutoff

### Phase 2: Flow Monitoring (3-6 months later)
**Additional Cost:** ~$355
- Add clamp-on ultrasonic flow sensor
- Install relay control for pump cutoff
- Set threshold at 100 L/min
- Allows observation of normal flow patterns first

**Benefits of Phased Approach:**
✅ Gets system running immediately
✅ Allows observation of normal flow patterns
✅ Spreads cost over time
✅ Easy to retrofit sensor (clamp-on design)

---

## Document Information

**Created:** 2026
**System Type:** Residential rainwater tank drip irrigation
**Location:** Brisbane, Queensland, AU
**Pump Model:** Ozito 800W Constant Pressure Pump (OZL-800)
**Primary Retailer:** Bunnings Australia

---

## Important Safety Warnings

⚠️ **ELECTRICAL SAFETY:**
- All electrical work must comply with AS/NZS 3000 (Australian/New Zealand Wiring Rules)
- Use a licensed electrician for pump power and flow sensor relay installation
- Install RCD (residual current device) protection on pump circuit
- Keep all electrical components dry and in weatherproof enclosures

⚠️ **WATER QUALITY:**
- This system is designed for garden irrigation only
- Rainwater from this system is NOT suitable for drinking
- Do not connect to potable water supply

⚠️ **PRESSURE:**
- Never exceed maximum pressure ratings of components
- Always install pressure reducer as specified
- Test system before burying pipes

⚠️ **MAINTENANCE:**
- Regular filter cleaning essential to prevent system damage
- Monitor water levels to prevent pump dry-running
- Inspect connections regularly for leaks

---

*End of Document*
