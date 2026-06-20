# Policy Rules (DEMO insurer — edit to point the system at a real policy)
Plan = Accident & Illness
Annual limit = $10,000
Deductible = $250 / policy year (per pet)
Reimbursement = 80% after deductible
Waiting periods: illness 14 days from policy start; cruciate/orthopedic 6 months; accident 0 days

## Exclusions (deny / partial)
- Pre-existing conditions (any sign/symptom before policy start or during waiting period)
- Elective/cosmetic (declaw, tail dock, ear crop)
- Breeding, pregnancy, whelping
- Routine/preventive UNLESS Wellness add-on present (check claim.addons)
- Boarding, grooming, food, supplements (non-prescription)

## Decision shorthand for AdjudicationDrafter
APPROVE  = covered peril, post-waiting, not excluded, amount reasonable, within annual limit
PARTIAL  = covered but some line items excluded OR exceeds remaining annual limit
DENY     = excluded peril, within waiting period, or pre-existing
RETURNED = missing records, illegible invoice, diagnosis/treatment mismatch unresolved
