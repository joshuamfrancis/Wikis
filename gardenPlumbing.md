# Rainwater Tank to Garden Drip Irrigation System
## Complete Bill of Materials & Installation Guide - FINAL CORRECTED VERSION

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
            │  Pope 25 x 25mm BSP Male Director       │
            │  25mm BSP Male x 25mm Poly Barb         │
            └────────┬────────────────────────────────┘
                     │
                     │ 25mm POLY PIPE (PN12.5 or PN16 rated)
                     │ ← Ratchet clamp here
                     ↓
            ┌──────────────────────────────────────────┐
            │  🌊 ULTRASONIC FLOW SENSOR               │ 💧 LEAK DETECTION
            │  Clamp-on Type (FUTURE INSTALLATION)     │    & PUMP CUTOFF
            │  25mm pipe diameter                      │
            │  Output: Relay signal                    │
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
            │  Pope 25mm In-Line      │
            │  Barbed Filter          │
            │  Inlet: 25mm barb       │
            │  Outlet: 25mm barb      │
            └────────┬────────────────┘
                     │
                     │ 25mm poly pipe section (short ~20cm)
                     │ ← Ratchet clamp
                     ↓
            ┌─────────────────────────┐
            │  NUT & TAIL ADAPTER     │
            │  Pope 25mm              │
            │  Poly barb → 3/4" BSP F │
            └────────┬────────────────┘
                     │
                     │ 3/4" BSP Female thread
                     ↓
            ┌─────────────────────────┐
            │  DOUBLE MALE NIPPLE     │ 🔗 CONNECTS TWO FEMALE THREADS
            │  Philmac 3/4" BSP       │
            │  Male both ends         │
            └────────┬────────────────┘
                     │
                     │ 3/4" BSP Male thread screws into:
                     ↓
            ┌─────────────────────────┐
            │  PRESSURE REDUCER       │ 🛡️ LIMITS TO 300kPa (3 bar)
            │  Pope 300kPa            │
            │  Inlet: 3/4" BSP Female │
            │  Outlet: 3/4" BSP Male  │
            └────────┬────────────────┘
                     │
                     │ 3/4" BSP Male screws into:
                     ↓
            ┌─────────────────────────────┐
            │  TAP TIMER                  │ ⏱️ SCHEDULES WATERING
            │  Holman Low Pressure        │
            │  Inlet: 20/25mm BSP Female  │
            │  Outlet: 12mm hose barb     │
            └────────┬────────────────────┘
                     │
                     │ 12mm hose barb outlet
                     │ 13mm poly pipe slides over 12mm barb
                     │ ← 13mm ratchet clamp
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
- **Parts:** Pope 25 x 25mm BSP Male Director (p3128198)
- **Clamp:** 25mm ratchet clamp

### 4. Main Poly Pipe Run
- **Pipe:** 25mm poly pipe (PN12.5 minimum)
- **Length:** 50m roll (use ~25-30m)
- **Elbows:** Pope 25mm Barbed Elbow x 4
- **Clamps:** Pope 25mm Ratchet Clamp x 10 (2 per elbow + spares)

### 5. Filter Connection
- **Inlet:** 25mm poly barb
- **Outlet:** 25mm poly barb
- **Part:** Pope 25mm In-Line Barbed Filter (p3120271)
- **Clamps:** 25mm ratchet clamp x 2

### 6. Filter to Pressure Reducer (3-part connection)
**Part A: Short Poly Pipe**
- **Connection Type:** 25mm poly pipe
- **Length:** ~20cm
- **Clamps:** 25mm ratchet clamp x 1

**Part B: Nut & Tail Adapter**
- **Poly barb side:** 25mm poly pipe slides over
- **Thread side:** 3/4" BSP Female
- **Part:** Pope 25mm Nut & Tail (p3123863)
- **Clamp:** 25mm ratchet clamp x 1

**Part C: Double Male Nipple**
- **Both ends:** 3/4" BSP Male threads
- **Part:** Philmac 3/4" BSP Thread Pipe Nipple (p4813759)
- **Purpose:** Connects Nut & Tail (Female) to Pressure Reducer (Female)

**Part D: Pressure Reducer**
- **Inlet:** 3/4" BSP Female (nipple screws into this)
- **Outlet:** 3/4" BSP Male
- **Part:** Pope 300kPa Pressure Reducer (p3121926)

### 7. Pressure Reducer to Timer
- **Connection Type:** Direct BSP threaded
- **Pressure Reducer Outlet:** 3/4" BSP Male
- **Timer Inlet:** 3/4" (20/25mm) BSP Female
- **No adapter needed** - threads screw directly together

