# From the agentic template: change the template, not this copy.
# The verdict on a PR's checks. A pending check may be the gate, so it outweighs a gate not run.

# Each check by its newest run, as in `gh pr checks`: the head keeps the checks of every run.
def newest_runs:
  [.statusCheckRollup // [] | group_by([.workflowName, .name, .context])[] | max_by(.startedAt)];

# The check the rulesets require; the Gate workflow's read-draft passes on a draft too.
def gate: .workflowName == "Gate" and .name == "gate";

def conclusion:
  if .__typename == "StatusContext" then .state
  elif .status == "COMPLETED" then .conclusion else "PENDING" end;

def verdict:
  newest_runs as $checks
  | if $checks == [] then "no checks"
    elif any($checks[] | conclusion; IN("SUCCESS", "NEUTRAL", "SKIPPED", "PENDING", "EXPECTED") | not) then "checks failed"
    elif any($checks[] | conclusion; IN("PENDING", "EXPECTED")) then "checks pending"
    elif any($checks[]; gate and conclusion == "SUCCESS") then "checks passed"
    else "gate not run" end;
