# Mutation Safety

Change persistent state only as needed for the result the user requested.
Require explicit authorization for destructive or hard-to-reverse actions and
mutations to external or shared systems.

Before mutating, confirm the target and scope. Preserve unrelated or
uncertain-ownership work, including concurrent changes; ask before overwriting
or reverting it.
