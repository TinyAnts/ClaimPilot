#!/usr/bin/env python3
"""
ClaimPilot synthetic corpus generator.

Regenerates the 150-claim veterinary insurance benchmark and its independent
ground-truth labels from an explicit policy grammar and a fixed random seed.

    python3 generate_corpus.py --n 150 --seed 20260101 --out .

Outputs
    claims_dataset.json   the claim documents given to the pipeline
    ground_truth.json     reference dispositions/payouts from the oracle
    stats.json            corpus composition summary

Design notes (see paper, Sections 6.6 and 6.7)
  * Claims are composed from a peril grammar, not sampled from a language model.
  * The oracle applies the modelled policy to each claim's TRUE underlying fields.
    No ground-truth field is ever exposed to an LLM prompt: the pipeline receives
    only the claim document and must recover what the oracle already knows.
  * The corpus is stratified to exercise every decision path, including
    document-completeness failures, excluded line items, waiting-period edges,
    and add-on dependence.
"""
import json, random, argparse, datetime, collections, os

# ---------------------------------------------------------------- policy ----
ANNUAL_LIMIT   = 10000
DEDUCTIBLE     = 250
REIMBURSE_PCT  = 80
WAITING_DAYS   = {"accident": 0, "illness": 14, "orthopedic": 182,
                  "wellness": 0, "cosmetic": 0}
EXCLUDED_ITEMS = {"Prescription i/d food", "Therapeutic diet", "Joint supplement",
                  "Nail trim", "Boarding", "Nutritional supplement"}

# ------------------------------------------------------------- generation ---
SPECIES = {"dog": ["Labrador", "Beagle", "Boxer", "Bulldog", "Dachshund", "Husky", "Poodle"],
           "cat": ["Domestic Shorthair", "Maine Coon", "Persian", "Ragdoll", "Siamese"]}

DIAGNOSES = {
    "accident":   ["Laceration repair", "Foreign body ingestion", "Fracture (fall)",
                   "Hit-by-car trauma"],
    "illness":    ["Acute gastroenteritis", "Urinary tract infection", "Dermatitis",
                   "Otitis externa", "Hyperthyroidism"],
    "orthopedic": ["Cranial cruciate ligament rupture", "Luxating patella", "Hip dysplasia"],
    "cosmetic":   ["Elective ear cropping", "Declaw (elective)", "Cosmetic dental whitening"],
    "wellness":   ["Annual wellness exam", "Core vaccination", "Heartworm prevention"],
}
TREATMENT = "Exam, diagnostics, treatment as indicated"

BASE_ITEMS = {
    "accident":   [("Exam", 55, 95), ("Diagnostics", 180, 420), ("Surgery + anesthesia", 400, 1400),
                   ("Hospitalization", 200, 600), ("Prescription meds", 30, 120)],
    "illness":    [("Exam", 55, 95), ("Diagnostics", 120, 380), ("Procedure", 150, 700),
                   ("Prescription meds", 30, 140)],
    "orthopedic": [("Exam", 55, 95), ("Diagnostics", 200, 450), ("Surgery + anesthesia", 900, 2400),
                   ("Hospitalization", 250, 700)],
    "cosmetic":   [("Exam", 55, 95), ("Procedure", 200, 800)],
    "wellness":   [("Wellness exam", 45, 80), ("Vaccination", 25, 70)],
}
OPTIONAL_EXCLUDED = ["Joint supplement", "Prescription i/d food", "Therapeutic diet",
                     "Nail trim", "Boarding", "Nutritional supplement"]


def days_between(a, b):
    d1 = datetime.date(*map(int, a.split("-")))
    d2 = datetime.date(*map(int, b.split("-")))
    return (d2 - d1).days


def oracle(claim, peril, preexisting):
    """Reference adjudication from the claim's TRUE fields. Independent of the pipeline."""
    if not (claim.get("diagnosis") or "").strip():
        return "RETURNED", 0.0, {"peril": peril, "covered": False, "waiting_ok": None,
                                 "excluded_items": [], "deductible": DEDUCTIBLE,
                                 "reimburse_pct": REIMBURSE_PCT}, "missing or illegible diagnosis"

    waiting_ok = days_between(claim["policy_start"], claim["claim_date"]) >= WAITING_DAYS[peril]
    covered, reason = True, "adjudicated"
    if peril == "cosmetic":
        covered, reason = False, "excluded peril / pre-existing"
    elif preexisting:
        covered, reason = False, "excluded peril / pre-existing"
    elif not waiting_ok:
        covered, reason = False, "within waiting period"
    elif peril == "wellness" and "wellness" not in (claim.get("addons") or []):
        covered, reason = False, "routine excluded without wellness add-on"

    excluded = [i["desc"] for i in claim["line_items"] if i["desc"] in EXCLUDED_ITEMS]
    pe = {"peril": peril, "covered": covered, "waiting_ok": waiting_ok,
          "excluded_items": excluded, "deductible": DEDUCTIBLE, "reimburse_pct": REIMBURSE_PCT}
    if not covered:
        return "DENY", 0.0, pe, reason

    excl_amt = sum(i["amount"] for i in claim["line_items"] if i["desc"] in excluded)
    net = claim["invoice_total"] - excl_amt
    raw = max(0, net - DEDUCTIBLE) * REIMBURSE_PCT / 100.0
    payout = round(min(raw, ANNUAL_LIMIT), 2)
    if net <= 0:
        return "DENY", 0.0, pe, reason
    disposition = "PARTIAL" if (excluded or raw > ANNUAL_LIMIT) else "APPROVE"
    return disposition, payout, pe, reason


