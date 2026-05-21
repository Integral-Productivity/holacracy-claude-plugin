# Meeting Templates -- Holacracy Secretary

Expanded templates for Tactical and Governance meeting outputs. Use these as the basis for all Secretary captures. Copy and populate the appropriate template at the start of each meeting.

---

## Tactical Meeting Template (Full)

```markdown
# Tactical Meeting -- [Circle Name]
**Date:** [YYYY-MM-DD]
**Time:** [HH:MM - HH:MM timezone]
**Circle Members Present:** [Name / Role, ...]
**Facilitator:** [Name]
**Secretary:** [Name / AI co-Secretary]

---

## Check-in
| Participant | Check-in |
|------------|----------|
| [Name]     | [note]   |

---

## Checklist Review
| Checklist Item | Role | Frequency | Status | Notes |
|----------------|------|-----------|--------|-------|
| [item]         | [role] | [weekly/monthly] | [+]/[-] | [context if not done] |

---

## Metrics Review
| Metric | Role | Current Value | Target | Notes |
|--------|------|---------------|--------|-------|
| [metric] | [role] | [value] | [target if set] | [commentary] |

---

## Project Updates
| Project | Role / Person | Status | Update |
|---------|---------------|--------|--------|
| [project] | [role] | [on track / stalled / done] | [brief update] |

---

## Agenda
Items added during build:
1. [label]
2. [label]
3. ...

---

## Triage Outputs

### Actions Captured
| # | Action Description | Role / Person | Due Date |
|---|--------------------|---------------|----------|
| 1 | | | |
| 2 | | | |

### New Projects Proposed
| Project | Role / Person | Notes |
|---------|---------------|-------|

### Tensions for Governance
(Items that could not be resolved through tactical -- need a governance meeting)
- [Tension as described by the person who named it]

### Other Outputs
(Decisions made, information shared, coordination confirmed)
- [item]

---

## GlassFrog Gap Analysis
*(Include only when GlassFrog data was loaded before this meeting. Omit section entirely if GlassFrog was unavailable.)*

### Items in GlassFrog not reviewed in this meeting
| Item | Type | Role | Possible reason skipped |
|------|------|------|------------------------|
| | Checklist / Metric / Project | | Absent role-filler / frequency mismatch / retired informally |

### Items mentioned in the meeting not found in GlassFrog
| Item | Type | Mentioned by | Suggested action |
|------|------|-------------|-----------------|
| | Checklist / Metric / Project | | Add to GlassFrog / bring as governance tension |

### Gap Analysis Notes
*(Any pattern or concern worth flagging for the circle -- e.g., three consecutive missed checklist items, informal work not in governance records, etc.)*

---

## Closing
| Participant | Closing Reflection |
|------------|-------------------|
| [Name]     | [note]            |

---

*Published by: [Secretary name/AI co-Secretary] on [date]*
```

---

## Governance Meeting Template (Full)

```markdown
# Governance Meeting -- [Circle Name]
**Date:** [YYYY-MM-DD]
**Time:** [HH:MM - HH:MM timezone]
**Circle Members Present:** [Name / Role, ...]
**Facilitator:** [Name]
**Secretary:** [Name / AI co-Secretary]

---

## Check-in
| Participant | Check-in |
|------------|----------|
| [Name]     | [note]   |

---

## Administrative Concerns
[Scheduling, housekeeping items]

---

## Agenda
Items added during build:
1. [label -- one or two words]
2. [label]
3. ...

---

## Governance Outcomes

### Item 1 -- "[Tension Label]"
**Proposer:** [Name / Role]
**Tension (as stated):** [Verbatim or close paraphrase of the tension the proposer named]
**Initial Proposal:** [Exact text of the proposed governance change]

**Clarifying Questions:** [Significant Q&A, or "None"]

**Reactions:** [Brief summary of reaction round, or "No significant reactions"]

**Objections Raised:**
- [Objector name/role]: [Objection as stated] -> Resolved by: [amendment / withdrawn]
  - **Amendment:** [Revised proposal text if amended]

**Final Proposal Text:**
> [Exact final text of the governance change -- this is the official record]

**Outcome Type:** [ ] Role created  [ ] Role modified  [ ] Role removed  [ ] Policy added  [ ] Policy modified  [ ] Policy removed  [ ] Domain delegated  [ ] Strategy adopted  [ ] Election

**Summary of Change:** [One-sentence plain-language description of what changed]

---

### Item 2 -- "[Tension Label]"
[same structure]

---

## No-Action Items
| Tension Label | Proposer | Disposition |
|---------------|----------|-------------|
| [label]       | [name]   | Withdrawn / Failed objection criteria / Tabled |

---

## GlassFrog Gap Analysis
*(Include only when GlassFrog data was loaded. Omit section entirely if GlassFrog was unavailable.)*

### Governance record vs. meeting outcomes
| Change decided in meeting | Reflected in GlassFrog? | Action needed |
|--------------------------|------------------------|---------------|
| [e.g., new accountability on Social Media role] | [+] / [-] / Not yet | [e.g., update via GlassFrog UI -- API is read-only for role definitions] |

### Roles or elements discussed but not found in GlassFrog
| Element | Type | Notes |
|---------|------|-------|
| [e.g., "Operations Coordinator" mentioned in proposal] | Role | Does not exist in GlassFrog -- informal or pending formal creation |

### Gap Analysis Notes
*(Discrepancies between what the circle believes its governance says and what GlassFrog actually records. Any gap here is a governance integrity risk.)*

---

## Closing
| Participant | Closing Reflection |
|------------|-------------------|
| [Name]     | [note]            |

---

*Published by: [Secretary name/AI co-Secretary] on [date]*
*GlassFrog update status: [ ] Complete  [ ] Pending  [ ] N/A*
```

---

## Election Record Template

Used when the Governance Meeting includes an Integrative Election:

```markdown
### Election -- [Role Name] (e.g., Facilitator / Secretary / Circle Rep)
**Facilitator (for this election):** [Name]
**Nominees:** [List of nominees]
**Process:** Integrative Election per S.5.3
**Elected:** [Name]
**Term:** [Duration or "until next election" if not specified]
**Consented by:** All Circle Members present
```

---

## Pre-Meeting Prep Checklist

### Before Tactical
- [ ] Load checklist items from GlassFrog (`glassfrog_list_checklist_items`)
- [ ] Load metrics from GlassFrog (`glassfrog_list_metrics`)
- [ ] Load projects from GlassFrog (`glassfrog_list_projects`)
- [ ] Populate Tactical Meeting template with items from above
- [ ] Confirm meeting time and attendees
- [ ] Send prep packet to Circle Members (optional but recommended)

### Before Governance
- [ ] Load current role definitions (`glassfrog_list_roles`, `glassfrog_get_role` for detail)
- [ ] Load current policies (`glassfrog_get_circle`)
- [ ] Note any previously-identified tensions that may surface as proposals
- [ ] Confirm meeting time and attendees
- [ ] Prepare governance output template

---

## Post-Meeting Publishing Checklist

### After Tactical
- [ ] Finalize and clean up meeting notes
- [ ] Update project statuses in GlassFrog (`glassfrog_update_project`)
- [ ] Distribute final meeting output to Circle Members
- [ ] Archive to circle's designated record location

### After Governance
- [ ] Finalize governance meeting output with exact final proposal text
- [ ] Verify GlassFrog reflects all governance changes (or flag for manual update)
- [ ] Distribute governance output to Circle Members
- [ ] Archive to circle's governance records
- [ ] Publish any constitutional interpretation rulings issued during the meeting
