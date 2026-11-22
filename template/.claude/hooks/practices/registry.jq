# From the python-service template: change the template, not a project's copy.
# The python-service layer's practices, which the agentic guard.sh runs on every edit.
import "skipped_checks" as skipped_checks;
import "secret_scan_skips" as secret_scan_skips;
import "excepts" as excepts;
import "docstrings" as docstrings;
import "comments" as comments;
import "logs" as logs;
import "tests" as tests;
import "config" as config;

def kind($path):
  if $path | endswith(".py") then "python"
  elif $path | test("/(pyproject\\.toml|\\.?ruff(\\.base)?\\.toml|basedpyright\\.base\\.json|\\.jscpd\\.json|\\.pre-commit-config\\.yaml|pre-commit\\.base\\.yaml|Makefile|[^/]+\\.mk)$") then "config"
  elif $path | test("\\.(toml|ya?ml)$") then "data"
  else "other" end;

# gitleaks scans a file of any type, so every edit is checked for its skips.
def practices($ctx; $kind):
  secret_scan_skips::check($ctx),
  if $kind == "python" then
    skipped_checks::check($ctx), excepts::check($ctx), docstrings::check($ctx),
    comments::check($ctx), logs::check($ctx), tests::check($ctx)
  elif $kind == "config" then config::check($ctx), comments::check($ctx)
  elif $kind == "data" then comments::check($ctx)
  else empty end;