def build(n, seed):
    rng = random.Random(seed)
    # target composition (matches the released benchmark)
    plan = (["accident"] * 43 + ["illness"] * 36 + ["orthopedic"] * 18 +
            ["cosmetic"] * 14 + ["wellness"] * 21 + ["unusable"] * 18)
    rng.shuffle(plan)
    plan = (plan * ((n // len(plan)) + 1))[:n]

    claims, truth = [], []
    for idx, kind in enumerate(plan, start=1):
        eid = f"SYN-{idx:04d}"
        species = rng.choice(list(SPECIES))
        breed = rng.choice(SPECIES[species])
        pet = {"species": species, "breed": breed, "age_years": rng.randint(1, 14)}

        peril = "illness" if kind == "unusable" else kind
        start = datetime.date(2024, 1, 1) + datetime.timedelta(days=rng.randint(0, 500))
        # waiting-period edge cases: place some claims just inside/outside the window
        offset = WAITING_DAYS[peril] + rng.choice([-5, -1, 1, 30, 120, 300])
        claim_date = start + datetime.timedelta(days=max(1, offset))

        items = [{"desc": d, "amount": rng.randint(lo, hi)} for d, lo, hi in BASE_ITEMS[peril]]
        if rng.random() < 0.28:                      # inject an excluded line item
            items.append({"desc": rng.choice(OPTIONAL_EXCLUDED), "amount": rng.randint(20, 90)})
        total = sum(i["amount"] for i in items)

        addons = ["wellness"] if (peril == "wellness" and rng.random() < 0.45) else []
        diagnosis = "" if kind == "unusable" else rng.choice(DIAGNOSES[peril])
        # pre-existing grounds are deliberately ABSENT from the document (see Section 6.7)
        preexisting = (kind != "unusable" and rng.random() < 0.09)

        claim = {"external_id": eid, "pet": pet,
                 "policy_start": start.isoformat(), "claim_date": claim_date.isoformat(),
                 "addons": addons, "diagnosis": diagnosis, "treatment": TREATMENT,
                 "line_items": items, "invoice_total": total}
        disp, payout, pe, reason = oracle(claim, peril, preexisting)
        claims.append(claim)
        truth.append({"external_id": eid, "disposition": disp, "payout": payout,
                      "reason": reason, "policy_eval": pe})
    return claims, truth


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=150)
    ap.add_argument("--seed", type=int, default=20260101)
    ap.add_argument("--out", default=".")
    a = ap.parse_args()

    claims, truth = build(a.n, a.seed)
    os.makedirs(a.out, exist_ok=True)
    json.dump(claims, open(os.path.join(a.out, "claims_dataset.json"), "w"), indent=1)
    json.dump(truth, open(os.path.join(a.out, "ground_truth.json"), "w"), indent=1)

    disp = collections.Counter(t["disposition"] for t in truth)
    peril = collections.Counter((t["policy_eval"] or {}).get("peril") for t in truth)
    totals = [c["invoice_total"] for c in claims]
    paid = [t["payout"] for t in truth if t["payout"] > 0]
    stats = {"N": len(claims), "seed": a.seed, "disposition": dict(disp), "peril": dict(peril),
             "invoice_mean": round(sum(totals) / len(totals)),
             "invoice_max": max(totals),
             "payout_paid_n": len(paid),
             "payout_mean": round(sum(paid) / len(paid)) if paid else 0}
    json.dump(stats, open(os.path.join(a.out, "stats.json"), "w"), indent=2)

    print(json.dumps(stats, indent=2))
    print("\nNOTE: regenerating with a different seed produces a NEW corpus. The benchmark "
          "reported in the paper is the released claims_dataset.json / ground_truth.json pair; "
          "this generator documents and reproduces the construction procedure.")


if __name__ == "__main__":
    main()