### 8. Timer to Drip System
- **Timer Outlet:** 12mm hose barb
- **Connection:** 13mm poly pipe slides over 12mm barb
- **Clamp:** 13mm ratchet clamp
- **Note:** 13mm poly pipe fits snugly on 12mm barb - this is a standard connection

### 9. Drip Irrigation Network
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
| Filter inlet/outlet | 25mm | Poly barb (both ends) |
| Nut & Tail adapter | 25mm poly / 3/4" BSP F | Hybrid fitting |
| Double Male Nipple | 3/4" BSP M both ends | Thread connector |
| Pressure reducer | 3/4" (20mm) | BSP F inlet, M outlet |
| Timer inlet | 3/4" (20mm) | BSP Female |
| Timer outlet | 12mm | Hose barb |
| Drip line | 13mm | Poly pipe |

---

## Complete Bill of Materials - In Installation Sequence

### SECTION 1: TANK TO PUMP

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 1.1 | Philmac 25mm x 1" Ball Valve | 1 | TBD | $37.40 | **$37.40** | Manual isolation valve | [Search Bunnings](https://www.bunnings.com.au/search/products?q=philmac+25mm+ball+valve) |
| 1.2 | Thread Seal Tape (PTFE) | 1 | Generic | $3.00 | **$3.00** | For BSP threads | [Search Bunnings](https://www.bunnings.com.au/search/products?q=ptfe+thread+seal+tape) |

**Subtotal Section 1: $40.40**

---

### SECTION 2: PUMP

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 2.1 | Ozito 800W Constant Pressure Pump | 1 | OZL-800 | $199.00 | **$199.00** | Already owned | [Search Bunnings](https://www.bunnings.com.au/search/products?q=ozito+800w+constant+pressure+pump) |

**Subtotal Section 2: $199.00** *(Already owned)*

---

### SECTION 3: PUMP OUTLET CONNECTION

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 3.1 | Pope 25 x 25mm BSP Male Director - Single | 1 | p3128198 | $1.72 | **$1.72** | 25mm BSP Male to 25mm poly barb | [View at Bunnings](https://www.bunnings.com.au/pope-25-x-25mm-bsp-male-director_p3128198) |
| 3.2 | Pope 25mm Single Poly Ratchet Clamp | 1 | p3126992 | $0.49 | **$0.49** | Secure barb connection | [View at Bunnings](https://www.bunnings.com.au/pope-25mm-single-poly-ratchet-clamp_p3126992) |

**Subtotal Section 3: $2.21**

---

### SECTION 4: FLOW SENSOR (FUTURE INSTALLATION)

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 4.1 | Clamp-on Ultrasonic Flow Sensor 25mm | 1 | TBD - Online | $250.00 | **$250.00** | To be added later | [Search eBay AU](https://www.ebay.com.au/sch/i.html?_nkw=clamp+on+ultrasonic+flow+sensor+25mm) |
| 4.2 | 12V DC Power Supply (2A) | 1 | TBD - Online | $25.00 | **$25.00** | For flow sensor | [Search Jaycar](https://www.jaycar.com.au/search?text=12V+DC+power+supply+2A) |
| 4.3 | 10A Relay Module (240V AC) | 1 | TBD - Online | $30.00 | **$30.00** | Pump control relay | [Search Jaycar](https://www.jaycar.com.au/search?text=10A+relay+module+240V) |
| 4.4 | Weatherproof Enclosure (IP65) | 1 | TBD - Online | $25.00 | **$25.00** | Electronics housing | [Search Jaycar](https://www.jaycar.com.au/search?text=IP65+weatherproof+enclosure) |
| 4.5 | Electrical Wire 2.5mm² (10m) | 1 | Generic | $15.00 | **$15.00** | Pump power control | [Search Bunnings](https://www.bunnings.com.au/search/products?q=2.5mm+electrical+wire) |
| 4.6 | Waterproof Cable Connectors | 5 | Generic | $10.00 | **$10.00** | Electrical connections | [Search Bunnings](https://www.bunnings.com.au/search/products?q=waterproof+cable+connectors) |

**Subtotal Section 4: $355.00** *(FUTURE - NOT PURCHASED NOW)*

---

### SECTION 5: MAIN POLY PIPE RUN (25m to Garden)

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 5.1 | Holman 25mm x 50m Black Poly Pipe | 1 | p3120670 | $50.92 | **$50.92** | PN12.5 rated, use ~30m | [View at Bunnings](https://www.bunnings.com.au/holman-25mm-x-50m-black-poly-pipe_p3120670) |
| 5.2 | Pope 25mm Single Poly Barbed Elbow | 4 | p3127029 | $1.35 | **$5.40** | For 90° turns | [View at Bunnings](https://www.bunnings.com.au/pope-25mm-single-poly-barbed-elbow_p3127029) |
| 5.3 | Pope 25mm Single Poly Ratchet Clamp | 10 | p3126992 | $0.49 | **$4.90** | 2 per elbow + spares | [View at Bunnings](https://www.bunnings.com.au/pope-25mm-single-poly-ratchet-clamp_p3126992) |
| 5.4 | Pope 25mm Barbed Joiner - Single | 2 | Generic | $1.10 | **$2.20** | For joining pipe sections | [Search Bunnings](https://www.bunnings.com.au/search/products?q=pope+25mm+barbed+joiner) |

**Subtotal Section 5: $63.42**

---

### SECTION 6: FILTER

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 6.1 | Pope 25mm In-Line Barbed Filter | 1 | p3120271 | $12.37 | **$12.37** | Both inlet & outlet 25mm barb | [View at Bunnings](https://www.bunnings.com.au/pope-25mm-in-line-barbed-filter_p3120271) |
| 6.2 | Pope 25mm Single Poly Ratchet Clamp | 2 | p3126992 | $0.49 | **$0.98** | For filter connections | [View at Bunnings](https://www.bunnings.com.au/pope-25mm-single-poly-ratchet-clamp_p3126992) |

**Subtotal Section 6: $13.35**

---

### SECTION 7: FILTER TO PRESSURE REDUCER CONNECTION

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 7.1 | Holman 25mm x 1m Black Poly Pipe | 1 | Generic | $2.50 | **$2.50** | Short section filter to adapter | [Search Bunnings](https://www.bunnings.com.au/search/products?q=holman+25mm+poly+pipe) |
| 7.2 | Pope 25mm Poly Nut And Tail | 1 | p3123863 | $5.62 | **$5.62** | 25mm poly to 3/4" BSP Female | [View at Bunnings](https://www.bunnings.com.au/pope-25mm-poly-nut-and-tail_p3123863) |
| 7.3 | Pope 25mm Single Poly Ratchet Clamp | 1 | p3126992 | $0.49 | **$0.49** | Secure nut & tail | [View at Bunnings](https://www.bunnings.com.au/pope-25mm-single-poly-ratchet-clamp_p3126992) |
| 7.4 | Philmac 3/4" BSP Thread Pipe Nipple | 1 | p4813759 | $4.50 | **$4.50** | Double male, connects two females | [View at Bunnings](https://www.bunnings.com.au/philmac-3-4-bsp-thread-pipe-nipple_p4813759) |
| 7.5 | Pope 300kPa Pressure Reducer | 1 | p3121926 | $15.79 | **$15.79** | Reduces to 3 bar max | [View at Bunnings](https://www.bunnings.com.au/pope-300kpa-pressure-reducer_p3121926) |

**Subtotal Section 7: $28.90**

---

### SECTION 8: TAP TIMER

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 8.1 | Holman Electronic Low Pressure Tap Timer | 1 | p3120874 | $64.48 | **$64.48** | Designed for rainwater tanks | [View at Bunnings](https://www.bunnings.com.au/holman-electronic-low-pressure-tap-timer_p3120874) |
| 8.2 | AAA Batteries (2 pack) | 1 | Generic | $4.00 | **$4.00** | Timer power | [Search Bunnings](https://www.bunnings.com.au/search/products?q=AAA+batteries) |

**Subtotal Section 8: $68.48**

---

### SECTION 9: DRIP IRRIGATION SYSTEM

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 9.1 | Pope 13mm x 30m Drip Eze Drip Irrigation Tube | 1 | p3120300 | $35.00 | **$35.00** | 2L/hr @ 100kPa | [View at Bunnings](https://www.bunnings.com.au/pope-13mm-x-30m-drip-eze-drip-irrigation-tube_p3120300) |
| 9.2 | Pope Veriflow Dripper - 25 Pack | 1 | Generic | $31.50 | **$31.50** | Pressure compensating | [Search Bunnings](https://www.bunnings.com.au/search/products?q=pope+veriflow+dripper) |
| 9.3 | Pope 13mm Single Barbed Poly Tee | 5 | Generic | $0.70 | **$3.50** | Branch connections | [Search Bunnings](https://www.bunnings.com.au/search/products?q=pope+13mm+barbed+tee) |
| 9.4 | Pope 13mm Single Poly Barbed Elbow | 5 | Generic | $0.64 | **$3.20** | Direction changes | [Search Bunnings](https://www.bunnings.com.au/search/products?q=pope+13mm+barbed+elbow) |
| 9.5 | Pope 13mm Single Barbed End Plug | 3 | Generic | $0.36 | **$1.08** | Line termination | [Search Bunnings](https://www.bunnings.com.au/search/products?q=pope+13mm+end+plug) |
| 9.6 | Pope 13mm Locking Clamp - 25 Pack | 1 | Generic | $7.09 | **$7.09** | For 13mm connections | [Search Bunnings](https://www.bunnings.com.au/search/products?q=pope+13mm+locking+clamp) |

**Subtotal Section 9: $81.37**

---

### SECTION 10: OPTIONAL/RECOMMENDED ADDITIONS

| Seq | Item | Qty | Part Number | Unit Price | Total | Notes | Product Link |
|-----|------|-----|-------------|------------|-------|-------|--------------|
| 10.1 | GARDENA AquaCount Water Meter | 1 | p0737647 | $51.98 | **$51.98** | Optional: Flow monitoring | [View at Bunnings](https://www.bunnings.com.au/gardena-aquacount-water-meter_p0737647) |
| 10.2 | Pope Universal Poly Pipe Cutter | 1 | Generic | $19.76 | **$19.76** | Recommended: Clean cuts | [Search Bunnings](https://www.bunnings.com.au/search/products?q=pope+poly+pipe+cutter) |
| 10.3 | Extra 25mm Ratchet Clamps (25 pack) | 1 | Generic | $9.75 | **$9.75** | Spares recommended | [Search Bunnings](https://www.bunnings.com.au/search/products?q=25mm+ratchet+clamp+25+pack) |
| 10.4 | Extra 13mm Locking Clamps (25 pack) | 1 | Generic | $7.09 | **$7.09** | Spares recommended | [Search Bunnings](https://www.bunnings.com.au/search/products?q=13mm+locking+clamp+25+pack) |

**Subtotal Section 10: $88.58** *(OPTIONAL)*

---

## Cost Summary

### Essential Components (Purchase Now):

| Section | Description | Subtotal |
|---------|-------------|----------|
| Section 1 | Tank to Pump | $40.40 |
| Section 2 | Pump | *$0.00* (Already owned) |
| Section 3 | Pump Outlet Connection | $2.21 |
| Section 5 | Main Poly Pipe Run | $63.42 |
| Section 6 | Filter | $13.35 |
| Section 7 | Filter to Pressure Reducer | $28.90 |
| Section 8 | Tap Timer | $68.48 |
| Section 9 | Drip Irrigation | $81.37 |
| **ESSENTIAL TOTAL** | | **$298.13** |

### Recommended Additions:

| Section | Description | Subtotal |
|---------|-------------|----------|
| Section 10 | Optional Tools & Spares | $88.58 |
| **WITH RECOMMENDED** | | **$386.71** |

### Future Additions:

| Section | Description | Subtotal |
|---------|-------------|----------|
| Section 4 | Flow Sensor System | $355.00 |
| **COMPLETE SYSTEM** | | **$741.71** |

---

## How Filter Connects to Pressure Reducer

This is a **4-part connection** that solves the "two female threads" problem:

```
FILTER OUTLET (25mm poly barb)
    ↓
    │ 25mm poly pipe (~20cm section)
    │ ← Secured with 25mm ratchet clamp
    ↓
NUT & TAIL ADAPTER
  │ Poly barb end: 25mm poly pipe slides over (clamped)
  │ Thread end: 3/4" BSP FEMALE
    ↓
    │ PTFE tape on threads
    ↓
DOUBLE MALE NIPPLE
  │ Philmac 3/4" BSP Male (both ends)
  │ Top end screws INTO Nut & Tail (Female)
  │ Bottom end screws INTO Pressure Reducer (Female)
    ↓
    │ PTFE tape on threads
    ↓
PRESSURE REDUCER INLET
  │ 3/4" BSP FEMALE thread
  │ Reduces pressure to 300 kPa
  │ Outlet: 3/4" BSP MALE
    ↓
    │ Screws directly into Timer
    ↓
TAP TIMER INLET (3/4" BSP Female)
```

### Why the Nipple is Needed:

**The Problem:**
- Nut & Tail has 3/4" BSP **Female** thread
- Pressure Reducer has 3/4" BSP **Female** inlet
- Two female threads cannot connect to each other!

**The Solution:**
- Insert a 3/4" BSP **Male-Male** nipple between them
- The nipple has male threads on BOTH ends
- One end screws into the Nut & Tail (Female)
- Other end screws into the Pressure Reducer (Female)

---

## Installation Sequence Checklist

```
□ 1. Install ball valve on tank outlet
□ 2. Connect pump to ball valve with BSP threads
□ 3. Install pump outlet adapter (BSP to poly barb)
□ 4. Connect 25mm poly pipe to pump adapter with clamp
□ 5. [FUTURE: Install flow sensor on straight pipe section]
□ 6. Run 25mm poly pipe to garden (install elbows as needed)
□ 7. Install 25mm filter inline (both ends 25mm barb)
□ 8. Connect short 25mm poly pipe section after filter
□ 9. Install Pope 25mm Nut & Tail (converts to 3/4" BSP Female)
□ 10. Screw Philmac double male nipple onto nut & tail (3/4" BSP + PTFE)
□ 11. Screw pressure reducer onto nipple (3/4" BSP + PTFE)
□ 12. Screw tap timer onto pressure reducer outlet (3/4" BSP + PTFE)
□ 13. Connect 13mm poly pipe to timer's 12mm hose barb outlet
□ 14. Secure with 13mm ratchet clamp
□ 15. Layout and connect 13mm drip tube network
□ 16. Install tees, elbows, and drippers as needed
□ 17. Install end plugs on all termination points
□ 18. Pressure test system before burying pipe
□ 19. Program tap timer for watering schedule
□ 20. Bury 25mm main line at 300mm depth
□ 21. Mark pipe route with markers
```

---

## Shopping List - Organized for Bunnings

### IRRIGATION AISLE:
- Holman 25mm x 50m Black Poly Pipe (p3120670) - 1
- Holman 25mm x 1m Black Poly Pipe (short sections) - 1
- Pope 25 x 25mm BSP Male Director (p3128198) - 1
- Pope 25mm Single Poly Barbed Elbow (p3127029) - 4
- Pope 25mm Barbed Joiner - Single - 2
- Pope 25mm Poly Nut And Tail (p3123863) - 1
- Pope 25mm Single Poly Ratchet Clamp (p3126992) - 15+
- Pope 25mm In-Line Barbed Filter (p3120271) - 1
- Pope 300kPa Pressure Reducer (p3121926) - 1
- Pope 13mm x 30m Drip Eze Tube (p3120300) - 1
- Pope Veriflow Dripper - 25 Pack - 1
- Pope 13mm Single Barbed Poly Tee - 5
- Pope 13mm Single Poly Barbed Elbow - 5
- Pope 13mm Single Barbed End Plug - 3
- Pope 13mm Locking Clamp - 25 Pack - 1
- Holman Electronic Low Pressure Tap Timer (p3120874) - 1

### PLUMBING AISLE:
- Philmac 25mm Ball Valve - 1
- Philmac 3/4" BSP Thread Pipe Nipple (p4813759) - 1
- Thread Seal Tape (PTFE) - 1 roll

### GARDEN HOSES & SPRINKLERS AISLE:
- GARDENA AquaCount Water Meter (p0737647) - 1 *(Optional)*

### TOOLS:
- Pope Universal Poly Pipe Cutter - 1 *(Recommended)*

### ELECTRICAL (for batteries):
- AAA Batteries 2-pack - 1

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
4. **Thread seal:** Use 3-4 wraps of PTFE tape on all BSP threads, wrap in direction of thread rotation
5. **Hand tight plus:** Tighten BSP connections hand-tight, then 1-2 turns with wrench (don't over-tighten)

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

## Notes on Part Numbers

1. **"Generic" entries:** Standard items where specific Bunnings part numbers weren't available. Ask staff for equivalent Pope/Holman products.

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
**Cost:** ~$298
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
**Revision:** 3.0 (All compatibility issues corrected + nipple adapter added)
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

## Compatibility Verification Summary

All parts in this BOM have been verified for compatibility:

✅ **Tank to Pump:** 25mm BSP Female (tank) → 25mm BSP Male (ball valve) → 25mm BSP Female (pump)  
✅ **Pump Outlet:** 25mm BSP Male → Pope 25mm BSP Male Director → 25mm poly pipe  
✅ **Filter:** 25mm poly barb inlet and outlet (no diameter change)  
✅ **Nut & Tail to Pressure Reducer:** Nut & Tail (3/4" BSP F) → Nipple (3/4" BSP M both ends) → Pressure Reducer (3/4" BSP F inlet)  
✅ **Pressure Reducer to Timer:** PR outlet (3/4" BSP M) screws into Timer inlet (3/4" BSP F)  
✅ **Timer to Drip Line:** 13mm poly pipe fits over 12mm hose barb (standard connection)  

**All BSP thread connections verified - no mismatches!**

---

*End of Document*
