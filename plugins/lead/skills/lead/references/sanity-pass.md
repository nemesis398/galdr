# Sanity pass before each wave

The plan is the only contract the workers read, so check it before any of
them starts. Fix what fails in the plan's own text, then dispatch.

1. **One owner per file.** Every file the wave touches belongs to exactly one
   task. Two tasks of the same wave that both edit a file are merged, or one
   moves to the next wave.
2. **Names match on both sides.** Every name, path, signature, data shape and
   key that one task produces and another consumes reads the same in both
   Interfaces blocks.
3. **Every ruling is in the text.** A decision made since the plan was written
   (by the user, by a review, by an earlier wave) is written into the plan's
   section that needs it. A ruling that lives only in the lead's context never
   reaches the worker.
4. **Every task carries a category** (`scout`, `edit`, `build`, `review`), and
   its start rung lies inside that category's range. An old `(opus)` becomes
   `(build, rung 5)`; a task without a tag becomes `(build)`. Correct a tag
   that is plainly wrong, and say so in the tick line.
5. **Every task fits its turn budget**: scout 20, edit 15, build 50, review 40.
   A task that will not fit is split, in the plan.
6. **Slow states have a hook.** A task whose acceptance needs a state that is
   slow to reach names the flag, seed or URL parameter that reaches it.
