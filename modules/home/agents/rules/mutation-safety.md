# Mutation Safety

Change persistent state only as needed for the result the user requested. Get
explicit authorization before destructive or hard-to-reverse actions and
mutations to external or shared systems.

Before mutating, confirm the target and scope. Preserve work that is unrelated
or whose owner is unclear, including concurrent changes; ask before overwriting
or reverting it.
