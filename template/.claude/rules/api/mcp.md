---
paths:
  - "**/*.py"
---

# MCP conventions

- MCP tools and the MCP response models have outside-facing docstrings: the LLM reads them
- A tool's docstring may end with an `Args:` section, the one exception to the rule on parameter
  lists: fastmcp writes it into the tool's schema as the parameter descriptions the LLM reads. It
  goes last, because fastmcp keeps only the text before it as the tool's description and drops the
  `Returns:` and `Raises:` sections
