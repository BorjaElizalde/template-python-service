# From the python-service template: change the template, not this copy.
# REMIND on every new docstring: on the outside surface to write for that reader, elsewhere to ask
# whether better code would say it instead. STOP on a module docstring anywhere but in a migration
# (Alembic shows it as the revision message), and on a docstring that lists parameters, return
# values or exceptions (comments-and-docstrings.md). An MCP tool keeps its Args:
# section: fastmcp writes it into the tool's input schema as the parameter descriptions, and once a
# docstring has one it drops the Returns: and Raises: sections. Python makes a str literal a
# docstring when it is the first statement of the module or of a def or class body; b- and
# f-strings never are.
include "lib";
include "python";

def surface:
  test("^" + package + "/(api/v1/(routers/.+|responses|core/schemas)|api/mcp/(tools/.+|responses)"
    + "|batch/main|types)\\.py$");
def migration: test("^database/versions/[^/]+\\.py$");
def mcp_tool: test("^" + package + "/api/mcp/tools/.+\\.py$");
def string_start: has("^\\s*[ur]?(\"\"\"|'''|\"[^\"]*\"\\s*(#.*)?$|'[^']*'\\s*(#.*)?$)");
def bare_quote: has("^\\s*[ur]?(\"\"\"|''')\\\\?\\s*$");
def opens_body: sub("\\s+#.*$"; "") | has("^\\s*((async\\s+)?def|class)\\s.*:$|^\\s*[)\\]].*:$");
def code: trimmed | . != "" and (startswith("#") | not);
def param_list: has("^\\s*(args|arguments|parameters|params)\\s*:?\\s*$|^\\s*:(param|type)\\b");
def result_list: has("^\\s*(returns?|yields|raises)\\s*:?\\s*$|^\\s*:(returns?|rtype|raises?)\\b");
def param_section: param_list or result_list;

def code_above($new; $i): first(range($i - 1; -1; -1) | select($new[.] | code)) // null;

def docstring_at($new; $i):
  ($new[$i] | string_start)
  and (code_above($new; $i) as $p | $p == null or ($new[$p] | opens_body));

# From the opening quote to the closing one; an unclosed one runs to the end of the file.
def docstring_lines($new; $i):
  [$new[$i] | match("\"\"\"|'''"; "g").string] as $quotes
  | if ($quotes | length) == 1 then
      (first(range($i + 1; $new | length) | select($new[.] | contains($quotes[0]))) as $end
       | $new[$i:$end + 1])
      // $new[$i:]
    else [$new[$i]] end;

def opener_above($new; $i): first(range($i - 1; -1; -1) | select($new[.] | test("\"\"\"|'''")));

# The docstrings this edit adds, plus old ones it adds a parameter section to. A bare opening
# quote's text is often already in the file, so its first text line counts as well.
def edited_docstrings($ctx):
  $ctx.new as $new
  | ($ctx.added | map(.at)) as $added
  | ([$added[] | ., (. - 1 | select(. >= 0 and ($new[.] | bare_quote)))] | unique) as $starts
  | [$added[] | select($new[.] | param_section) | opener_above($new; .)] as $holders
  | $starts + $holders | unique
  | map(select(docstring_at($new; .)) as $i
        | {new: ($starts | index($i) != null), module: (code_above($new; $i) == null),
           line: (if $new[$i] | bare_quote then $new[$i + 1] // $new[$i] else $new[$i] end),
           sections: [docstring_lines($new; $i)[] | select(param_section)]});

def count_more: if length > 1 then " (and \(length - 1) more)" else "" end;

def check($ctx):
  ($ctx.rel | surface) as $surface
  | ($ctx.rel | migration) as $migration
  | ($ctx.rel | mcp_tool) as $mcp_tool
  | edited_docstrings($ctx)
  | map(.param = [.sections[] | select(($mcp_tool | not) or result_list)][0])
  | map(select(.new and .module and ($migration | not)) | .line) as $modules
  | map(select(.param != null)) as $params
  | map(select(.new and (.module | not)) | .line) as $added
  | ($mcp_tool and any(.[].sections[]; param_list)) as $mcp_args
  | if ($modules + $params | length) > 0 then
      (select($modules != [])
       | {level: "stop", text: ("Stopped by the practices hook, docstring rule"
           + " (.claude/rules/comments-and-docstrings.md). This edit adds a"
           + " module docstring:\n" + ($modules | map("- `\(short)`") | join("\n"))
           + "\nModules don't get docstrings in this codebase, except a migration's, which Alembic"
           + " shows as the revision message. Remove it. If it held something the code can't show,"
           + " keep only that, in the docstring of the function or class it is about or as a"
           + " one-line comment where it applies.")}),
      (select($params != [])
       | {level: "stop", text: ("Stopped by the practices hook, docstring rule"
           + " (.claude/rules/comments-and-docstrings.md). This docstring lists"
           + " parameters, return values or exceptions:\n"
           + ($params | map("- `\(.line | short)`: `\(.param | trimmed)`") | join("\n"))
           + "\n"
           + if $mcp_tool then
               "On an MCP tool only an Args: section has a reader: fastmcp writes it into the"
               + " tool's schema as the parameter descriptions. Once a docstring has one, fastmcp"
               + " drops its Returns: and Raises: sections, and without one they are plain text."
               + " Remove that section and say what comes back and which errors in the"
               + " description itself."
             else
               "The signature and its types already say that. Remove that section. On a function,"
               + " method, class or test, keep only why it exists or how a caller must use it, in"
               + " one or two sentences, or remove the docstring."
             end)})
    elif $added == [] then empty
    elif $surface then
      {level: "remind", text: ("Practices hook, docstring rule"
        + " (.claude/rules/comments-and-docstrings.md). This docstring is read outside the code"
        + " (API docs, SDK hover"
        + " text, MCP client or --help): `\($added[0] | short)`\($added | count_more). Write for"
        + " that reader in one to three sentences: what it does for them, what to send, what comes"
        + " back, and which errors come back by their ``ERR_...`` code. No internals (tables,"
        + " sessions, transactions, internal steps, other modules, history). A helper in this file"
        + " has no outside reader, so the bar for internal code applies to it instead: one or two"
        + " sentences on why it exists or how a caller must use it, and only if a clearer name or"
        + " simpler code can't say it."
        + if $mcp_args then
            " On an MCP tool, the Args: section becomes the parameter descriptions in the tool's"
            + " schema. Put it last: fastmcp keeps only the text before it as the tool's"
            + " description."
          else "" end)}
    else
      {level: "remind", text: ("Practices hook, docstring rule"
        + " (.claude/rules/comments-and-docstrings.md). This edit adds a docstring:"
        + " `\($added[0] | short)`"
        + ($added | count_more) + ". This codebase prefers code that explains itself. Before"
        + " keeping it, ask: could a clearer name, a smaller function or a simpler structure say"
        + " this instead, without hurting performance or the design? If so, change the code and"
        + " drop the docstring. " + durability + " Keep it only if it says why this exists or"
        + " how a caller must use it, something a reader can't work out from the code and its"
        + " name: a contract to respect, a required order of calls, a side effect to expect. One"
        + " or two sentences; no parameters, return values or exceptions; nothing the code"
        + " already shows; no history.")}
    end;
