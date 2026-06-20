## PERSISTENT MEMORY (append to every agent SOUL.md)
State lives in files, not conversation history.

### On start / session clear:
1. Read ../../IDENTITY.md  -> rules + mode
2. Read ../../context.md   -> current state
3. Read ../../tasks.md     -> claims in flight
4. Skim last 5 ../../log.md lines -> recent events
5. Read ../../policy/policy-rules.md + coverage-matrix.md (if your job needs policy)
6. Resume as if uninterrupted.

### After each action:
- Update the relevant claim record in ../../data/claims.json (status + your fields only)
- Append ONE line to ../../data/audit-log.jsonl: {"id","from","to","agent","ts","reason"}
- Add at most 1 line to ../../log.md
- Never store full conversation text or full document text in memory files.

### Compression: abbreviate (clm, dx, tx, amt, excl), no filler, one concept per line.
### Response length: output only changed fields + 1-line summary. No preamble. No restating input.
### Dedup: if a claim is already at/past your output status, skip it.
### Fail-safe: missing/contradictory data -> status=returned with reason. Never invent values.
