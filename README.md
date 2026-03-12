# SAP HANA AMDP Hierarchy Expansion for Financial Management

## Overview

This repository contains **ABAP CDS Table Functions and AMDP implementations** that expand **SAP Set-based hierarchies** used in Financial Management into a **flattened relational structure**.

The implementation is written using:

- ABAP Managed Database Procedures (AMDP)
- HANA SQLScript
- CDS Table Functions

The goal is to efficiently expand hierarchical **SET structures** stored in SAP tables such as:

- `SETHEADER`
- `SETNODE`
- `SETLEAF`
- `SETHEADERT`

and return them as **fully expanded hierarchies with parent relationships and path information**.

This pattern is useful for:

- Financial reporting
- Hierarchy flattening for analytics
- CDS-based reporting models
- Performance optimized hierarchy traversal in SAP HANA

---

## Architecture

Each hierarchy is implemented using the following pattern:

```
CDS Table Function
        ↓
AMDP Class Method (SQLScript)
        ↓
Reads SAP SET hierarchy tables
        ↓
Returns flattened hierarchy
```

The CDS table function defines the interface, while the AMDP class implements the logic in SQLScript executed in SAP HANA.

---

## Repository Contents

### CDS Table Functions

| Object | Description |
|------|-------------|
| `ZI_CEHierTF.ddls.asddl` | Expands Cost Element Group hierarchies |
| `zi_CIHierTF.ddls.asddl` | Expands Commitment Item hierarchies |
| `zi_CSHierTF.ddls.asddl` | Expands Cost Center hierarchies |
| `ZI_FMHIERTF.ddls.asddl` | Expands Fund Center hierarchies |

Each table function returns:

- hierarchy leaf nodes
- parent hierarchy nodes
- level relationship
- hierarchy path
- node text

---

### AMDP Implementations

| Class | Purpose |
|------|---------|
| `zcl_fm_ce_hier_amdp.clas.abap` | AMDP implementation for Cost Element hierarchy |
| `zcl_fm_ci_hier_amdp.class.abap` | AMDP implementation for Commitment Item hierarchy |
| `zcl_fm_cs_hier_amdp.clas.abap` | AMDP implementation for Cost Center hierarchy |
| `zcl_fm_fc_hier_amdp.clas.abap` | AMDP implementation for Fund Center hierarchy |

Each class:

- Implements `IF_AMDP_MARKER_HDB`
- Executes SQLScript in SAP HANA
- Reads hierarchy data from SAP SET tables
- Returns expanded hierarchy nodes

---

## Hierarchy Source Tables

The logic reads hierarchy structures from standard SAP tables:

| Table | Purpose |
|------|--------|
| `SETHEADER` | Set definition |
| `SETNODE` | Hierarchy node relationships |
| `SETLEAF` | Leaf values |
| `SETHEADERT` | Set text descriptions |

Additional master data tables are joined depending on hierarchy type.

### Examples

| Hierarchy | Master Data Table |
|-----------|------------------|
| Cost Center | `CSKS`, `CSKT` |
| Cost Element | `SKA1` |
| Commitment Item | `FMCI` |
| Fund Center | `FMFCTR` |

---

## Output Structure

Each hierarchy returns a flattened structure similar to:

| Field | Description |
|------|-------------|
| Client | SAP Client |
| RootSet | Root hierarchy node |
| ParentSet | Parent node |
| ParentLevel | Distance from leaf |
| NodeKind | Leaf or set node |
| Object | Actual business object (Cost center, CI, etc.) |
| SetText | Set description |
| ParentSetText | Parent node description |
| SetSequenceNumber | Sequence within set |
| Path | Full hierarchy path |

### Example hierarchy path

```
TOTAL -> OPERATIONS -> IT -> SERVER_COSTS
```

---

## Example Usage

Example CDS consumption:

```sql
SELECT *
FROM ZI_CSHierTF(
    p_FIKRS    = '1000',
    p_SETCLASS = '0101',
    p_SETNAME  = 'TOTAL'
);
```

Returns the full **Cost Center hierarchy expansion** under the root node.

---

## Key Features

- Fully executed in **SAP HANA SQLScript**
- Avoids recursive **ABAP loops**
- Efficient hierarchy expansion
- Designed for **CDS based reporting**
- Reusable pattern for any **SET hierarchy**

---

## Use Cases

Typical scenarios where this pattern is useful:

- Financial reporting hierarchies
- Budget reporting
- Fund center rollups
- Commitment item analysis
- Cost center group reporting
- Analytics in CDS views

---

## Performance Considerations

The hierarchy expansion is executed directly in **HANA using SQLScript**, which provides:

- set-based processing
- minimal data transfer to ABAP layer
- efficient handling of deep hierarchies

This approach scales better than traditional **recursive ABAP implementations**.

---

## Author

**SAP ABAP / S4HANA Developer**

Focus areas:

- ABAP on HANA
- AMDP
- CDS development
- Financial Management reporting
