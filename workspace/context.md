# Context
Updated: pilot-evaluated (v2)
Active insurer = DEMO (edit policy/ files to switch insurer)
System status = DRAFT_ONLY, 9-role pipeline live (8 LLM agents + deterministic adjudication)
Models = all live agents on cheap tier; pattern-review on frontier (weekly)
policy_eval contract MUST include: peril, covered(true/false), waiting_ok, excluded_items, deductible, reimburse_pct
Pilot (40 claims): 100% completion, 50% disposition accuracy, Cohen kappa 0.33, payout MAE $183.88
Known gaps = no 'returned' route in orchestrator; over-approval bias on withhold-payment classes
