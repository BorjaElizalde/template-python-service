# From the python-service template: change the template, not this copy.
# Python helpers for the practice modules, which include it after lib.jq (jq includes do not pass
# on the definitions they bring in). stack.json, rendered from the template answers, names
# the application package.
include "lib";
import "stack" as $stack;

def package: $stack[0].package;
def in_package: startswith(package + "/");
def directive: "^\\s*#\\s*(fmt|noqa|type|pyright|nosec|pragma|ruff)\\b|^\\s*#!";
def plain_comment: has("^\\s*#\\s*[a-z0-9]") and (has(directive) | not);
