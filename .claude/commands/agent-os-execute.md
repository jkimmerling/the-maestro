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

/execute-task "Implement Epic $ARGUMENTS[0], Story $ARGUMENTS[1]. Reference the acceptance criteria in /home/jasonk/the_maestro/project_specs/prd.md and use .agent-os/product/ for technical stack and decisions. Refer to /home/jasonk/the_maestro/gemini-cli-source if you need to reference the source code we are trying to port to Elixir  ---  ALWAYS MAKE THE NEW BRANCH BEFORE YOU START WRITING/EDITING  --- create the TDD tests, use the code-reviewer for quality checks, use the qa-expert before the final push to verify good code quality at the end: please git add. > git commit (with a detailed message) > git push > create a pr (with a detailed message) 

MANDATORY: Fix ALL test failures completely. Do not skip, ignore, or work around any failing tests. If a test is failing, you MUST investigate the root cause and implement a proper fix. Never suggest disabling tests or using mocks to bypass real issues. Every single test must pass before the task is considered complete.

When you encounter test failures, your job is to dig deep and fix the underlying issues, not to find shortcuts. Treat test failures as critical bugs that must be resolved, not obstacles to work around."  --mode=tdd