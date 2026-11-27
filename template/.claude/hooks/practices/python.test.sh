#!/usr/bin/env bash
# From the python-service template: change the template, not this copy.
# Table-driven regression suite for the python-service practices behind the agentic guard.sh (the
# copies beside it). Run from any checkout: bash .claude/hooks/practices/python.test.sh
# Expect 2 = stopped, R = goes on with a reminder, 0 = silent.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
# The checks run from a copy beside a fixture stack.json, so the cases never depend on the answers
# this project was rendered with.
cp "$HERE"/*.jq "$HERE/guard.sh" "$WORK/"
PKG=app
stack() {  # stack <parts> <boundaries>: the answers the cases after it run with, as JSON
  printf '{"package": "%s", "parts": %s, "boundaries": %s}\n' "$PKG" "$1" "$2" >"$WORK/stack.json"
}
EVERY_PART='["api", "batch", "database"]'
stack "$EVERY_PART" '["release.run"]'
GUARD="$WORK/guard.sh"
REPO="$(mktemp -d)"; NOGIT="$(mktemp -d)"
trap 'rm -rf "$REPO" "$NOGIT" "$WORK"' EXIT
git -C "$REPO" init -q
mkdir -p "$REPO/$PKG/services" "$REPO/$PKG/api/v1/routers" "$REPO/tests/unit"
mkdir -p "$REPO/$PKG/api/v1/core" "$REPO/$PKG/api/mcp/tools/guides" "$REPO/$PKG/batch"
mkdir -p "$REPO/database/versions" "$REPO/.github/workflows" "$REPO/commons"
APP="$REPO/$PKG/services/case.py"
COMMONS="$REPO/commons/case.py"
MIGRATION="$REPO/database/versions/abc123_add_x.py"
ROUTER="$REPO/$PKG/api/v1/routers/case.py"
TEST="$REPO/tests/unit/case.py"
pass=0; fail=0

check() {  # check <want> <desc> <payload>
  local out code got
  out="$(bash "$GUARD" <<<"$3" 2>/dev/null)"; code=$?
  got="$code"
  [ "$code" -eq 0 ] && [[ "$out" == *additionalContext* ]] && got=R
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS ($got) $2"
  else fail=$((fail+1)); echo "FAIL (want $1, got $got) $2"; fi
}
edit() {  # edit <want> <desc> <path> <old> <new>   (the file holds exactly <old>)
  edit_in "$1" "$2" "$3" "$4" "$4" "$5"
}
edit_in() {  # edit_in <want> <desc> <path> <file content> <old_string> <new_string>
  printf '%s' "$4" >"$3"
  check "$1" "$2" "$(jq -n --arg p "$3" --arg o "$5" --arg n "$6" \
    '{tool_input:{file_path:$p, old_string:$o, new_string:$n}}')"
}
write() {  # write <want> <desc> <path> <on-disk content> <new content>
  printf '%s' "$4" >"$3"
  check "$1" "$2" "$(jq -n --arg p "$3" --arg c "$5" '{tool_input:{file_path:$p, content:$c}}')"
}
says() {  # says <yes|no> <phrase> <desc> <path> <old> <new>: whether the guard's message has <phrase>
  local out got=no
  printf '%s' "$5" >"$4"
  out="$(jq -n --arg p "$4" --arg o "$5" --arg n "$6" \
    '{tool_input:{file_path:$p, old_string:$o, new_string:$n}}' | bash "$GUARD" 2>&1)"
  [[ "$out" == *"$2"* ]] && got=yes
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS ($got) $3"
  else fail=$((fail+1)); echo "FAIL (want $1, got $got) $3"; fi
}

# A reason in the form the rules give follows the why with one of these per alternative.
TRIED='Tried the fix the rule gives, but it breaks the callers.'

echo "-- skipped checks: no rule code, or no reason in the form (must stop)"
edit 2 "bare noqa"                    "$APP" 'x = 1' 'x = 1  # noqa'
edit 2 "noqa code, no reason"         "$APP" '    except ValueError:' '    except ValueError:  # noqa: S110'
edit 2 "file-level ruff noqa"         "$APP" 'import x' $'# ruff: noqa: E501\nimport x'
edit 2 "bare type ignore"             "$APP" 'a = f()' 'a = f()  # type: ignore'
edit 2 "type ignore code, no reason"  "$APP" 'a = f()' 'a = f()  # type: ignore[assignment]'
edit 2 "pyright ignore, no reason"    "$APP" 'a = f()' 'a = f()  # pyright: ignore[reportAssignmentType]'
edit 2 "pyright directive, no reason" "$APP" 'import x' $'# pyright: basic\nimport x'
edit 2 "nosec code, no reason"        "$APP" 'y = load(f)' 'y = load(f)  # nosec B506'
edit 2 "pragma no cover"              "$APP" 'def f():' 'def f():  # pragma: no cover'
edit 2 "fmt skip, reason w/o 2nd #"   "$APP" 'x = [1]' "x = [1]  # fmt: skip keep aligned. $TRIED"
edit 2 "fmt off, trailing reason"     "$APP" 'x = [1]' "# fmt: off  # aligned table. $TRIED"$'\nx = [1]'
edit 2 "fmt off, nothing above"       "$APP" 'x = [1]' $'# fmt: off\nx = [1]'
edit 2 "mark.skip, no reason"         "$TEST" 'def test_x():' $'@pytest.mark.skip\ndef test_x():'
edit 2 "skipif, no reason"            "$TEST" 'def test_x():' $'@pytest.mark.skipif(sys.platform == "win32")\ndef test_x():'
edit 2 "pytest.skip()"                "$TEST" '    pass' '    pytest.skip()'
edit 2 "filterwarnings mark that ignores, no reason" "$TEST" 'def test_x():' \
  $'@pytest.mark.filterwarnings("ignore::DeprecationWarning")\ndef test_x():'
edit 2 "module mark that shows warnings, no reason" "$TEST" 'import pytest' \
  $'import pytest\n\npytestmark = pytest.mark.filterwarnings("default")'
edit 2 "mark with error and another filter" "$TEST" 'def test_x():' \
  $'@pytest.mark.filterwarnings("error", "ignore::UserWarning")\ndef test_x():'
edit 2 "mark with its filter on the next line" "$TEST" 'def test_x():' \
  $'@pytest.mark.filterwarnings(\n    "error::UserWarning"\n)\ndef test_x():'
edit 2 "filterwarnings mark, no Tried" "$TEST" 'def test_x():' \
  $'@pytest.mark.filterwarnings("ignore::DeprecationWarning")  # the SDK warns on import\ndef test_x():'
CONFTEST="$REPO/tests/conftest.py"
edit 2 "conftest filter that ignores, no reason" "$CONFTEST" 'def pytest_configure(config):' \
  $'def pytest_configure(config):\n    config.addinivalue_line("filterwarnings", "ignore::DeprecationWarning")'
edit 2 "conftest filter split before its name, no reason" "$CONFTEST" 'def pytest_configure(config):' \
  $'def pytest_configure(config):\n    config.addinivalue_line(\n        "filterwarnings", "ignore::DeprecationWarning"\n    )'
edit 2 "jscpd ignore-start, no reason" "$APP" 'x = c()' $'# jscpd:ignore-start\nx = c()\n# jscpd:ignore-end'
edit 2 "jscpd marker inside prose"    "$APP" 'x = c()' $'# keep this jscpd:ignore-start\nx = c()'
write 2 "Write: new file, bare noqa"  "$APP" '' $'import os  # noqa\n'
edit 2 "a why, no Tried sentence"     "$APP" 'x = c()' 'x = c()  # noqa: F821 defined by the plugin loader'
edit 2 "Tried with no but"            "$APP" 'x = c()' 'x = c()  # noqa: F821 defined by the plugin loader. Tried importing it.'
edit 2 "Tried with no why before it"  "$APP" 'x = c()' 'x = c()  # noqa: F821 Tried importing it, but the import cycles.'
edit 2 "second Tried with no but"     "$APP" 'x = c()' "x = c()  # noqa: F821 defined by the plugin loader. $TRIED Tried a stub."
edit 2 "reason above a bare noqa"     "$APP" 'x = c()' $'# Defined by the plugin loader.\n# '"$TRIED"$'\nx = c()  # noqa'
edit 2 "reason above, code in between" "$APP" 'x = c()' "# Defined by the plugin loader. $TRIED"$'\ny = 1\nx = c()  # noqa: F821'
edit 2 "skipif reason, no Tried"      "$TEST" 'def test_x():' $'@pytest.mark.skipif(sys.platform == "win32", reason="no fork on Windows")\ndef test_x():'
edit 2 "pytest.skip reason, no Tried" "$TEST" '    pass' '    pytest.skip(f"Lucide icon source unreachable: {exc}")'
says yes "Read the current documentation" "the stop sends the agent to the docs first" "$APP" 'x = 1' 'x = 1  # noqa'
says yes "Tried <alternative>, but <why it was discarded>" "the stop spells out the form" "$APP" 'x = 1' 'x = 1  # noqa'
# The form holds a placeholder for the code, so it never reads as advice to change the code skipped.
says yes "Write it in this form: # pyright: ignore[<rule name>] <reason>" "the pyright form shows a placeholder for the rule" \
  "$APP" 'a = f()' 'a = f()  # pyright: ignore[reportOptionalMemberAccess]'
says no "reportAssignmentType" "the form names no rule the line didn't skip" \
  "$APP" 'a = f()' 'a = f()  # pyright: ignore[reportOptionalMemberAccess]'
says yes "Write it in this form: # jscpd:ignore-start <reason>, and # jscpd:ignore-end" \
  "the jscpd form shows the reason and the end marker" "$APP" 'x = c()' $'# jscpd:ignore-start\nx = c()'
says yes "(ruff, basedpyright, bandit, pytest, jscpd)" "the stop sends the agent to jscpd's docs too" \
  "$APP" 'x = c()' $'# jscpd:ignore-start\nx = c()'
says yes "Write it in this form: # noqa: <rule code> <reason>" "the noqa form shows a placeholder for the code" "$APP" 'x = 1' 'x = 1  # noqa: E501'
says no "BLE001" "the noqa form names no code the line didn't skip" "$APP" 'x = 1' 'x = 1  # noqa: E501'
says yes "Write it in this form: <the line that sets the filter>  # <reason>" \
  "the warning filter form shows where the reason goes" "$TEST" 'def test_x():' \
  $'@pytest.mark.filterwarnings("ignore")\ndef test_x():'

echo "-- skipped checks: rule code and a reason in the form, on the line or above (goes on)"
edit 0 "noqa code + reason"           "$APP" 'x = c()' "x = c()  # noqa: F821 defined by the plugin loader. $TRIED"
edit 0 "noqa code + 2nd-hash reason"  "$APP" 'q = c == True' "q = c == True  # noqa: E712  # SQLAlchemy needs ==. $TRIED"
edit 0 "type ignore code + reason"    "$APP" 'a = f()' "a = f()  # type: ignore[assignment] stub is wrong upstream. $TRIED"
edit 0 "pyright ignore + reason"      "$APP" 'a = f()' "a = f()  # pyright: ignore[reportAssignmentType]  # stub bug. $TRIED"
edit 0 "nosec code + reason"          "$APP" 'y = load(f)' "y = load(f)  # nosec B506 config file is ours. $TRIED"
edit 0 "pragma no cover + reason"     "$APP" 'def f():' "def f():  # pragma: no cover runs only on the host. $TRIED"
edit 0 "jscpd ignore-start + reason"  "$APP" 'x = c()' \
  "# jscpd:ignore-start the two totals change apart. $TRIED"$'\nx = c()\n# jscpd:ignore-end'
edit R "jscpd ignore-start + reason above" "$APP" 'x = c()' \
  $'# The two totals change apart.\n# '"$TRIED"$'\n# jscpd:ignore-start\nx = c()\n# jscpd:ignore-end'
edit 0 "jscpd ignore-end alone skips nothing" "$APP" 'x = c()' $'x = c()\n# jscpd:ignore-end'
edit 0 "fmt skip + 2nd-hash reason"   "$APP" 'x = [1]' "x = [1]  # fmt: skip  # keep aligned. $TRIED"
edit R "reason on the lines above"    "$APP" 'x = c()' $'# Defined by the plugin loader.\n# '"$TRIED"$'\nx = c()  # noqa: F821'
edit R "a Tried sentence wrapped over two lines" "$APP" 'x = c()' \
  $'# Defined by the plugin loader.\n# Tried importing it, but the import\n#   cycles back into this module.\nx = c()  # noqa: F821'
edit R "pyright directive + reason above" "$APP" 'import x' $'# Generated module; types come from the wire.\n# '"$TRIED"$'\n# pyright: basic\nimport x'
edit R "fmt off + reason above"       "$TEST" 'x = [1]' $'# One case per row reads as a spec.\n# '"$TRIED"$'\n# fmt: off\nx = [1]'
write 0 "fmt off, reason above already in file" "$TEST" "# One case per row reads as a spec. $TRIED"$'\nx = [1]' \
  "# One case per row reads as a spec. $TRIED"$'\n# fmt: off\nx = [1]'
edit R "skipif + reason + Tried comment" "$TEST" 'def test_x():' \
  $'@pytest.mark.skipif(sys.platform == "win32", reason="no fork on Windows")  # '"$TRIED"$'\ndef test_x():'
edit R "pytest.skip + reason above"   "$TEST" '    pass' \
  $'    # The icon list lives only upstream.\n    # '"$TRIED"$'\n    pytest.skip(f"Lucide icon source unreachable: {exc}")'
edit R "filterwarnings mark + reason" "$TEST" 'def test_x():' \
  $'@pytest.mark.filterwarnings("ignore::DeprecationWarning")  # The SDK warns on import. '"$TRIED"$'\ndef test_x():'
edit R "mark with its filter on the next line + reason above" "$TEST" 'def test_x():' \
  $'# The SDK warns on import.\n# '"$TRIED"$'\n@pytest.mark.filterwarnings(\n    "ignore::DeprecationWarning"\n)\ndef test_x():'
edit 0 "filterwarnings mark that raises" "$TEST" 'def test_x():' \
  $'@pytest.mark.filterwarnings("error::UserWarning")\ndef test_x():'
edit R "conftest filter + reason" "$CONFTEST" 'def pytest_configure(config):' \
  $'def pytest_configure(config):\n    config.addinivalue_line("filterwarnings", "ignore::DeprecationWarning")  # The SDK warns. '"$TRIED"
edit 0 "conftest filter that raises" "$CONFTEST" 'def pytest_configure(config):' \
  $'def pytest_configure(config):\n    config.addinivalue_line("filterwarnings", "error::UserWarning")'
edit 0 "conftest marker line"         "$CONFTEST" 'def pytest_configure(config):' \
  $'def pytest_configure(config):\n    config.addinivalue_line("markers", "slow: runs for minutes")'
edit 0 "old reason rewritten into the form" "$APP" 'x = 1  # noqa: E501 long URL' "x = 1  # noqa: E501 a long URL cannot wrap. $TRIED"
edit 2 "stop wins over a reminder"    "$APP" $'a = 1\nb = 1' $'# A comment.\na = 1\nb = 1  # noqa'
edit 0 "edit next to an old bare noqa" "$APP" $'x = 1  # noqa\ny = 1' $'x = 1  # noqa\ny = 2'
write 0 "Write keeping an old bare noqa" "$APP" $'import os  # noqa\nx = 1\n' $'import os  # noqa\nx = 2\n'
edit 0 "not a .py file"               "$REPO/$PKG/case.md" 'x' 'x  # noqa'
edit 0 "outside any git repo"         "$NOGIT/case.py" 'x' 'x  # noqa'

echo "-- excepts (a new one must say why it earns its keep, then gets a reminder)"
edit 2 "new except without a reason"  "$APP" '    y = f()' $'    try:\n        y = f()\n    except ValueError:\n        y = None'
edit R "reason on the except line"    "$APP" '    y = f()' $'    try:\n        y = f()\n    except ValueError:  # the provider sends blanks for missing amounts\n        y = None'
edit R "reason as the handler's first line" "$APP" '    y = f()' $'    try:\n        y = f()\n    except ValueError:\n        # The provider sends blanks for missing amounts.\n        y = None'
edit R "reason on the line above"     "$APP" '    y = f()' $'    try:\n        y = f()\n    # The provider sends blanks for missing amounts.\n    except ValueError:\n        y = None'
edit 2 "two new excepts, one without a reason" "$APP" '    y = f()' $'    try:\n        y = f()\n    except ValueError:  # the provider sends blanks\n        y = None\n    except KeyError:\n        y = 0'
edit 0 "old comment moved onto an old except" "$APP" $'    # the provider sends blanks\n    except ValueError:' '    except ValueError:  # the provider sends blanks'
edit 0 "old try/except re-indented"   "$APP" $'    try:\n        y = f()\n    except ValueError:\n        y = None' $'try:\n    y = f()\nexcept ValueError:\n    y = None'
edit 0 "reason added to an old except" "$APP" '    except Exception:' "    except Exception:  # noqa: BLE001 any failure is unhealthy. $TRIED"
edit R "new except with a reasoned noqa" "$APP" '    y = f()' $'    try:\n        y = f()\n    except Exception:  # noqa: BLE001 if one provider fails, carry on. '"$TRIED"$'\n        y = None'
edit 0 "new except in tests"          "$TEST" '    y = f()' $'    try:\n        y = f()\n    except ValueError:\n        y = None'
edit 2 "new except in another top-level folder" "$COMMONS" '    y = f()' $'    try:\n        y = f()\n    except ValueError:\n        y = None'
edit 0 "old bare noqa re-indented"    "$APP" $'    try:\n        y = f()  # noqa' $'    y = f()  # noqa'
edit 2 "a bare noqa still stops"      "$APP" '    y = f()' $'    try:\n        y = f()\n    except Exception:  # noqa: BLE001\n        y = None'

echo "-- comments (every new one goes on with a reminder)"
edit R "one-line comment"             "$APP" 'x = 1' $'# Why: the provider pads amounts.\nx = 1'
edit R "two-line comment"             "$APP" 'x = 1' $'# First line of a story.\n# Second line of the story.\nx = 1'
edit R "comment grows an old one"     "$APP" $'# Old line.\nx = 1' $'# Old line.\n# New second line.\nx = 1'
edit R "old comment reworded"         "$APP" $'# Old line.\nx = 1' $'# Old line, reworded.\nx = 1'
edit R "trailing comment on new code" "$APP" 'x = 1' $'x = 1\ny = 2  # the provider pads amounts'
edit R "comment added to old code"    "$APP" 'x = 1' 'x = 1  # the provider pads amounts'
edit R "new comment in a test"        "$TEST" '    y = f()' $'    # The fixture holds two providers.\n    y = f()'
edit 0 "old 2-line comment dedented"  "$APP" $'    try:\n        # First line.\n        # Second line.\n        x = 1' \
  $'    # First line.\n    # Second line.\n    x = 1'
edit 0 "old comment moved to the end of a line" "$APP" $'# the provider pads amounts\nx = 1' 'x = 1  # the provider pads amounts'
edit 0 "code changed beside an old comment" "$APP" 'x = 1  # the provider pads amounts' 'x = 2  # the provider pads amounts'
edit 0 "directive: shebang"           "$APP" 'import os' $'#!/usr/bin/env python\nimport os'
edit 0 "directive: type comment"      "$APP" 'x = []' 'x = []  # type: list[int]'
edit 0 "# inside a string"            "$APP" 'x = 1' $'x = 1\nURL = "https://x.test/#anchor"'
edit 0 "# line inside a triple-quoted argument" "$APP" '    y = f()' $'    y = render(\n        """\n        # Steps\n        """\n    )'

edit R "comment that starts with a number" "$APP" 'x = 60' 'x = 60  # 1 hour'
edit 2 "old_string ending at the file's last newline" "$APP" $'x = 1\n' $'x = 1  # noqa\n'

echo "-- comments in TOML, YAML and the Makefile (same reminder)"
mkdir -p "$REPO/configs/default"
CFG="$REPO/configs/default/api.yaml"
edit R "pyproject.toml comment"       "$REPO/pyproject.toml" '    "fastapi",' $'    # Async sessions need greenlet in production.\n    "fastapi",'
edit R "trailing pyproject comment"   "$REPO/pyproject.toml" '    "fastapi",' '    "fastapi",  # the API framework'
edit 0 "# inside a TOML string"       "$REPO/pyproject.toml" 'name = "x"' $'name = "x"\nurl = "https://x.test/#anchor"'
edit R "YAML comment in configs"      "$CFG" 'ttl_minutes: 10' 'ttl_minutes: 10  # the browser-binding cookie expires with it'
edit 0 "# inside a quoted YAML value" "$CFG" 'tag: a' "tag: '#a'"
edit 0 "# glued to a YAML value"      "$CFG" 'url: a' 'url: https://x.test/#frag'
edit R "gate.yaml comment"            "$REPO/.github/workflows/gate.yaml" '      - run: uv run pytest' $'      # Runs the whole suite on every PR.\n      - run: uv run pytest'
edit R "Makefile comment"             "$REPO/Makefile" $'test:\n\tuv run pytest\n' $'# The gate\'s test leg.\ntest:\n\tuv run pytest\n'
edit 0 "# inside a quoted recipe argument" "$REPO/Makefile" $'x:\n\t@echo a\n' $'x:\n\t@echo "# a"\n'

echo "-- comments: durability (every reminder asks; history words add a line)"
says yes "in a year"          "comment reminder asks the durability question" "$APP" 'x = 1' $'# The provider pads amounts.\nx = 1'
says yes "in a year"          "docstring reminder asks it too" "$APP" 'def f():' $'def f():\n    """Callers must hold the user lock."""'
says yes "reads like history" "a version that dropped something" "$REPO/pyproject.toml" '    "fastapi",' $'    # 2.1 dropped greenlet from its default install; async sessions need it in production.\n    "fastapi",'
says yes "reads like history" "no longer"                 "$APP" 'x = 1' $'# The provider no longer pads amounts.\nx = 1'
says yes "reads like history" "since a version"           "$APP" 'x = 1' $'# Needed since 3.2.\nx = 1'
says yes "reads like history" "removed in a version"      "$APP" 'x = 1' $'# The flag was removed in 2.0.\nx = 1'
says no  "reads like history" "a comment that says what holds" "$APP" 'x = 1' $'# Async sessions need greenlet in production.\nx = 1'
says no  "reads like history" "an RFC section number"     "$APP" 'x = 1' $'# RFC 8252 §7.3: native apps bind an ephemeral loopback port.\nx = 1'
says no  "reads like history" "since as a cause"          "$APP" 'x = 1' $'# Since the lock is held, nothing else writes here.\nx = 1'
says no  "reads like history" "a dropped connection"      "$APP" 'x = 1' $'# A dropped connection retries once.\nx = 1'
says no  "reads like history" "balances as of a date"     "$APP" 'x = 1' $'# Balances as of the oldest snapshot.\nx = 1'

echo "-- docstrings: functions, classes and tests off the outside surface (go on with the challenge)"
edit R "one-line docstring"           "$APP" 'def f():' $'def f():\n    """Do the thing."""'
edit R "multi-line docstring"         "$APP" 'def f():' $'def f():\n    """Do the thing.\n\n    Long story.\n    """'
edit R "single-quote triple docstring" "$APP" 'def f():' $'def f():\n    \'\'\'Do the thing.\'\'\''
edit R "r-prefixed docstring"         "$APP" 'def f():' $'def f():\n    r"""Match \\d+ digits."""'
edit R "U-prefixed docstring"         "$APP" 'def f():' $'def f():\n    U"""Do the thing."""'
edit R "plain-quote docstring"        "$APP" 'def f():' $'def f():\n    "Do the thing."'
edit R "class docstring"              "$APP" 'class Plan:' $'class Plan:\n    """A plan."""'
edit_in R "under a multi-line signature" "$APP" $'async def f(\n    x: int,\n) -> int:\n    return x' ') -> int:' $') -> int:\n    """Return x."""'
edit R "blank line between def and docstring" "$APP" 'def f():' $'def f():\n\n    """Do the thing."""'
edit_in R "bare opening quote already in the file" "$APP" $'SQL = """\nSELECT 1\n"""\n\ndef f():\n    pass' \
  $'def f():\n    pass' $'def f():\n    """\n    Do the thing.\n    """\n    pass'
edit R "test docstring"               "$TEST" 'def test_x():' $'def test_x():\n    """Checks x."""'
edit R "migration function docstring" "$MIGRATION" 'def upgrade() -> None:' $'def upgrade() -> None:\n    """Upgrade schema."""'
edit R "prose that starts with Returns" "$APP" 'def f():' $'def f():\n    """Returns None when the user has no provider, so callers skip it."""'
edit R "contract moved into the docstring" "$APP" $'# Callers must hold the user lock.\ndef f():' $'def f():\n    """Callers must hold the user lock."""'

echo "-- docstrings: module docstrings stop, except a migration's"
write 2 "module docstring, new file"  "$APP" '' $'"""Service helpers."""\nimport os\n'
edit_in 2 "module docstring under a leading comment" "$APP" $'# Generated by tools/x.py.\nimport os\n' 'import os' $'"""Service helpers."""\nimport os'
write 2 "module docstring in a router" "$ROUTER" '' $'"""User endpoints."""\nfrom fastapi import APIRouter\n'
write 0 "migration module docstring (Alembic's message)" "$MIGRATION" '' $'"""add x\n\nRevision ID: abc123\nRevises: def456\n"""\nfrom alembic import op\n'

echo "-- docstrings: parameter, return and exception sections stop everywhere"
ARGS=$'    """Do the thing.\n\n    Args:\n        x: the thing.\n    """'
edit 2 "Args: on a function"          "$APP" 'def f(x):' $'def f(x):\n'"$ARGS"
edit 2 "Returns: on a function"       "$APP" 'def f():' $'def f():\n    """Do the thing.\n\n    Returns:\n        The plan.\n    """'
edit 2 "Raises: on a function"        "$APP" 'def f():' $'def f():\n    """Do the thing.\n\n    Raises:\n        ValueError: on a blank.\n    """'
edit 2 "Sphinx :param field"          "$APP" 'def f(x):' $'def f(x):\n    """Do the thing.\n\n    :param x: the thing.\n    """'
edit 2 "numpy Parameters section"     "$APP" 'def f(x):' $'def f(x):\n    """Do the thing.\n\n    Parameters\n    ----------\n    x : int\n    """'
edit 2 "Args: after a comment"        "$APP" 'def f(x):' $'def f(x):\n    # why\n'"$ARGS"
edit 2 "Args: on an endpoint"         "$ROUTER" 'async def get_me(x):' $'async def get_me(x):\n'"$ARGS"
TOOL="$REPO/$PKG/api/mcp/tools/case.py"
edit R "Args: on an MCP tool (fastmcp's parameter descriptions)" "$TOOL" 'async def list_items(x):' $'async def list_items(x):\n'"$ARGS"
edit 2 "Returns: on an MCP tool"      "$TOOL" 'async def list_items():' $'async def list_items():\n    """List them.\n\n    Returns:\n        The items.\n    """'
edit 2 "Args: and Raises: on an MCP tool" "$TOOL" 'async def list_items(x):' $'async def list_items(x):\n    """List them.\n\n    Args:\n        x: the filter.\n\n    Raises:\n        ValueError: on a blank.\n    """'
edit 2 "Args: on an MCP response model" "$REPO/$PKG/api/mcp/responses.py" 'class OverviewResponse(MCPBaseModel):' $'class OverviewResponse(MCPBaseModel):\n'"$ARGS"
edit_in 2 "Args: added to an old docstring" "$APP" $'def f(x):\n    """Do the thing.\n\n    Long story.\n    """\n    pass' \
  $'    Long story.\n' $'    Long story.\n\n    Args:\n        x: the thing.\n'
edit_in 0 "old Args: left alone by an edit below" "$APP" $'def f(x):\n'"$ARGS"$'\n    return 1' '    return 1' '    return 2'

echo "-- docstrings: on the outside surface (goes on with a reminder)"
edit R "endpoint"                     "$ROUTER" 'async def get_me():' $'async def get_me():\n    """Return the signed-in user."""'
edit R "API response model"           "$REPO/$PKG/api/v1/responses.py" 'class UserResponse(APIBaseModel):' $'class UserResponse(APIBaseModel):\n    """A user of the team."""'
edit R "API request model"            "$REPO/$PKG/api/v1/core/schemas.py" 'class TagCreate(APIBaseModel):' $'class TagCreate(APIBaseModel):\n    """A tag to add to an item."""'
edit R "enum on the wire"             "$REPO/$PKG/types.py" 'class Status(str, Enum):' $'class Status(str, Enum):\n    """How urgent an item is."""'
edit R "MCP tool"                     "$REPO/$PKG/api/mcp/tools/case.py" 'async def list_items():' $'async def list_items():\n    """List the team\'s items."""'
edit R "MCP tool in a subpackage"     "$REPO/$PKG/api/mcp/tools/guides/case.py" 'async def get_guide():' $'async def get_guide():\n    """Call this first."""'
edit R "MCP output model"             "$REPO/$PKG/api/mcp/responses.py" 'class OverviewResponse(MCPBaseModel):' $'class OverviewResponse(MCPBaseModel):\n    """Current net position."""'
edit R "batch CLI command"            "$REPO/$PKG/batch/main.py" 'def run(task_name: str | None = None):' $'def run(task_name: str | None = None):\n    """Run the named batch task."""'

echo "-- docstrings: strings that are not docstrings (silent)"
edit 0 "SQL assigned to a name"       "$APP" 'x = 1' $'SQL = """\nSELECT 1\n"""\nx = 1'
edit 0 "text ending on a colon line"  "$APP" 'x = 1' $'GUIDE = """\\\nSteps:\n"""\nx = 1'
edit 0 "text with a markdown heading" "$APP" 'x = 1' $'GUIDE = """\n# Heading\n"""\nx = 1'
edit 0 "string argument on its own line" "$APP" '    y = f()' $'    y = cur.execute(\n        """\n        SELECT 1\n        """\n    )'
edit 0 "f-string argument"            "$APP" '    y = f()' $'    raise ValueError(\n        f"""bad {y}"""\n    )'
edit 0 "f-string where a docstring would go" "$APP" 'def f(x):' $'def f(x):\n    f"""{x}"""'
edit 0 "bytes where a docstring would go" "$APP" 'def f():' $'def f():\n    b"""raw"""'
edit 0 "test data string"             "$TEST" '    rows = parse(x)' $'    rows = parse("""\n    a,b\n    """)'
edit 0 "old docstring moves into a class" "$APP" $'def f():\n    """Do the thing."""\n    pass' $'class A:\n    def f():\n        """Do the thing."""\n        pass'
edit 0 "text with a Returns: line"    "$APP" 'x = 1' $'GUIDE = """\nReturns:\n"""\nx = 1'

echo "-- logs (any new log call reminds, whatever its level)"
edit R "new info log"                 "$APP" '    y = f()' $'    y = f()\n    log.info("rows_loaded", count=len(y))'
edit R "new async debug log"          "$APP" '    y = f()' $'    y = f()\n    await log.adebug("Lock user: Start")'
edit R "multi-line log call"          "$APP" '    y = f()' $'    y = f()\n    await log.awarning(\n        "refresh_expired",\n        user_id=1,\n    )'
edit R "logger name, not log"         "$APP" '    y = f()' $'    y = f()\n    logger.error("boom")'
edit 0 "log in tests"                 "$TEST" '    y = f()' $'    y = f()\n    log.info("rows_loaded")'
edit R "log in another top-level folder" "$COMMONS" '    y = f()' $'    y = f()\n    log.info("rows_loaded")'
edit 0 "old log re-indented"          "$APP" $'    try:\n        log.info("rows_loaded")' $'    log.info("rows_loaded")'
edit 0 "old comment moved onto an old log" "$APP" $'    # sampled upstream\n    log.info("rows_loaded")' '    log.info("rows_loaded")  # sampled upstream'
edit 0 "not a logger (catalog.info)"  "$APP" '    y = f()' $'    y = f()\n    catalog.info("x")'

echo "-- tests: a new one that calls the code directly stops; one through a boundary reminds"
UNIT="$REPO/tests/unit/test_case.py"
mkdir -p "$REPO/tests/migrations" "$REPO/tests/config_integrity" "$REPO/tests/contracts" "$REPO/tests/unit/api"
DIRECT=$'def test_x():\n    assert sanitize("a ") == "a"'
write 2 "calls a helper directly"       "$UNIT" '' "$DIRECT"
write 2 "the next test's boundary does not count" "$UNIT" '' $'def test_x():\n    assert sanitize("a") == "a"\n\n\ndef test_y(client):\n    client.get("/x")\n'
write 2 "direct test in a class"        "$UNIT" '' $'class TestX:\n    def test_y(self):\n        assert sanitize("a") == "a"\n\n    def test_z(self, client):\n        client.get("/x")\n'
edit 2 "direct test beside an old one"  "$UNIT" $'def test_x(client):\n    client.get("/x")' $'def test_x(client):\n    client.get("/x")\n\n\ndef test_y():\n    assert sanitize("a") == "a"'
write 2 "a boto3 client is not the test client" "$UNIT" '' $'def test_x():\n    client = boto3.client("logs")\n    assert client.describe_log_streams(logGroupName="g")\n'
write 2 "the OpenAPI document outside its contract file" "$UNIT" '' $'def test_x():\n    assert app.openapi()["paths"]\n'
write R "through an endpoint"           "$UNIT" '' $'def test_x(client):\n    assert client.get("/x").status_code == 200\n'
write R "through an MCP tool"           "$UNIT" '' $'def test_x(monkeypatch, user):\n    assert call_tool(monkeypatch, user.id, "list_items") == []\n'
write R "through a batch task"          "$UNIT" '' $'def test_x():\n    assert task_sync_daily()["users"] == 1\n'
write R "through the batch CLI"         "$UNIT" '' $'def test_x():\n    assert CliRunner().invoke(run, ["--task_name", "t"]).exit_code == 0\n'
write R "through a project boundary"    "$UNIT" '' $'def test_x():\n    release.run(conn)\n'
write 2 "a name that only starts like one" "$UNIT" '' $'def test_x():\n    release.runner(conn)\n'
write R "signature on its own lines"    "$UNIT" '' $'def test_x(\n    monkeypatch,\n    user,\n):\n    assert call_tool(monkeypatch, user.id, "x") == []\n'
write 0 "contract check: migration test" "$REPO/tests/migrations/test_case.py" '' "$DIRECT"
write 0 "contract check: shipped config" "$REPO/tests/config_integrity/test_case.py" '' "$DIRECT"
write 0 "contract check: the OpenAPI document" "$REPO/tests/contracts/test_openapi.py" '' $'def test_x():\n    assert app.openapi()["paths"]\n'
write 0 "contract check: the email templates" "$REPO/tests/contracts/test_emails.py" '' $'def test_x():\n    assert render("welcome", "en")\n'
write 2 "a contract-like file outside tests/contracts" "$REPO/tests/unit/api/test_openapi.py" '' "$DIRECT"
write 0 "test-like name outside a test file" "$TEST" '' "$DIRECT"
write 0 "new helper in a test file"     "$UNIT" '' $'def _rows():\n    return sanitize("a")\n'
edit 0 "old direct test edited"         "$UNIT" "$DIRECT" $'def test_x():\n    assert sanitize("b ") == "b"'
edit 0 "old direct test gains a fixture" "$UNIT" "$DIRECT" $'def test_x(monkeypatch):\n    assert sanitize("a ") == "a"'
edit 0 "old direct test moved into a class" "$UNIT" "$DIRECT" $'class TestX:\n    def test_x(self):\n        assert sanitize("a ") == "a"'

echo "-- tests: a new one that calls a write endpoint and does not read the database after it stops"
UNREAD=$'def test_x(client):\n    response = client.post("/x", json={"a": 1})\n    assert response.status_code == 201\n'
write 2 "write checked by its response only" "$UNIT" '' "$UNREAD"
write 2 "a GET after the write is not the check" "$UNIT" '' $'def test_x(client):\n    client.patch("/x/1", json={"a": 1})\n    assert client.get("/x/1").json()["a"] == 1\n'
write 2 "refused write checked by its error only" "$UNIT" '' $'def test_x(client):\n    response = client.delete("/x/9999")\n    assert_response_exception(response, APIException.X_NOT_FOUND)\n'
write 2 "db_session used only before the write" "$UNIT" '' $'def test_x(client, db_session):\n    row = mock_x(db_session)\n    client.put(f"/x/{row.id}", json={"a": 1})\n'
write 2 "the next test's database read does not count" "$UNIT" '' $'def test_x(client):\n    client.post("/x")\n\n\ndef test_y(client, db_session):\n    client.get("/x")\n    assert db_session.scalar(select(X))\n'
write 2 "write test in a class"         "$UNIT" '' $'class TestX:\n    def test_y(self, client):\n        client.patch(\n            "/x/1",\n            json={"a": 1},\n        )\n'
edit 2 "write test beside an old one"   "$UNIT" $'def test_x(client):\n    client.get("/x")' $'def test_x(client):\n    client.get("/x")\n\n\ndef test_y(client):\n    client.post("/x")'
write 2 "both stops in one edit"        "$UNIT" '' "$DIRECT"$'\n\n\n'"${UNREAD/test_x/test_y}"
write R "write test that reads the database" "$UNIT" '' $'def test_x(client, db_session):\n    client.patch("/x/1", json={"a": 1})\n    db_session.expire_all()\n    assert db_session.scalar(select(X.a).where(X.id == 1)) == 1\n'
write R "refused write that reads the database" "$UNIT" '' $'def test_x(client, db_session):\n    client.delete("/x/1")\n    db_session.expire_all()\n    assert db_session.get(X, 1) is not None\n'
write R "database read inside a helper" "$UNIT" '' $'def test_x(client, db_session):\n    client.post("/x", json={"a": 1})\n    assert_stored_x(db_session, a=1)\n'
write R "another object's post is not a write call" "$UNIT" '' $'def test_x(client):\n    http_client.post("/x")\n    assert client.get("/x").status_code == 200\n'
edit 0 "old write test edited"          "$UNIT" "$UNREAD" "${UNREAD/json=/data=}"
write 0 "write test in a contract check" "$REPO/tests/migrations/test_case.py" '' "$UNREAD"
write 0 "write test in the email templates check" "$REPO/tests/contracts/test_emails.py" '' "$UNREAD"
says yes "call a boundary (an endpoint, an MCP tool, a batch task, the batch CLI or \`release.run\`)" \
  "the stop names every part's boundaries and the answered one" "$UNIT" '' "$DIRECT"

echo "-- parts: a check that belongs to a part runs only in a project that picked it"
stack '[]' '[]'
write 0 "no part, no boundary: a direct test"  "$UNIT" '' "$DIRECT"
write 0 "no part: an endpoint test"            "$UNIT" '' "$UNREAD"
edit 2 "no part: Args: on an MCP tool"         "$TOOL" 'async def list_items(x):' $'async def list_items(x):\n'"$ARGS"
write 2 "no part: a module docstring in database/versions" "$MIGRATION" '' $'"""add x\n\nRevision ID: abc123\n"""\nfrom alembic import op\n'
says no "Alembic" "no part: the module docstring stop names no migration" "$APP" 'import os' $'"""Service helpers."""\nimport os'
says yes "prefers code that explains itself" "no part: an endpoint's docstring gets the reminder for internal code" \
  "$ROUTER" 'async def get_me():' $'async def get_me():\n    """Return the signed-in user."""'
stack '[]' '["release.run"]'
write 2 "no part, a boundary answered: a direct test" "$UNIT" '' "$DIRECT"
write R "no part: through the answered boundary" "$UNIT" '' $'def test_x():\n    release.run(conn)\n'
says yes "call a boundary (\`release.run\`)" "no part: the stop names only the answered boundary" "$UNIT" '' "$DIRECT"
says no "mock_" "no part: the stop names no database helper" "$UNIT" '' "$DIRECT"
stack '["batch"]' '[]'
write R "batch: through a batch task"          "$UNIT" '' $'def test_x():\n    assert task_sync_daily()["users"] == 1\n'
write 2 "batch: an endpoint is no boundary"    "$UNIT" '' $'def test_x(client):\n    assert client.get("/x").status_code == 200\n'
write 2 "batch: a migration test is no contract check" "$REPO/tests/migrations/test_case.py" '' "$DIRECT"
says yes "(--help)" "batch: the CLI docstring's reader is --help" \
  "$REPO/$PKG/batch/main.py" 'def run(task_name: str | None = None):' $'def run(task_name: str | None = None):\n    """Run the named batch task."""'
says no "ERR_" "batch: the CLI docstring's reminder asks for no API error code" \
  "$REPO/$PKG/batch/main.py" 'def run(task_name: str | None = None):' $'def run(task_name: str | None = None):\n    """Run the named batch task."""'
stack '["api"]' '[]'
write R "api without database: a write checked by its response" "$UNIT" '' "$UNREAD"
says yes "(the MCP client)" "api: the MCP tool's reader is the MCP client" \
  "$TOOL" 'async def list_items():' $'async def list_items():\n    """List the team\'s items."""'
stack '["database"]' '[]'
write 0 "database alone: a direct test"        "$UNIT" '' "$DIRECT"
write 0 "database alone: a migration module docstring" "$MIGRATION" '' $'"""add x\n\nRevision ID: abc123\n"""\nfrom alembic import op\n'
# Copier renders an empty test_boundaries answer as null.
stack "$EVERY_PART" null
write 2 "null boundaries: a direct test still stops" "$UNIT" '' "$DIRECT"
edit 2 "null boundaries: the other checks still run" "$APP" '    y = f()' $'    try:\n        y = f()\n    except ValueError:\n        y = None'
stack "$EVERY_PART" '["release.run"]'

echo "-- config: switching a check off stops until a reason in the form sits next to it"
PY="$REPO/pyproject.toml"
BASE=$'[project]\ndependencies = ["fastapi"]\n\n[tool.ruff.lint]\nselect = [\n    "F",  # Pyflakes\n    "E",  # pycodestyle\n]\n\n[tool.basedpyright]\ntypeCheckingMode = "recommended"\ninclude = ["app"]\n\n[tool.pytest.ini_options]\naddopts = "-v"\n'
edit_in 2 "ruff ignore added"             "$PY" "$BASE" $'select = [' $'ignore = ["E501"]\nselect = ['
edit_in 2 "per-file-ignores entry"        "$PY" "$BASE" $'[tool.basedpyright]' $'[tool.ruff.lint.per-file-ignores]\n"tests/**" = ["E501"]\n\n[tool.basedpyright]'
edit_in 2 "item added to multi-line ignore" "$PY" $'[tool.ruff.lint]\nignore = [\n    "E501",\n]\n' '    "E501",' $'    "E501",\n    "E712",'
edit_in 2 "rule removed from select"      "$PY" "$BASE" $'    "E",  # pycodestyle\n' ''
edit_in 2 "type-check report turned off"  "$PY" "$BASE" 'typeCheckingMode = "recommended"' $'typeCheckingMode = "recommended"\nreportUnusedImport = false'
edit_in 2 "type-check mode lowered"       "$PY" "$BASE" 'typeCheckingMode = "recommended"' 'typeCheckingMode = "off"'
edit_in 2 "type-check mode lowered to standard" "$PY" "$BASE" 'typeCheckingMode = "recommended"' 'typeCheckingMode = "standard"'
edit_in 2 "type-check mode lowered to strict" "$PY" "$BASE" 'typeCheckingMode = "recommended"' 'typeCheckingMode = "strict"'
edit_in 2 "type-check warnings let pass"  "$PY" "$BASE" 'typeCheckingMode = "recommended"' $'typeCheckingMode = "recommended"\nfailOnWarnings = false'
edit_in 2 "type-check scope narrowed"     "$PY" "$BASE" 'include = ["app"]' 'include = []'
edit_in 2 "pytest deselect"               "$PY" "$BASE" 'addopts = "-v"' 'addopts = "-v --deselect tests/test_x.py::test_y"'
edit_in 2 "pytest deselect=, in a multi-line addopts" "$PY" $'[tool.pytest.ini_options]\naddopts = [\n    "-v",\n]\n' \
  '    "-v",' $'    "-v",\n    "--deselect=tests/test_x.py::test_y",'
edit_in 2 "pytest plugin turned off, glued to its -p" "$PY" "$BASE" 'addopts = "-v"' 'addopts = "-v -pno:warnings"'
edit_in 2 "pytest plugin turned off, as list items" "$PY" "$BASE" 'addopts = "-v"' 'addopts = ["-v", "-p", "no:warnings"]'
edit_in 2 "pytest plugin turned off, in a multi-line addopts" "$PY" $'[tool.pytest.ini_options]\naddopts = [\n    "-v",\n]\n' \
  '    "-v",' $'    "-v",\n    "-p",\n    "no:warnings",'
edit_in 2 "tests selected by name, as list items" "$PY" "$BASE" 'addopts = "-v"' "addopts = ['-v', '-k', 'smoke']"
edit_in 2 "tests selected by name, at the start of a multi-line string's line" "$PY" "$BASE" 'addopts = "-v"' \
  $'addopts = """\n-k smoke\n"""'
edit_in 2 "tests selected by mark"        "$PY" "$BASE" 'addopts = "-v"' "addopts = \"-v -m 'not slow'\""
edit_in 2 "tests selected by mark, as list items" "$PY" "$BASE" 'addopts = "-v"' 'addopts = ["-v", "-m", "not slow"]'
edit_in 2 "tests selected by mark, glued to its -m" "$PY" "$BASE" 'addopts = "-v"' 'addopts = "-v -mslow"'
edit_in 0 "report chars that hold m"      "$PY" "$BASE" 'addopts = "-v"' 'addopts = "-v -rm"'
edit_in 0 "pytest option that tightens" "$PY" "$BASE" 'addopts = "-v"' 'addopts = ["-v", "--strict-markers"]'
edit_in 2 "typed except check off"       "$PY" "$BASE" $'[tool.basedpyright]' $'[tool.ruff.lint.flake8-bandit]\ncheck-typed-exception = false\n\n[tool.basedpyright]'
edit_in 2 "per-file-ignores reason with no Tried sentence" "$PY" "$BASE" $'[tool.basedpyright]' \
  $'[tool.ruff.lint.per-file-ignores]\n# E501: the fixtures hold long URLs.\n"tests/**" = ["E501"]\n\n[tool.basedpyright]'
edit_in 2 "rule removed, its reason only in an old comment" "$PY" \
  $'[tool.ruff.lint]\nselect = [\n    "F",\n    # E: ruff format owns layout. '"$TRIED"$'\n    "E",\n]\n' $'    "E",\n' ''
says yes "Read the current documentation" "a config stop sends the agent to the docs first" "$PY" \
  $'[tool.ruff.lint]\nignore = []' $'[tool.ruff.lint]\nignore = ["E501"]'
edit_in R "per-file-ignores reason above the entry" "$PY" "$BASE" $'[tool.basedpyright]' \
  $'[tool.ruff.lint.per-file-ignores]\n# E501: the fixtures hold long URLs.\n# '"$TRIED"$'\n"tests/**" = ["E501"]\n\n[tool.basedpyright]'
edit_in R "ignore with the reason on its line" "$PY" "$BASE" $'select = [' "ignore = [\"E501\"]  # E501: long URLs. $TRIED"$'\nselect = ['
edit_in R "tests selected by mark, reason above" "$PY" "$BASE" 'addopts = "-v"' \
  "# The nightly job runs the slow tests. $TRIED"$'\naddopts = "-v -m \'not slow\'"'
edit_in R "rule removed from select, reason where it was" "$PY" "$BASE" $'    "E",  # pycodestyle\n' \
  "    # E: ruff format owns layout. $TRIED"$'\n'
edit_in 0 "rule added to select"          "$PY" "$BASE" $'    "E",  # pycodestyle\n' $'    "E",  # pycodestyle\n    "BLE001",\n'
edit_in R "select entry comment reworded (no stop, the comment reminds)" "$PY" "$BASE" '    "E",  # pycodestyle' '    "E",  # pycodestyle errors'
edit_in R "type-check mode lowered, reason above" "$PY" "$BASE" 'typeCheckingMode = "recommended"' \
  "# This tool's generated stubs hold no types. $TRIED"$'\ntypeCheckingMode = "standard"'
edit_in 0 "type-check mode raised"        "$PY" "$BASE" 'typeCheckingMode = "recommended"' 'typeCheckingMode = "all"'
edit_in 0 "type-check scope widened"      "$PY" "$BASE" 'include = ["app"]' 'include = ["app", "tests"]'
edit_in 0 "unrelated section"             "$PY" "$BASE" 'dependencies = ["fastapi"]' 'dependencies = ["fastapi", "exclude-me"]'
edit_in 2 "single-quoted rule removed from select" "$PY" $'[tool.ruff.lint]\nselect = [\'F\', \'E\']\n' \
  "select = ['F', 'E']" "select = ['F']"

echo "-- config: a warning filter other than error lets a warning pass the tests"
FW=$'[tool.pytest.ini_options]\nfilterwarnings = [\n    "error",\n]\n'
FW1=$'[tool.pytest.ini_options]\nfilterwarnings = ["error"]\n'
edit_in 2 "error filter removed"          "$PY" "$FW" $'    "error",\n' ''
edit_in 2 "filterwarnings line removed"   "$PY" "$FW1" $'filterwarnings = ["error"]\n' ''
edit_in 2 "filterwarnings emptied"        "$PY" "$FW1" 'filterwarnings = ["error"]' 'filterwarnings = []'
edit_in 2 "ignore filter added"           "$PY" "$FW" '    "error",' $'    "error",\n    "ignore::DeprecationWarning",'
edit_in 2 "single-quoted ignore filter added" "$PY" "$FW" '    "error",' \
  $'    "error",\n    \'ignore:function ham\\(\\) is deprecated:DeprecationWarning\','
edit_in 2 "filter that shows warnings, beside the error filter" "$PY" "$FW1" 'filterwarnings = ["error"]' \
  'filterwarnings = ["error", "default::UserWarning"]'
edit_in 2 "warning filter in addopts"     "$PY" "$BASE" 'addopts = "-v"' 'addopts = "-v -W ignore::DeprecationWarning"'
edit_in 2 "warning filter in addopts, as list items" "$PY" "$BASE" 'addopts = "-v"' 'addopts = ["-v", "-W", "ignore"]'
edit_in 2 "warning filter in addopts, glued to its -W" "$PY" "$BASE" 'addopts = "-v"' 'addopts = "-v -Wignore"'
edit_in 2 "-W alone on its line, whatever filter follows" "$PY" $'[tool.pytest.ini_options]\naddopts = [\n    "-v",\n]\n' \
  '    "-v",' $'    "-v",\n    "-W",\n    "error",'
edit_in R "ignore filter added, reason on its line" "$PY" "$FW" '    "error",' \
  $'    "error",\n    "ignore::DeprecationWarning",  # The SDK warns on import. '"$TRIED"
edit_in R "error filter removed, reason where it was" "$PY" "$FW" $'    "error",\n' \
  "    # The suite checks each warning with pytest.warns. $TRIED"$'\n'
edit_in 0 "error filter for a category added" "$PY" "$FW" '    "error",' $'    "error",\n    "error::UserWarning",'
edit_in 0 "single-quoted error filter added" "$PY" "$FW" '    "error",' $'    "error",\n    \'error::UserWarning\','
edit_in 0 "ignore filter removed"         "$PY" $'[tool.pytest.ini_options]\nfilterwarnings = [\n    "error",\n    "ignore::DeprecationWarning",\n]\n' \
  $'    "ignore::DeprecationWarning",\n' ''
edit_in 0 "error filter kept as its list grows into lines" "$PY" "$FW1" 'filterwarnings = ["error"]' \
  $'filterwarnings = [\n    "error",\n]'
edit_in 0 "error filter in addopts"       "$PY" "$BASE" 'addopts = "-v"' 'addopts = "-v -W error::UserWarning"'
edit_in 0 "error filter in addopts, as list items" "$PY" "$BASE" 'addopts = "-v"' 'addopts = ["-v", "-W", "error"]'

echo "-- config: a select in a ruff config that extends another replaces that config's rule list"
EXT=$'[tool.ruff]\nextend = "ruff.base.toml"\n\n[tool.ruff.lint]\nextend-select = ["B"]\n'
edit_in 2 "select in a config that extends a base" "$PY" "$EXT" 'extend-select = ["B"]' $'extend-select = ["B"]\nselect = ["F"]'
edit_in 2 "multi-line select there"       "$PY" "$EXT" 'extend-select = ["B"]' $'extend-select = ["B"]\nselect = [\n    "F",\n]'
edit_in 2 "select under [tool.ruff] there" "$PY" "$EXT" 'extend = "ruff.base.toml"' $'extend = "ruff.base.toml"\nselect = ["F"]'
edit_in R "select there with a reason"    "$PY" "$EXT" 'extend-select = ["B"]' \
  $'extend-select = ["B"]\n'"select = [\"F\"]  # F: this tool keeps only Pyflakes. $TRIED"
edit_in 0 "extend-select there"           "$PY" "$EXT" 'extend-select = ["B"]' 'extend-select = ["B", "ANN"]'
edit_in 0 "an item added to a select there" "$PY" $'[tool.ruff]\nextend = "ruff.base.toml"\n\n[tool.ruff.lint]\nselect = [\n    "F",\n]\n' \
  '    "F",' $'    "F",\n    "E",'
edit_in 0 "select in a config that extends nothing" "$PY" $'[tool.ruff.lint]\nignore = []\n' 'ignore = []' $'select = ["F"]\nignore = []'
says yes "extend-select adds to it" "the stop names extend-select" "$PY" "$EXT" "$EXT"$'select = ["F"]\n'
edit_in 2 "ruff extend removed"           "$PY" "$EXT" $'extend = "ruff.base.toml"\n' ''
edit_in 2 "ruff extend pointed elsewhere" "$PY" "$EXT" 'extend = "ruff.base.toml"' 'extend = "lax.toml"'
EXTS=$'[tool.basedpyright]\nextends = "basedpyright.base.json"\ninclude = ["app"]\n'
edit_in 2 "basedpyright extends removed"  "$PY" "$EXTS" $'extends = "basedpyright.base.json"\n' ''
edit_in R "ruff extend removed, reason where it was" "$PY" "$EXT" $'extend = "ruff.base.toml"\n' \
  "# This tool keeps its own rule list. $TRIED"$'\n'
edit_in 0 "ruff extend kept as its section grows" "$PY" "$EXT" $'[tool.ruff]\nextend = "ruff.base.toml"' \
  $'[tool.ruff]\nline-length = 100\nextend = "ruff.base.toml"'

echo "-- config: the shared base files stop every edit, reason or not: each update rewrites them"
RB="$REPO/ruff.base.toml"
edit_in 2 "a rule dropped from ruff.base.toml" "$RB" $'[lint]\nselect = ["F", "E"]\n' 'select = ["F", "E"]' 'select = ["F"]'
edit_in 2 "a rule added to ruff.base.toml" "$RB" $'[lint]\nselect = ["F"]\n' 'select = ["F"]' 'select = ["F", "E"]'
edit_in 2 "a ruff.base.toml change with a reason" "$RB" $'[lint]\nignore = []\n' 'ignore = []' \
  "ignore = [\"E501\"]  # E501: long URLs. $TRIED"
write 2 "basedpyright.base.json rewritten" "$REPO/basedpyright.base.json" $'{\n  "reportUnreachable": "error"\n}\n' \
  $'{\n  "reportUnreachable": false\n}\n'
says yes "Change the template instead" "the base-file stop sends the change to the template" "$RB" \
  $'[lint]\nselect = ["F"]\n' $'[lint]\nselect = []\n'
JS="$REPO/.jscpd.json"
edit_in 2 "minLines raised in .jscpd.json" "$JS" $'{\n  "minLines": 9\n}\n' '"minLines": 9' '"minLines": 99'
edit_in 2 "a path left out in .jscpd.json" "$JS" $'{\n  "ignore": ["tests/**"]\n}\n' '"tests/**"' '"tests/**", "app/**"'
mkdir -p "$REPO/.github/gate-checks"
edit_in 2 "CI's copy of .jscpd.json edited" "$REPO/.github/gate-checks/.jscpd.json" \
  $'{\n  "minLines": 9\n}\n' '"minLines": 9' '"minLines": 99'
says yes "goes between \`# jscpd:ignore-start\` and \`# jscpd:ignore-end\`" "the .jscpd.json stop points to the markers" \
  "$JS" $'{\n  "minLines": 9\n}\n' $'{\n  "minLines": 99\n}\n'
says no "jscpd:ignore-start" "the ruff.base.toml stop names no jscpd marker" "$RB" \
  $'[lint]\nselect = ["F"]\n' $'[lint]\nselect = []\n'
PC="$REPO/.pre-commit-config.yaml"
PCBASE=$'repos:\n  - repo: local\n    hooks:\n      - id: ruff\n      - id: bandit\n        args: ["-ll"]\n'
edit_in 2 "pre-commit exclude added"      "$PC" "$PCBASE" '      - id: ruff' $'      - id: ruff\n        exclude: ^tests/'
edit_in 2 "pre-commit hook removed"       "$PC" "$PCBASE" $'      - id: bandit\n' ''
edit_in 2 "bandit skip arg"               "$PC" "$PCBASE" 'args: ["-ll"]' 'args: ["-ll", "--skip", "B101"]'
edit_in R "pre-commit exclude, reason above" "$PC" "$PCBASE" '      - id: ruff' \
  $'      - id: ruff\n        # The tests hold generated code.\n        # '"$TRIED"$'\n        exclude: ^tests/'
edit_in 0 "pre-commit hook added"         "$PC" "$PCBASE" '      - id: ruff' $'      - id: ruff\n      - id: check-json'
edit_in 0 "pre-commit hook added with its files" "$PC" "$PCBASE" '      - id: ruff' \
  $'      - id: ruff\n      - id: check-json\n        files: ^app/\n        exclude: ^app/generated/'
edit_in 2 "top-level exclude below an added hook" "$PC" "$PCBASE" '        args: ["-ll"]' \
  $'        args: ["-ll"]\n      - id: check-json\nexclude: ^generated/'
PCTEMPLATE=$'repos:\n  - repo: local\n    hooks:\n      - id: template-hooks\n        entry: uv run pre-commit run --config pre-commit.base.yaml --files\n'
edit_in 2 "template-hooks entry changed" "$PC" "$PCTEMPLATE" 'entry: uv run pre-commit run --config' \
  'entry: uv run pre-commit run ruff-check --config'
PB="$REPO/pre-commit.base.yaml"
edit_in 2 "template hook removed from pre-commit.base.yaml" "$PB" "$PCBASE" $'      - id: bandit\n' ''
edit_in R "template hook removed, reason added" "$PB" "$PCBASE" $'      - id: bandit\n        args: ["-ll"]\n' \
  "      # bandit runs in CI only. $TRIED"$'\n'
MK="$REPO/Makefile"
MKBASE=$'lint-check:\n\tuv run ruff check app\n\tuv run ruff format --check app\n\ngate: lint-check typecheck security test\n\t@echo ok\n'
edit_in 0 "lint widened to tests"         "$MK" "$MKBASE" $'\tuv run ruff check app\n' $'\tuv run ruff check app tests\n'
edit_in 2 "gate leg dropped"              "$MK" "$MKBASE" 'gate: lint-check typecheck security test' 'gate: lint-check typecheck test'
edit_in 0 "gate leg added"                "$MK" "$MKBASE" 'gate: lint-check typecheck security test' 'gate: lint-check typecheck security test docs'
edit_in 2 "lint line removed"             "$MK" "$MKBASE" $'\tuv run ruff check app\n\tuv run ruff format --check app\n' ''
edit_in 2 "errors ignored"                "$MK" "$MKBASE" $'\tuv run ruff check app\n' $'\tuv run ruff check app || true\n'
edit_in R "gate leg dropped, reason above" "$MK" "$MKBASE" 'gate: lint-check typecheck security test' \
  "# The gate runs bandit in CI only. $TRIED"$'\ngate: lint-check typecheck test'
edit_in R "errors ignored, reason above"  "$MK" "$MKBASE" $'\tuv run ruff check app\n' \
  "# Lint only warns here. $TRIED"$'\n\tuv run ruff check app || true\n'
MKDUP=$'duplication:\n\tuv run jscpd .\n'
edit_in 2 "jscpd line removed"            "$MK" "$MKDUP" $'\tuv run jscpd .\n' ''
edit_in 0 "jscpd line kept, scan widened" "$MK" "$MKDUP" $'\tuv run jscpd .\n' $'\tuv run jscpd . scripts\n'

echo "-- config: every edit to bandit's, pytest's or ruff's own files stops until it adds a reason on lines of its own"
BANDIT="$REPO/.bandit"; PINI="$REPO/pytest.ini"; RT="$REPO/ruff.toml"
edit_in 2 ".bandit skips a test"          "$BANDIT" $'[bandit]\n' '[bandit]' $'[bandit]\nskips = B101'
write 2 "pytest.ini created, even empty" "$PINI" '' ''
edit_in 2 ".pytest.ini edited, even to tighten" "$REPO/.pytest.ini" $'[pytest]\naddopts = -v\n' 'addopts = -v' \
  'addopts = -v --strict-markers'
write 2 "pytest.toml created"             "$REPO/pytest.toml" '' $'[pytest]\naddopts = ["-v"]\n'
write 2 ".pytest.toml created"            "$REPO/.pytest.toml" '' $'[pytest]\naddopts = ["-v"]\n'
edit_in 2 "ruff.toml ignore"              "$RT" $'line-length = 100\n' 'line-length = 100' $'line-length = 100\nignore = ["E501"]'
edit_in 2 "select in a ruff.toml that extends a base" "$RT" $'extend = "ruff.base.toml"\n\n[lint]\n' '[lint]' $'[lint]\nselect = ["F"]'
write 2 ".ruff.toml created in a folder"  "$REPO/$PKG/.ruff.toml" '' $'extend = "../pyproject.toml"\n'
edit_in 2 "reason after the entry"        "$BANDIT" $'[bandit]\n' '[bandit]' \
  $'[bandit]\n'"skips = B101  # B101: the tests assert. $TRIED"
edit_in 2 "reason with no Tried sentence" "$PINI" $'[pytest]\naddopts = -v\n' 'addopts = -v' \
  $'# The suite prints its own warnings.\naddopts = -v -p no:warnings'
says yes "\`#\` comment lines of their own" "the stop says where the reason goes" "$BANDIT" \
  $'[bandit]\n' $'[bandit]\nskips = B101'
edit_in R ".bandit skips, reason above"   "$BANDIT" $'[bandit]\n' '[bandit]' \
  $'[bandit]\n# B101: the tests assert.\n# '"$TRIED"$'\nskips = B101'
write R "pytest.ini created with its reason" "$PINI" '' \
  "# The generated suite needs its own settings. $TRIED"$'\n[pytest]\naddopts = -v\n'
edit_in R "ruff.toml entry removed, reason where it was" "$RT" $'[lint]\nselect = ["F", "E"]\n' \
  $'select = ["F", "E"]\n' "# E: ruff format owns layout. $TRIED"$'\nselect = ["F"]\n'

echo "-- config: CI workflows are not checked (the owner reviews them in the PR)"
edit_in 0 "gate.yaml loosened"            "$REPO/.github/workflows/gate.yaml" $'      - run: uv run pytest tests/ --cov\n' 'uv run pytest tests/ --cov' 'uv run pytest tests/ --cov || true'
edit_in 0 "other workflow loosened"       "$REPO/.github/workflows/build.yaml" $'      - run: uv run pytest\n' 'uv run pytest' 'uv run pytest || true'

echo "-- secret scan skips: gitleaks:allow, .gitleaksignore and .gitleaks.toml (must stop)"
YAML="$REPO/compose.yaml"
DOC="$REPO/notes.md"
IGNORE="$REPO/.gitleaksignore"
GL="$REPO/.gitleaks.toml"
Q="'''"
OWN=$'[extend]\nuseDefault = true\n'
edit 2 "gitleaks:allow, no reason"        "$APP" 'KEY = "k"' 'KEY = "k"  # gitleaks:allow'
edit 2 "gitleaks:allow, a why, no Tried"  "$APP" 'KEY = "k"' 'KEY = "k"  # gitleaks:allow a fixture key'
edit 2 "gitleaks:allow, reason above with code between" "$APP" 'KEY = "k"' \
  "# A fixture key. $TRIED"$'\nx = 1\nKEY = "k"  # gitleaks:allow'
edit 2 "gitleaks:allow in YAML, no reason" "$YAML" 'key: k' 'key: k  # gitleaks:allow'
edit 2 "gitleaks:allow in Markdown, no reason" "$DOC" 'key k' 'key k <!-- gitleaks:allow -->'
write 2 "fingerprint, no reason"          "$IGNORE" '' $'tests/a.py:github-pat:3\n'
write 2 "fingerprint, reason after it"    "$IGNORE" '' "tests/a.py:github-pat:3  # A fixture key. $TRIED"$'\n'
write 2 "fingerprint under another one's reason" "$IGNORE" '' \
  "# A fixture key. $TRIED"$'\ntests/a.py:github-pat:3\ntests/a.py:github-pat:4\n'
edit_in 2 "allowlist path, no reason"     "$GL" "$OWN" "$OWN" "$OWN"$'\n[[allowlists]]\n'"paths = [${Q}^tests/${Q}]"
edit_in 2 "multi-line regexes, reason above the key only" "$GL" "$OWN" "$OWN" \
  "$OWN"$'\n[[allowlists]]\n'"# Fixture keys. $TRIED"$'\nregexes = [\n'"  ${Q}^acme_${Q},"$'\n]'
edit_in 2 "allowlist item after one that holds =" "$GL" "$OWN" "$OWN" \
  "$OWN"$'\n[[allowlists]]\nregexes = [\n'"  'x=y',"$'\n'"  ${Q}^acme_${Q},"$'\n]'
edit_in 2 "a rule's allowlist stopword, no reason" "$GL" "$OWN" "$OWN" \
  "$OWN"$'\n[[rules]]\nid = "generic-api-key"\n[[rules.allowlists]]\nstopwords = ["fixture"]'
edit_in 2 "STOPWORDS in capitals, no reason" "$GL" "$OWN" "$OWN" "$OWN"$'\n[[allowlists]]\nSTOPWORDS = ["fixture"]'
edit_in 2 "disabledRules entry, no reason" "$GL" "$OWN" "$OWN" "$OWN"'disabledRules = ["generic-api-key"]'
edit_in 2 "disabledrules in lower case, no reason" "$GL" "$OWN" "$OWN" "$OWN"'disabledrules = ["generic-api-key"]'
write 2 "new file with a rule, no useDefault" "$GL" '' $'[[rules]]\nid = "acme-key"\n'"regex = ${Q}acme_[a-z0-9]{32}${Q}"$'\n'
write 2 "new file with only a comment"    "$GL" '' $'# The scan settings.\n'
edit_in 2 "useDefault removed"            "$GL" "$OWN" $'useDefault = true\n' ''
edit_in 2 "useDefault turned off"         "$GL" "$OWN" 'useDefault = true' 'useDefault = false'
edit_in 2 "the [extend] header removed"   "$GL" "$OWN" $'[extend]\n' ''
write 2 "new file with useDefault outside [extend]" "$GL" '' $'useDefault = true\n'
write 2 "new file with useDefault under a rule" "$GL" '' $'[[rules]]\nid = "acme-key"\nuseDefault = true\n'
says yes "tool's docs (gitleaks)" "the stop sends the agent to gitleaks's docs first" "$APP" 'KEY = "k"' 'KEY = "k"  # gitleaks:allow'
says yes "revoke a real secret" "the stop says a real secret is revoked, not skipped" "$APP" 'KEY = "k"' 'KEY = "k"  # gitleaks:allow'
says yes "Write it in this form: gitleaks:allow <reason>" "the stop shows the inline form" "$APP" 'KEY = "k"' 'KEY = "k"  # gitleaks:allow'
says yes "Add it, or add the reason as a comment" "the stop says how to keep gitleaks's own rules" "$GL" "$OWN" ''

echo "-- secret scan skips: a reason in the form where gitleaks keeps it (goes on)"
edit 0 "gitleaks:allow + reason after it" "$APP" 'KEY = "k"' "KEY = \"k\"  # gitleaks:allow a fixture key. $TRIED"
edit R "gitleaks:allow + reason above"    "$APP" 'KEY = "k"' $'# A fixture key.\n# '"$TRIED"$'\nKEY = "k"  # gitleaks:allow'
edit 0 "gitleaks:allow in YAML + reason after it" "$YAML" 'key: k' "key: k  # gitleaks:allow a fixture key. $TRIED"
edit 0 "gitleaks:allow in Markdown + reason in its comment" "$DOC" 'key k' "key k <!-- gitleaks:allow an example key. $TRIED -->"
edit 0 "edit next to an old bare gitleaks:allow" "$APP" $'KEY = "k"  # gitleaks:allow\nx = 1' $'KEY = "k"  # gitleaks:allow\nx = 2'
write 0 "fingerprint + reason above"      "$IGNORE" '' "# A fixture key. $TRIED"$'\ntests/a.py:github-pat:3\n'
write 0 "a comment in .gitleaksignore"    "$IGNORE" '' $'# Fingerprints of fixture keys.\n'
edit_in R "allowlist path + reason above" "$GL" "$OWN" "$OWN" \
  "$OWN"$'\n[[allowlists]]\n'"# Fixture keys. $TRIED"$'\n'"paths = [${Q}^tests/${Q}]"
edit_in R "disabledRules entry + reason on its line" "$GL" "$OWN" "$OWN" \
  "$OWN""disabledRules = [\"generic-api-key\"]  # generic-api-key: fixture keys. $TRIED"
edit_in R "new file without useDefault + reason" "$GL" '' '' \
  "# This project scans only for its own key. $TRIED"$'\n[[rules]]\nid = "acme-key"\n'
edit_in 0 "a rule added to a file that keeps useDefault" "$GL" "$OWN" "$OWN" \
  "$OWN"$'\n[[rules]]\nid = "acme-key"\n'"regex = ${Q}acme_[a-z0-9]{32}${Q}"
edit_in 0 "an allowlist description added" "$GL" "$OWN"$'\n[[allowlists]]\npaths = ["x"]\n' '[[allowlists]]' \
  $'[[allowlists]]\ndescription = "Fixtures"'
edit_in 0 "an allowlist path removed"     "$GL" "$OWN"$'\n[[allowlists]]\npaths = ["x"]\n' $'paths = ["x"]\n' ''
write 0 "new file that keeps useDefault"  "$GL" '' "$OWN"
write 0 "new file with extend.useDefault outside any table" "$GL" '' $'extend.useDefault = true\n'
edit R "gitleaks:allow + reason above that names gitleaks" "$APP" 'KEY = "k"' \
  "# gitleaks flags a fixture key. $TRIED"$'\nKEY = "k"  # gitleaks:allow'
write 0 "fingerprint + reason above that names gitleaks" "$IGNORE" '' \
  "# gitleaks flags a fixture key. $TRIED"$'\ntests/a.py:github-pat:3\n'
edit R "noqa + reason above that names gitleaks" "$APP" 'x = 1' "# gitleaks flags the URL. $TRIED"$'\nx = 1  # noqa: E501'
mkdir -p "$REPO/docs"
write 0 "a .gitleaks.toml below the root" "$REPO/docs/.gitleaks.toml" '' $'[[allowlists]]\npaths = ["x"]\n'
write 0 "a .gitleaksignore below the root" "$REPO/docs/.gitleaksignore" '' $'tests/a.py:github-pat:3\n'

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
