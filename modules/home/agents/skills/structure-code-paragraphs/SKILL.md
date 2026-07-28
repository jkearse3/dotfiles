---
name: structure-code-paragraphs
description: >-
  Structures source code into semantic paragraphs separated by blank lines so
  each phase of logic is easy to scan. Use whenever writing, editing,
  generating, or refactoring source code. Keep atomic operations together,
  respect required formatters, and avoid reformatting unrelated code.
---

# Structure Code Paragraphs

Use blank lines as semantic delimiters. Each paragraph should perform one
coherent step, and a blank line should signal that the next step has a distinct
purpose in the flow of the function.

Apply this skill to all source-code changes. Apply it fully to new or
substantially rewritten code, but do not reformat untouched code merely to make
an existing file conform.

## Form Paragraphs

Group statements that must be understood together. Start a new paragraph when
the code changes phase, such as:

- preparing inputs before performing an operation;
- moving from an operation and its validation to consuming its result;
- finishing state derivation before producing a side effect;
- changing the subject, abstraction level, or data-flow stage;
- completing setup before entering the main control flow.

Keep short, indivisible work in one paragraph. Blank lines should expose the
structure already present in the logic, not manufacture extra stages.

## Keep Atomic Groups Together

Do not insert blank lines where separation would obscure a direct relationship.
In particular, keep together:

- an operation and its immediate error handling;
- a condition and its body;
- a value declaration and the statements that directly construct it;
- adjacent statements that jointly express one calculation or invariant;
- a comment and the code it explains.

For example:

```go
x := "thing"

y, err := do(x)
if err != nil {
	return err
}

print(y)
```

The assignment establishes the input, the call and error check form one atomic
operation, and the final statement consumes the successful result.

Avoid flattening those phases together:

```go
x := "thing"
y, err := do(x)
if err != nil {
	return err
}
print(y)
```

Also avoid fragmenting the atomic operation:

```go
y, err := do(x)

if err != nil {
	return err
}
```

## Preserve Local Clarity

- Prefer one blank line between paragraphs. Do not use repeated blank lines as
  stronger separators inside a function.
- Do not add a blank line after every statement. A paragraph may contain several
  tightly related statements.
- Keep compact branches and loops compact when their internal steps are one
  coherent unit.
- Use extraction, naming, or comments rather than whitespace when the logic is
  too complex for paragraph boundaries to explain.
- Follow mandatory language formatters and established syntax conventions when
  they control or reject blank-line placement.
- Avoid whitespace-only changes outside code already touched by the requested
  work.

## Check The Flow

Before completing changed code, scan each function from top to bottom:

1. Identify the semantic purpose of each paragraph.
2. Confirm every blank line marks a real transition.
3. Confirm directly related statements remain together.
4. Confirm the paragraph sequence communicates the function's control and data
   flow without requiring line-by-line parsing.
5. Run the project's formatter and inspect its resulting layout.

Optimize for semantic scanability, not the number of blank lines.
