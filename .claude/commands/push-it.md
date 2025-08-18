---
description: "Aggressively push code with full validation pipeline - no excuses, fix everything"
allowed-tools: ["Bash", "Read", "Edit", "MultiEdit", "Grep", "Glob", "Bash(timeout 3600 git push)", "Bash(timeout 18000 git push)", "Bash(timeout 21600 git push)", "Bash(git push --no-verify)", "Bash(git push origin *)", "Bash(git push -u origin *)", "Bash(git push --set-upstream origin *)", "Bash(timeout * git push *)", "Bash(timeout * ./scripts/pre-push.sh)", "Bash(timeout * mix test)", "Bash(timeout * mix credo)", "Bash(timeout * mix format)", "Bash(timeout * mix compile)"]
---

# Push It Command - No Excuses Mode

Push the fucking code and make it pass everything. Run all pre-push hooks, tests, linting, credo, and whatever else needs to run. Fix every single failure until 100% pass rate is achieved.

Usage: `/push-it [branch_name]`

Arguments:
- Branch Name (optional): $ARGUMENTS[0] - defaults to current branch

This command will:
1. Run all pre-push hooks with extended timeouts (up to 6 hours if needed)
2. Fix ALL test failures
3. Fix ALL linting issues  
4. Fix ALL credo issues
5. Fix ALL compilation warnings
6. Achieve 100% pass rate on everything
7. Push the code successfully with extended timeout (no cancellation due to slowness)

No excuses. No shortcuts. Fix everything. Let it run as long as it takes.

/execute-task "AGGRESSIVE PUSH MODE: Push the current branch with zero tolerance for failures and unlimited time tolerance.

Step 1: Check current branch status and add all changes
Step 2: Run pre-push hooks with extended timeout (timeout 21600 for up to 6 hours)
Step 3: If ANYTHING fails (tests, linting, credo, compilation), FIX IT IMMEDIATELY
Step 4: Re-run validation with extended timeouts until 100% pass rate achieved
Step 5: Commit with detailed message about all fixes applied  
Step 6: Push with extended timeout (timeout 3600 git push or higher) - DO NOT cancel due to slowness
Step 7: Verify push completed successfully

ZERO TOLERANCE POLICY:
- Fix every test failure, no matter how long it takes
- Fix every linting error and warning
- Fix every credo issue  
- Fix every compilation warning
- Achieve 100% pass rate on all validation
- No skipping, no shortcuts, no excuses
- Use extended timeouts - let processes run for hours if needed

TIMEOUT STRATEGY:
- Use timeout 21600 (6 hours) for pre-push hooks
- Use timeout 3600 (1 hour) minimum for git push operations
- Increase timeouts as needed - speed is irrelevant, success is everything" --mode=aggressive-qa