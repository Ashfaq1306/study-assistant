---
description: Take the current task through the full pipeline (junior → senior → review → QA) and open a pull request
argument-hint: <what to build or fix>
---

Deliver this through the Study Assistant pipeline: $ARGUMENTS

1. Make sure you are on a feature branch off an up-to-date `main` (`feat/…`, `fix/…`, `chore/…`), never on `main` itself.
2. **junior-coder:** implement the task with tests. If the task needs a design decision, run **senior-coder** first to plan it, then hand the plan to junior-coder.
3. **senior-coder:** harden the diff (design, security, performance, product rules).
4. **code-reviewer:** review against `main`. On REQUEST CHANGES, send the blocking findings back to senior-coder and review again until APPROVE.
5. **qa-tester:** run every check and test on a device. On FAIL, fix the problem (through the coders) and run QA again.
6. Update `README.md` and `.gitignore` if the change needs it.
7. Commit in logical conventional commits (`feat(app): …`, `fix(api): …`). The author is the repo's configured git user. **No `Co-Authored-By` trailers and no AI attribution.**
8. `git push -u origin HEAD` and `gh pr create` using `.github/pull_request_template.md`. Fill in the review verdict and QA evidence. No AI attribution footer.
9. Reply with the PR link and a summary.
