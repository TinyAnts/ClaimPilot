# Context
Updated: v2 (deterministic policy engine)
System status = DRAFT_ONLY, human gate mandatory
Division of labour: LLM = field extraction + usability gate + peril classification ONLY.
CODE = waiting period, exclusions, coverage, payout (policy engine + adjudication).
Status chain = received -> extracted|returned -> classified -> policy_checked -> risk_scored
               -> adjudication_drafted -> human_review
v1 pilot (40 claims): 50.0% accuracy, kappa 0.33, 0/10 RETURNED detected.
v2 simulated ceiling on 150 claims: 96.0% (88% even at 20% peril-misclassification).
Known dataset limit: ~7 pre-existing DENY claims carry no signal in the document (unlearnable).
