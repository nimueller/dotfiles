# Git workflow

## With a remote: always a pull request

If the repository has a remote (`git remote` is not empty), never commit or
push directly to the main branch (`main`/`master`). Instead:

1. Create a branch with a descriptive name, e.g. `fix/…`, `feat/…`,
   `chore/…`.
2. Commit there and push the branch.
3. Open a pull request against the main branch with `gh pr create` and
   output the link to it.
4. Don't merge it yourself unless I explicitly say so.

Exception: only when I explicitly say in the session to commit/push directly
to `main` does that apply, and only for that one change.

## Without a remote: commit directly

If the repository has no remote, committing directly to the current branch is
normally fine. This only applies inside a Git repository; outside of one, don't
create a repository without asking.

## Pull request description

The PR description must explain the change precisely and completely, so that
it is understandable without the chat history. It always contains these
sections:

- **Background:** What was the state before, and what prompted the change?
- **Problem:** What exactly was wrong or missing? For bugs: the symptom, the
  cause, and how the cause was found.
- **Solution / concept:** What does the PR change, and why this way? Name
  important design decisions and rejected alternatives.
- **Testing:** How was the change verified, and with what result?
- **Possible issues / TODOs:** Risks, side effects, open points or follow-up
  work. Only include this section if there are any.
