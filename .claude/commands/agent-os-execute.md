---
description: "Execute Agent OS epic and story implementation with context from PRD and technical specs"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob"]
---

# Agent OS Execute Command

Execute the implementation of a specific epic and story from the Agent OS project.

Usage: `/agent-os-execute <epic_number> <story_number>`

Arguments:
- Epic Number: $ARGUMENTS[0]
- Story Number: $ARGUMENTS[1]

/execute-task "Implement Epic $ARGUMENTS[0], Story $ARGUMENTS[1]. Reference the acceptance criteria in use .agent-os/product/ for technical stack and decisions. Refer to /Users/jasonk/Development/cleanops_elixir/clean_ops_original_source if you need to reference the source code for features we need  ---  ALWAYS MAKE THE NEW BRANCH BEFORE YOU START WRITING/EDITING  --- create the TDD tests, use the code-reviewer for quality checks, use the qa-expert before the final push to verify good code quality at the end. ALL STORY TASKS REQUIRE 100% IMPLEMENTATION, NO PLACEHOLDERS, NO MOCKS (unless in tests), WE NEED 100000% FULLY WORKING FEATURES. please git add. > git commit (with a detailed message) > git push > create a pr (with a detailed message) --- Follow professional design system standards for UI/UX implementation. Use Playwright MCP for visual regression testing to ensure consistent quality and responsive design across all breakpoints."  --mode=tdd