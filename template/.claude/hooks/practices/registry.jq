# From the python-service template: change the template, not this copy.
# The python-service layer's practices, which the agentic guard.sh runs on every edit.
import "skipped_checks" as skipped_checks;
import "excepts" as excepts;
import "docstrings" as docstrings;
import "comments" as comments;
import "logs" as logs;
import "tests" as tests;
import "config" as config;

def kind($path):
  if $path | endswith(".py") then "python"
  elif $path | test("/(pyproject\\.toml|\\.?ruff(\\.base)?\\.toml|basedpyright\\.base\\.json|\\.pre-commit-config\\.yaml|Makefile|[^/]+\\.mk)$") then "config"
  elif $path | test("\\.(toml|ya?ml)$") then "data"
  else null end;

def practices($ctx; $kind):
  if $kind == "python" then
    skipped_checks::check($ctx), excepts::check($ctx), docstrings::check($ctx),
    comments::check($ctx), logs::check($ctx), tests::check($ctx)
  elif $kind == "config" then config::check($ctx), comments::check($ctx)
  else comments::check($ctx) end;
