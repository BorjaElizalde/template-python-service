---
paths:
  - "**/*.py"
---

# MCP conventions

- MCP tools and the MCP response models have outside-facing docstrings
  (`.claude/rules/python-conventions.md`, Docstrings): the LLM reads them. They name each error
  that comes back by its ``ERR_...`` code
- A tool's docstring may end with an `Args:` section, the one exception to the rule on parameter
  lists: fastmcp writes it into the tool's schema as the parameter descriptions the LLM reads. It
  goes last, because fastmcp keeps only the text before it as the tool's description and drops the
  `Returns:` and `Raises:` sections
